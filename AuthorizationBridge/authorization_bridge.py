"""
20-20 TOOLBOX · AuthorizationBridge v1.0
Local-only PAdES signing service for the Toolbox PDF authorization module.

Security model:
- binds exclusively to 127.0.0.1
- never persists PFX/P12 files or passphrases
- certificate material is kept only for the lifetime of a request
- signed documents are returned as an in-memory ZIP
"""

from __future__ import annotations

import io
import json
import os
import re
import secrets
import asyncio
import hashlib
import ctypes
import subprocess
import base64
import tempfile
import traceback
import zipfile
from datetime import datetime, timezone, timedelta
from urllib.parse import urlparse
from pathlib import Path
from typing import Any, Optional, Dict, List, Tuple

from flask import Flask, jsonify, request, send_file, Response
import pyhanko
from pyhanko import stamp
from pyhanko.pdf_utils import images
from pyhanko.pdf_utils.incremental_writer import IncrementalPdfFileWriter
from pyhanko.sign import fields, signers, timestamps
from pyhanko.sign.timestamps.dummy_client import DummyTimeStamper
from asn1crypto import x509 as asn1_x509, algos, keys as asn1_keys, tsp
from aiohttp import BasicAuth

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID


APP_VERSION = "2.1.1"
HOST = "127.0.0.1"
PORT = 8094
MAX_BYTES = 600 * 1024 * 1024

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = MAX_BYTES

# Browser security boundary. The bridge is localhost-only, but localhost services
# can still be targeted by arbitrary websites unless Origin + an unguessable
# per-process token are enforced.
_DEFAULT_TRUSTED_ORIGINS = {
    "https://parancze.github.io",
    "https://20-20.cz",
    "https://www.20-20.cz",
}
_TRUSTED_ORIGINS = {
    x.strip().rstrip("/")
    for x in os.environ.get("TWENTY20_AUTH_ORIGINS", ",".join(sorted(_DEFAULT_TRUSTED_ORIGINS))).split(",")
    if x.strip()
}
_SESSION_TOKEN = secrets.token_urlsafe(32)
_ALLOW_LOCALHOST_ORIGINS = os.environ.get("TWENTY20_AUTH_ALLOW_LOCALHOST", "").strip() == "1"
_TEST_TSA_USER = "TEST"
_TEST_TSA_PASSWORD = "TEST-ONLY"
_TEST_TSA = None
_PREFLIGHTS: Dict[str, Dict[str, Any]] = {}
_SIGN_APPROVALS: Dict[str, Dict[str, Any]] = {}
_APPROVAL_TTL_SECONDS = 600


def _origin_allowed(origin: Optional[str]) -> bool:
    if not origin:
        return False
    origin = origin.rstrip("/")
    if origin in _TRUSTED_ORIGINS:
        return True
    if _ALLOW_LOCALHOST_ORIGINS:
        return bool(re.match(r"^http://(?:127\.0\.0\.1|localhost)(?::\d+)?$", origin, re.I))
    return False


def _request_token_ok() -> bool:
    supplied = request.headers.get("X-20-20-Session", "")
    return bool(supplied) and secrets.compare_digest(supplied, _SESSION_TOKEN)


@app.before_request
def protect_local_bridge():
    origin = request.headers.get("Origin")

    # Native health checks (PowerShell installer) carry no Origin and are safe.
    if request.path == "/status" and request.method == "GET" and not origin:
        return None

    # Local RFC 3161 TEST TSA is called by the bridge itself over loopback.
    # It has its own Basic Auth gate and never accepts non-loopback clients.
    if request.path == "/test-tsa" and request.method == "POST" and not origin:
        return None

    # Browser access is restricted to the Toolbox origins.
    if origin and not _origin_allowed(origin):
        return jsonify(ok=False, error="Nepovolený webový původ požadavku."), 403

    if request.method == "OPTIONS":
        if not origin or not _origin_allowed(origin):
            return jsonify(ok=False, error="Nepovolený CORS požadavek."), 403
        return ("", 204)

    if request.path == "/session":
        if not origin or not _origin_allowed(origin):
            return jsonify(ok=False, error="Session lze vytvořit pouze z důvěryhodného Toolboxu."), 403
        return None

    if request.path == "/status" and request.method == "GET":
        if origin and not _origin_allowed(origin):
            return jsonify(ok=False, error="Nepovolený webový původ požadavku."), 403
        return None

    # Every operation that can inspect a certificate or sign documents requires
    # both a trusted browser Origin and an in-memory session token.
    if not origin or not _origin_allowed(origin):
        return jsonify(ok=False, error="AuthorizationBridge přijímá podpisové požadavky pouze z důvěryhodného Toolboxu."), 403
    if not _request_token_ok():
        return jsonify(ok=False, error="Neplatná nebo expirovaná lokální session."), 401
    return None


@app.after_request
def cors(response):
    origin = request.headers.get("Origin")
    if origin and _origin_allowed(origin):
        response.headers["Access-Control-Allow-Origin"] = origin
        response.headers["Vary"] = "Origin"
        response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
        response.headers["Access-Control-Allow-Headers"] = "Content-Type, X-20-20-Session"
        response.headers["Access-Control-Allow-Private-Network"] = "true"
    response.headers["Cache-Control"] = "no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    return response


@app.route("/<path:_path>", methods=["OPTIONS"])
@app.route("/", methods=["OPTIONS"])
def options(_path: str = ""):
    return ("", 204)


@app.get("/session")
def session():
    return jsonify(ok=True, token=_SESSION_TOKEN)


def _cleanup_approvals() -> None:
    now = datetime.now(timezone.utc).timestamp()
    for store in (_PREFLIGHTS, _SIGN_APPROVALS):
        stale = [
            token for token, item in store.items()
            if float(item.get("expires", 0)) <= now or bool(item.get("used"))
        ]
        for token in stale:
            store.pop(token, None)


def _approval_context(meta: Dict[str, Any], document_count: int) -> Dict[str, Any]:
    tsa_password = str(meta.get("tsa_password") or "")
    return {
        "certificate_thumbprint": re.sub(r"\s+", "", str(meta.get("certificate_thumbprint") or "")).upper(),
        "profile": str(meta.get("profile") or "bt").lower(),
        "tsa_url": str(meta.get("tsa_url") or "").strip(),
        "tsa_user": str(meta.get("tsa_user") or "").strip(),
        "tsa_credential_hash": hashlib.sha256(
            (str(meta.get("tsa_user") or "") + "\0" + tsa_password).encode("utf-8")
        ).hexdigest(),
        "tsa_test_mode": bool(meta.get("tsa_test_mode", False)),
        "document_count": int(document_count),
    }


def _canonical_signing_intent(meta: Dict[str, Any], stamp_bytes: bytes) -> Dict[str, Any]:
    docs = meta.get("documents")
    if not isinstance(docs, list):
        docs = []
    clean_docs = []
    for item in docs:
        item = item if isinstance(item, dict) else {}
        placement = item.get("placement")
        clean_docs.append({
            "name": str(item.get("name") or ""),
            "output_name": str(item.get("output_name") or ""),
            "placement": placement if isinstance(placement, dict) else None,
        })
    return {
        "reason": str(meta.get("reason") or ""),
        "location": str(meta.get("location") or ""),
        "contact": str(meta.get("contact") or ""),
        "append_ear": bool(meta.get("append_ear", True)),
        "documents": clean_docs,
        "stamp_sha256": hashlib.sha256(stamp_bytes or b"").hexdigest(),
        "stamp_size": len(stamp_bytes or b""),
    }


def _intent_digest(intent: Dict[str, Any]) -> str:
    payload = json.dumps(
        intent,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _native_sign_confirmation(
    cert_name: str,
    document_count: int,
    profile: str,
    tsa_url: str,
    documents: Optional[List[Dict[str, Any]]] = None,
) -> bool:
    if os.name != "nt":
        return False
    tsa_label = "bez TSA"
    if profile == "bt":
        parsed = urlparse(tsa_url)
        tsa_label = parsed.netloc or tsa_url

    docs = documents or []
    names = [str(x.get("name") or "") for x in docs if isinstance(x, dict)]
    shown = names[:6]
    file_lines = "\n".join(f"  • {name}" for name in shown if name)
    if len(names) > len(shown):
        file_lines += f"\n  … a dalších {len(names) - len(shown)}"

    batch_material = "\n".join(
        f"{str(x.get('name') or '')}|{int(x.get('size') or 0)}|{str(x.get('sha256') or '').lower()}"
        for x in docs if isinstance(x, dict)
    ).encode("utf-8")
    batch_fingerprint = hashlib.sha256(batch_material).hexdigest().upper()
    fingerprint_short = " ".join(
        batch_fingerprint[i:i+4] for i in range(0, min(len(batch_fingerprint), 32), 4)
    )

    message = (
        "20-20 TOOLBOX chce použít váš podpisový certifikát.\n\n"
        f"Certifikát: {cert_name}\n"
        f"Počet PDF: {document_count}\n"
        f"Profil: {'PAdES B-T' if profile == 'bt' else 'PAdES B-B'}\n"
        f"TSA: {tsa_label}\n"
        f"Otisk dávky: {fingerprint_short}\n\n"
        + (("Dokumenty:\n" + file_lines + "\n\n") if file_lines else "")
        + "Povolit tuto jednu podpisovou dávku?"
    )
    MB_YESNO = 0x00000004
    MB_ICONWARNING = 0x00000030
    MB_TOPMOST = 0x00040000
    result = ctypes.windll.user32.MessageBoxW(
        None,
        message,
        "20-20 TOOLBOX · Potvrzení podpisu",
        MB_YESNO | MB_ICONWARNING | MB_TOPMOST,
    )
    return result == 6


_WINDOWS_KEY_PROBE_PS = r"""
$ErrorActionPreference = 'Stop'
$thumb = ($env:TWENTY20_CERT_THUMBPRINT -replace ' ','').ToUpperInvariant()
if ($thumb -notmatch '^[0-9A-F]{40,128}def _build_timestamper(meta: Dict[str, Any]):
    profile = str(meta.get("profile") or "bt").lower()
    tsa_url = str(meta.get("tsa_url") or "").strip()
    tsa_user = str(meta.get("tsa_user") or "").strip()
    tsa_password = str(meta.get("tsa_password") or "")
    tsa_test_mode = bool(meta.get("tsa_test_mode", False))

    if profile != "bt":
        return None
    if not re.match(r"^https?://", tsa_url, re.I):
        raise ValueError("Pro PAdES B-T je nutná platná HTTP(S) adresa RFC 3161 TSA serveru.")
    if bool(tsa_user) != bool(tsa_password):
        raise ValueError("Pro přihlášení k TSA musí být vyplněn login i heslo.")

    if tsa_test_mode:
        if tsa_url != "http://127.0.0.1:8094/test-tsa":
            raise ValueError("TEST TSA musí používat lokální adresu 127.0.0.1:8094/test-tsa.")
        if not (
            secrets.compare_digest(tsa_user, _TEST_TSA_USER)
            and secrets.compare_digest(tsa_password, _TEST_TSA_PASSWORD)
        ):
            raise PermissionError("Neplatný TEST TSA login nebo heslo.")
        return _get_test_tsa()

    auth = BasicAuth(tsa_user, tsa_password) if tsa_user else None
    return timestamps.HTTPTimeStamper(tsa_url, auth=auth, timeout=15)


def _verify_tsa_login(timestamper) -> None:
    if timestamper is None:
        return
    probe_digest = hashlib.sha256(b"20-20 TOOLBOX TSA PREFLIGHT").digest()
    asyncio.run(timestamper.async_timestamp(probe_digest, "sha256"))


def _fmt_dt(value: Any) -> str:
    try:
        if value is None:
            return ""
        if hasattr(value, "astimezone"):
            value = value.astimezone()
        return value.strftime("%d.%m.%Y %H:%M:%S %Z").strip()
    except Exception:
        return str(value)



def _run_powershell(script: str, env_extra: Optional[Dict[str, str]] = None, timeout: int = 30) -> str:
    if os.name != "nt":
        raise RuntimeError("Windows Certificate Store je dostupný pouze ve Windows.")
    env = os.environ.copy()
    if env_extra:
        env.update(env_extra)
    proc = subprocess.run(
        ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "-"],
        input=script,
        text=True,
        capture_output=True,
        env=env,
        timeout=timeout,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "PowerShell selhal.").strip()
        raise RuntimeError(detail)
    return (proc.stdout or "").strip()


_WINDOWS_CERT_LIST_PS = r"""
$ErrorActionPreference = 'Stop'
$items = @()

$stores = @(
  @{ Path = 'Cert:\CurrentUser\My'; Location = 'CurrentUser' },
  @{ Path = 'Cert:\LocalMachine\My'; Location = 'LocalMachine' }
)

foreach ($entry in $stores) {
  try {
    $certs = @(Get-ChildItem -Path $entry.Path -ErrorAction Stop)
  } catch {
    continue
  }

  foreach ($cert in $certs) {
    try {
      $oid = ''
      $friendly = ''
      try { $oid = [string]$cert.PublicKey.Oid.Value } catch {}
      try { $friendly = [string]$cert.PublicKey.Oid.FriendlyName } catch {}

      $keyType = 'UNKNOWN'
      if ($oid -eq '1.2.840.113549.1.1.1' -or $friendly -match 'RSA') {
        $keyType = 'RSA'
      } elseif ($oid -eq '1.2.840.10045.2.1' -or $friendly -match 'ECC|ECDSA') {
        $keyType = 'ECDSA'
      }

      $keyBits = 0
      if ($keyType -eq 'RSA') {
        try {
          $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($cert)
          if ($null -ne $rsa) {
            $keyBits = $rsa.KeySize
            $rsa.Dispose()
          }
        } catch {}
      }

      $items += [pscustomobject]@{
        thumbprint = (($cert.Thumbprint -replace ' ','').ToUpperInvariant())
        display_name = $cert.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName,$false)
        subject = [string]$cert.Subject
        issuer = [string]$cert.Issuer
        serial = [string]$cert.SerialNumber
        valid_from = $cert.NotBefore.ToString('o')
        valid_to = $cert.NotAfter.ToString('o')
        has_private_key = [bool]$cert.HasPrivateKey
        key_type = $keyType
        key_bits = $keyBits
        supported = [bool]($cert.HasPrivateKey -and $keyType -eq 'RSA')
        store_location = [string]$entry.Location
        store_name = 'My'
      }
    } catch {
      continue
    }
  }
}

@($items | Sort-Object valid_to -Descending) | ConvertTo-Json -Compress -Depth 4
"""


_WINDOWS_CERT_DER_PS = r"""
$ErrorActionPreference = 'Stop'
$thumb = ($env:TWENTY20_CERT_THUMBPRINT -replace ' ','').ToUpperInvariant()
$outFile = $env:TWENTY20_CERT_FILE

if ($thumb -notmatch '^[0-9A-F]{40,128}$') { throw 'Neplatný thumbprint certifikátu.' }
if ([string]::IsNullOrWhiteSpace($outFile)) { throw 'Chybí dočasná cesta pro veřejný certifikát.' }

$cert = Get-ChildItem -Path 'Cert:\CurrentUser\My' -ErrorAction Stop |
  Where-Object { (($_.Thumbprint -replace ' ','').ToUpperInvariant()) -eq $thumb } |
  Select-Object -First 1

if ($null -eq $cert) {
  $cert = Get-ChildItem -Path 'Cert:\LocalMachine\My' -ErrorAction SilentlyContinue |
    Where-Object { (($_.Thumbprint -replace ' ','').ToUpperInvariant()) -eq $thumb } |
    Select-Object -First 1
}

if ($null -eq $cert) { throw 'Vybraný certifikát nebyl nalezen ve Windows úložišti.' }
if (-not $cert.HasPrivateKey) { throw 'Vybraný certifikát nemá dostupný privátní klíč.' }

Export-Certificate -Cert $cert -FilePath $outFile -Type CERT -Force | Out-Null
"""


_WINDOWS_RSA_SIGN_PS = r"""
$ErrorActionPreference = 'Stop'
$thumb = ($env:TWENTY20_CERT_THUMBPRINT -replace ' ','').ToUpperInvariant()
if ($thumb -notmatch '^[0-9A-F]{40,128}$') { throw 'Neplatný thumbprint certifikátu.' }
$data = [Convert]::FromBase64String($env:TWENTY20_SIGN_DATA)
$store = New-Object System.Security.Cryptography.X509Certificates.X509Store('My','CurrentUser')
$store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
try {
  $cert = $store.Certificates | Where-Object { (($_.Thumbprint -replace ' ','').ToUpperInvariant()) -eq $thumb } | Select-Object -First 1
  if ($null -eq $cert) { throw 'Vybraný certifikát už není ve Windows úložišti.' }
  if (-not $cert.HasPrivateKey) { throw 'Privátní klíč vybraného certifikátu není dostupný.' }
  $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
  if ($null -eq $rsa) { throw 'Toolbox zatím podporuje podpis certifikátem s RSA privátním klíčem.' }
  try {
    $sig = $rsa.SignData(
      $data,
      [System.Security.Cryptography.HashAlgorithmName]::SHA256,
      [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
    )
    [Convert]::ToBase64String($sig)
  } finally {
    $rsa.Dispose()
  }
} finally {
  $store.Close()
}
"""


def _windows_certificates() -> List[Dict[str, Any]]:
    raw = _run_powershell(_WINDOWS_CERT_LIST_PS, timeout=20)
    if not raw:
        return []
    data = json.loads(raw)
    if isinstance(data, dict):
        data = [data]
    if not isinstance(data, list):
        return []
    now = datetime.now(timezone.utc)
    out: List[Dict[str, Any]] = []
    for item in data:
        if not isinstance(item, dict):
            continue
        try:
            valid_to = datetime.fromisoformat(str(item.get("valid_to") or "").replace("Z", "+00:00"))
            if valid_to.tzinfo is None:
                valid_to = valid_to.astimezone()
            item["expired"] = valid_to.astimezone(timezone.utc) <= now
        except Exception:
            item["expired"] = False
        out.append(item)
    return out


def _windows_cert_der(thumbprint: str) -> bytes:
    thumbprint = re.sub(r"\s+", "", str(thumbprint or "")).upper()
    if not re.fullmatch(r"[0-9A-F]{40,128}", thumbprint):
        raise ValueError("Neplatný thumbprint certifikátu.")

    temp_path = None
    try:
        fd, temp_path = tempfile.mkstemp(prefix="2020-public-cert-", suffix=".cer")
        os.close(fd)

        _run_powershell(
            _WINDOWS_CERT_DER_PS,
            {
                "TWENTY20_CERT_THUMBPRINT": thumbprint,
                "TWENTY20_CERT_FILE": temp_path,
            },
            timeout=20,
        )

        with open(temp_path, "rb") as fh:
            raw = fh.read()

        if len(raw) < 128:
            raise ValueError(
                "Windows vyexportoval neplatný veřejný certifikát "
                f"({len(raw)} B)."
            )
        return raw
    finally:
        if temp_path:
            try:
                os.remove(temp_path)
            except OSError:
                pass


def _windows_sign_data(thumbprint: str, data: bytes) -> bytes:
    raw = _run_powershell(
        _WINDOWS_RSA_SIGN_PS,
        {
            "TWENTY20_CERT_THUMBPRINT": thumbprint,
            "TWENTY20_SIGN_DATA": base64.b64encode(data).decode("ascii"),
        },
        timeout=120,
    )
    return base64.b64decode(raw, validate=True)


class WindowsStoreSigner(signers.ExternalSigner):
    def __init__(self, thumbprint: str):
        try:
            cert_der = _windows_cert_der(thumbprint)
        except Exception as exc:
            raise RuntimeError("WINDOWS CERT READ: " + str(exc)) from exc
        try:
            crypto_cert = x509.load_der_x509_certificate(cert_der)
        except Exception as exc:
            raise RuntimeError("WINDOWS CERT ASN1: " + str(exc)) from exc
        public_key = crypto_cert.public_key()
        if not isinstance(public_key, rsa.RSAPublicKey):
            raise ValueError("Toolbox zatím podporuje Windows podpisové certifikáty s RSA klíčem.")
        self.thumbprint = re.sub(r"\s+", "", thumbprint).upper()
        self.signature_size = (public_key.key_size + 7) // 8
        super().__init__(
            signing_cert=asn1_x509.Certificate.load(cert_der),
            cert_registry=None,
            signature_value=self.signature_size,
            signature_mechanism=algos.SignedDigestAlgorithm({"algorithm": "sha256_rsa"}),
        )

    async def async_sign_raw(self, data: bytes, digest_algorithm: str, dry_run: bool = False) -> bytes:
        if dry_run:
            return b"\x00" * self.signature_size
        if str(digest_algorithm or "").lower().replace("-", "") != "sha256":
            raise ValueError("Windows signer je nastavený na SHA-256.")
        return _windows_sign_data(self.thumbprint, data)



def _get_test_tsa() -> DummyTimeStamper:
    global _TEST_TSA
    if _TEST_TSA is not None:
        return _TEST_TSA

    key = rsa.generate_private_key(public_exponent=65537, key_size=3072)
    subject = issuer = x509.Name(
        [
            x509.NameAttribute(NameOID.COUNTRY_NAME, "CZ"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "20-20 TEST TSA"),
            x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, "TEST TEST TEST - NOT QUALIFIED"),
            x509.NameAttribute(NameOID.COMMON_NAME, "TEST TEST TEST - 20-20 LOCAL TSA"),
        ]
    )
    now = datetime.now(timezone.utc)
    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - timedelta(days=1))
        .not_valid_after(now + timedelta(days=3650))
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .add_extension(
            x509.KeyUsage(
                digital_signature=True,
                content_commitment=False,
                key_encipherment=False,
                data_encipherment=False,
                key_agreement=False,
                key_cert_sign=False,
                crl_sign=False,
                encipher_only=False,
                decipher_only=False,
            ),
            critical=True,
        )
        .add_extension(
            x509.ExtendedKeyUsage([ExtendedKeyUsageOID.TIME_STAMPING]),
            critical=True,
        )
        .sign(key, hashes.SHA256())
    )

    cert_der = cert.public_bytes(serialization.Encoding.DER)
    key_der = key.private_bytes(
        serialization.Encoding.DER,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    )
    _TEST_TSA = DummyTimeStamper(
        tsa_cert=asn1_x509.Certificate.load(cert_der),
        tsa_key=asn1_keys.PrivateKeyInfo.load(key_der),
        certs_to_embed=None,
        include_nonce=True,
    )
    return _TEST_TSA


@app.post("/test-tsa")
def local_test_tsa():
    try:
        if request.remote_addr not in {"127.0.0.1", "::1"}:
            return Response("TEST TSA je dostupná jen lokálně.", status=403)

        auth = request.authorization
        user_ok = bool(auth) and secrets.compare_digest(auth.username or "", _TEST_TSA_USER)
        pass_ok = bool(auth) and secrets.compare_digest(auth.password or "", _TEST_TSA_PASSWORD)
        if not (user_ok and pass_ok):
            return Response(
                "TEST TEST TEST - neplatný login k lokální TSA.",
                status=401,
                headers={"WWW-Authenticate": 'Basic realm="20-20 TEST TSA"'},
            )

        raw = request.get_data(cache=False)
        if not raw:
            return Response("Prázdný RFC 3161 požadavek.", status=400)

        ts_req = tsp.TimeStampReq.load(raw)
        ts_resp = _get_test_tsa().request_tsa_response(ts_req)
        return Response(
            ts_resp.dump(),
            status=200,
            content_type="application/timestamp-reply",
            headers={"X-20-20-Test-TSA": "TEST TEST TEST"},
        )
    except Exception as exc:
        print("[AuthorizationBridge] TEST TSA error:", traceback.format_exc(), flush=True)
        return Response("TEST TSA chyba: " + str(exc), status=400)


def _load_signer(pfx_bytes: bytes, password: str) -> signers.SimpleSigner:
    path = None
    try:
        with tempfile.NamedTemporaryFile(prefix="2020-auth-", suffix=".pfx", delete=False) as tmp:
            tmp.write(pfx_bytes)
            path = tmp.name
        signer = signers.SimpleSigner.load_pkcs12(
            path,
            passphrase=password.encode("utf-8") if password else None,
        )
        if signer is None:
            raise ValueError("Certifikát se nepodařilo načíst. Zkontroluj heslo a obsah PFX/P12.")
        return signer
    finally:
        if path:
            try:
                os.remove(path)
            except OSError:
                pass


def _make_test_signer() -> signers.SimpleSigner:
    """Create a short-lived local self-signed certificate for TEST mode."""
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = issuer = x509.Name(
        [
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "20-20 TOOLBOX"),
            x509.NameAttribute(NameOID.COMMON_NAME, "20-20 TOOLBOX TEST SIGNATURE"),
        ]
    )
    now = datetime.now(timezone.utc)
    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - timedelta(minutes=5))
        .not_valid_after(now + timedelta(days=1))
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .sign(key, hashes.SHA256())
    )
    pfx_bytes = pkcs12.serialize_key_and_certificates(
        name=b"20-20 TOOLBOX TEST",
        key=key,
        cert=cert,
        cas=None,
        encryption_algorithm=serialization.NoEncryption(),
    )
    return _load_signer(pfx_bytes, "")


def _cert_payload(signer: signers.SimpleSigner) -> dict[str, Any]:
    cert = signer.signing_cert
    validity = cert["tbs_certificate"]["validity"]
    subject_native = cert.subject.native or {}
    display_name = (
        subject_native.get("common_name")
        or subject_native.get("name")
        or subject_native.get("organization_name")
        or ""
    )
    return {
        "subject": cert.subject.human_friendly,
        "display_name": str(display_name or ""),
        "issuer": cert.issuer.human_friendly,
        "serial": str(cert.serial_number),
        "valid_from": _fmt_dt(validity["not_before"].native),
        "valid_to": _fmt_dt(validity["not_after"].native),
    }


def _safe_name(name: str, fallback: str = "document.pdf") -> str:
    name = os.path.basename(name or fallback)
    name = re.sub(r"[\\/:*?\"<>|\x00-\x1f]", "_", name).strip(" .")
    if not name:
        name = fallback
    if not name.lower().endswith(".pdf"):
        name += ".pdf"
    return name


def _ear_name(name: str) -> str:
    base = _safe_name(name)
    stem, _ext = os.path.splitext(base)
    if not stem.lower().endswith("_ear"):
        stem += "_EAR"
    return stem + ".pdf"


def _unique_name(name: str, used: set[str]) -> str:
    base = _safe_name(name)
    stem, ext = os.path.splitext(base)
    candidate = base
    n = 2
    while candidate.lower() in used:
        if stem.lower().endswith("_ear"):
            candidate = f"{stem[:-4]}_{n}_EAR{ext}"
        else:
            candidate = f"{stem}_{n}{ext}"
        n += 1
    used.add(candidate.lower())
    return candidate


def _validate_box(box: Any) -> Tuple[int, int, int, int]:
    if not isinstance(box, list) or len(box) != 4:
        raise ValueError("Neplatný obdélník viditelného podpisu.")
    vals = [float(x) for x in box]
    x1, y1, x2, y2 = vals
    if x2 <= x1 or y2 <= y1:
        raise ValueError("Obdélník podpisu má nulovou nebo zápornou velikost.")
    if max(abs(x) for x in vals) > 100000:
        raise ValueError("Souřadnice podpisu jsou mimo očekávaný rozsah.")
    return tuple(int(round(x)) for x in vals)  # type: ignore[return-value]


def _stamp_style(stamp_path: Optional[str]):
    if stamp_path:
        # Static image appearance: the image itself is the signature appearance.
        return stamp.StaticStampStyle(
            background=images.PdfImage(stamp_path),
            background_opacity=1.0,
            border_width=0,
        )
    # Text fallback uses only ASCII to stay compatible with the default font.
    return stamp.TextStampStyle(
        stamp_text="Podepsal: %(signer)s\nCas: %(ts)s",
        border_width=1,
        background_opacity=0.0,
    )


def _sign_one(
    pdf_bytes: bytes,
    signer: signers.Signer,
    document_meta: dict[str, Any],
    common_meta: dict[str, Any],
    timestamper,
    stamp_path: Optional[str],
) -> bytes:
    field_name = "Signature_2020_" + os.urandom(8).hex()
    placement = document_meta.get("placement")

    new_field = None
    appearance = None
    if placement:
        page = int(placement.get("page", 0))
        if page < 0:
            raise ValueError("Číslo stránky podpisu je neplatné.")
        box = _validate_box(placement.get("box"))
        new_field = fields.SigFieldSpec(
            sig_field_name=field_name,
            on_page=page,
            box=box,
        )
        appearance = _stamp_style(stamp_path)
    else:
        # box=None => invisible signature field.
        new_field = fields.SigFieldSpec(sig_field_name=field_name)

    sig_meta = signers.PdfSignatureMetadata(
        field_name=field_name,
        md_algorithm="sha256",
        subfilter=fields.SigSeedSubFilter.PADES,
        reason=common_meta.get("reason") or None,
        location=common_meta.get("location") or None,
        contact_info=common_meta.get("contact") or None,
        certify=True,
        docmdp_permissions=fields.MDPPerm.ANNOTATE,
    )

    input_stream = io.BytesIO(pdf_bytes)
    output_stream = io.BytesIO()
    writer = IncrementalPdfFileWriter(input_stream)
    pdf_signer = signers.PdfSigner(
        sig_meta,
        signer=signer,
        timestamper=timestamper,
        stamp_style=appearance,
        new_field_spec=new_field,
    )
    pdf_signer.sign_pdf(writer, output=output_stream)
    return output_stream.getvalue()


@app.get("/status")
def status():
    return jsonify(
        ok=True,
        service="20-20 AuthorizationBridge",
        version=APP_VERSION,
        pyhanko=getattr(pyhanko, "__version__", "unknown"),
        host=HOST,
        port=PORT,
        features={
            "test_signing": True,
            "dedicated_test_endpoint": True,
            "pdfa3_input": True,
            "origin_lock": True,
            "session_token": True,
            "fast_zip": True,
            "optional_ear_suffix": True,
            "tsa_basic_auth": True,
            "windows_cert_store": True,
            "local_test_tsa": True,
            "tsa_preflight": True,
            "local_sign_approval": True,
            "docmdp_annotate": True,
        },
    )


@app.get("/windows-certificates")
def windows_certificates():
    try:
        return jsonify(ok=True, certificates=_windows_certificates())
    except Exception as exc:
        return jsonify(ok=False, error=str(exc)), 400


@app.post("/windows-certificate-info")
def windows_certificate_info():
    try:
        payload = request.get_json(silent=True) or {}
        thumbprint = str(payload.get("thumbprint") or "").strip()
        signer = WindowsStoreSigner(thumbprint)
        return jsonify(ok=True, thumbprint=thumbprint, **_cert_payload(signer))
    except Exception as exc:
        return jsonify(ok=False, error=str(exc)), 400


@app.post("/preflight-sign")
def preflight_sign():
    try:
        meta = request.get_json(silent=True) or {}
        document_count = int(meta.get("document_count") or 0)
        if document_count < 1 or document_count > 10000:
            return jsonify(ok=False, error="Neplatný počet dokumentů pro podpis."), 400

        cert_thumbprint = str(meta.get("certificate_thumbprint") or "").strip()
        if not cert_thumbprint:
            return jsonify(ok=False, error="Vyber podpisový certifikát z Windows."), 400

        profile = str(meta.get("profile") or "bt").lower()
        if profile not in {"bb", "bt"}:
            return jsonify(ok=False, error="Podporované profily jsou PAdES B-B a B-T."), 400

        # 1) Certifikát + privátní klíč ověřit ještě před PDF/A konverzí.
        signer = WindowsStoreSigner(cert_thumbprint)
        cert_info = _cert_payload(signer)
        crypto_cert = x509.load_der_x509_certificate(signer.signing_cert.dump())
        now = datetime.now(timezone.utc)
        valid_from = getattr(crypto_cert, "not_valid_before_utc", crypto_cert.not_valid_before.replace(tzinfo=timezone.utc))
        valid_to = getattr(crypto_cert, "not_valid_after_utc", crypto_cert.not_valid_after.replace(tzinfo=timezone.utc))
        if now < valid_from or now > valid_to:
            return jsonify(ok=False, error="Vybraný podpisový certifikát není v tuto chvíli platný."), 400
        try:
            key_usage = crypto_cert.extensions.get_extension_for_class(x509.KeyUsage).value
            if not (key_usage.digital_signature or key_usage.content_commitment):
                return jsonify(ok=False, error="Vybraný certifikát nemá povolené použití pro elektronický podpis."), 400
        except x509.ExtensionNotFound:
            pass
        _verify_windows_private_key_available(signer)

        # 2) U B-T skutečně kontaktovat TSA a ověřit credentials + RFC3161 odpověď.
        try:
            timestamper = _build_timestamper(meta)
            _verify_tsa_login(timestamper)
        except PermissionError as exc:
            return jsonify(ok=False, error=str(exc)), 401
        except Exception as exc:
            return jsonify(ok=False, error="TSA ověření selhalo: " + str(exc)), 400

        # 3) Issue a short-lived preflight token. No document conversion has
        # happened yet, so this token only proves cert/TSA readiness.
        _cleanup_approvals()
        preflight_token = secrets.token_urlsafe(32)
        context = _approval_context(meta, document_count)
        _PREFLIGHTS[preflight_token] = {
            "context": context,
            "certificate_name": str(cert_info.get("display_name") or cert_info.get("subject") or "Windows certifikát"),
            "expires": datetime.now(timezone.utc).timestamp() + _APPROVAL_TTL_SECONDS,
            "used": False,
        }
        return jsonify(
            ok=True,
            preflight_token=preflight_token,
            expires_in=_APPROVAL_TTL_SECONDS,
            certificate=cert_info,
            tsa_verified=(profile == "bt"),
        )
    except Exception as exc:
        print("[AuthorizationBridge] preflight error:", traceback.format_exc(), flush=True)
        return jsonify(ok=False, error=str(exc)), 400


@app.post("/approve-sign")
def approve_sign():
    try:
        payload = request.get_json(silent=True) or {}
        preflight_token = str(payload.get("preflight_token") or "")
        documents = payload.get("documents")
        signing_intent = payload.get("signing_intent")
        if not isinstance(documents, list) or not documents:
            return jsonify(ok=False, error="Chybí finální dokumenty k potvrzení."), 400
        if not isinstance(signing_intent, dict):
            return jsonify(ok=False, error="Chybí podpisový záměr k potvrzení."), 400

        _cleanup_approvals()
        preflight = _PREFLIGHTS.get(preflight_token)
        if not preflight or bool(preflight.get("used")):
            return jsonify(ok=False, error="Preflight vypršel nebo není platný. Spusť export znovu."), 403

        context = preflight.get("context") or {}
        if int(context.get("document_count") or 0) != len(documents):
            return jsonify(ok=False, error="Počet finálních PDF neodpovídá předběžné kontrole."), 403

        clean_docs = []
        for item in documents:
            if not isinstance(item, dict):
                return jsonify(ok=False, error="Neplatný popis finálního PDF."), 400
            name = str(item.get("name") or "")
            digest = str(item.get("sha256") or "").lower()
            size = int(item.get("size") or 0)
            if not name or not re.fullmatch(r"[0-9a-f]{64}", digest) or size < 1:
                return jsonify(ok=False, error="Neplatný SHA-256 otisk finálního PDF."), 400
            clean_docs.append({"name": name, "sha256": digest, "size": size})

        if not _native_sign_confirmation(
            str(preflight.get("certificate_name") or "Windows certifikát"),
            len(clean_docs),
            str(context.get("profile") or "bt"),
            str(context.get("tsa_url") or ""),
            clean_docs,
        ):
            return jsonify(ok=False, error="Podpisová dávka nebyla ve Windows potvrzena."), 403

        preflight["used"] = True
        approval_token = secrets.token_urlsafe(32)
        _SIGN_APPROVALS[approval_token] = {
            "context": context,
            "documents": clean_docs,
            "intent_digest": _intent_digest(signing_intent),
            "expires": datetime.now(timezone.utc).timestamp() + _APPROVAL_TTL_SECONDS,
            "used": False,
        }
        return jsonify(ok=True, approval_token=approval_token, expires_in=_APPROVAL_TTL_SECONDS)
    except Exception as exc:
        print("[AuthorizationBridge] approval error:", traceback.format_exc(), flush=True)
        return jsonify(ok=False, error=str(exc)), 400


@app.post("/sign-batch")
@app.post("/sign-batch-test")
def sign_batch():
    stamp_path = None
    try:
        pdfs = request.files.getlist("pdfs")
        metadata_raw = request.form.get("metadata", "")

        if not pdfs:
            return jsonify(ok=False, error="Nebyla odeslána žádná PDF."), 400
        try:
            meta = json.loads(metadata_raw)
        except Exception:
            return jsonify(ok=False, error="Metadata požadavku nejsou platný JSON."), 400

        test_mode = request.path.endswith("/sign-batch-test") or bool(meta.get("test_mode"))
        cert_thumbprint = str(meta.get("certificate_thumbprint") or "").strip()
        if not test_mode and not cert_thumbprint:
            return jsonify(ok=False, error="Vyber podpisový certifikát z Windows."), 400

        docs_meta = meta.get("documents")
        if not isinstance(docs_meta, list) or len(docs_meta) != len(pdfs):
            return jsonify(ok=False, error="Počet dokumentů neodpovídá metadatům."), 400

        profile = str(meta.get("profile") or "bt").lower()
        if profile not in {"bb", "bt"}:
            return jsonify(ok=False, error="Podporované profily jsou PAdES B-B a B-T."), 400

        approval = None
        if not test_mode:
            _cleanup_approvals()
            approval_token = str(meta.get("approval_token") or "")
            approval = _SIGN_APPROVALS.get(approval_token)
            if not approval or bool(approval.get("used")):
                return jsonify(ok=False, error="Chybí platné lokální potvrzení podpisové dávky."), 403
            expected = _approval_context(meta, len(pdfs))
            if approval.get("context") != expected:
                return jsonify(ok=False, error="Podpisová dávka neodpovídá lokálně potvrzenému požadavku."), 403
            expected_docs = approval.get("documents") or []
            if len(expected_docs) != len(pdfs):
                return jsonify(ok=False, error="Počet PDF neodpovídá lokálně potvrzené dávce."), 403

        tsa_url = str(meta.get("tsa_url") or "").strip()
        tsa_user = str(meta.get("tsa_user") or "").strip()
        tsa_test_mode = bool(meta.get("tsa_test_mode", False))
        try:
            timestamper = _build_timestamper(meta)
        except PermissionError as exc:
            return jsonify(ok=False, error=str(exc)), 401

        signer = _make_test_signer() if test_mode else WindowsStoreSigner(cert_thumbprint)
        cert_info = _cert_payload(signer)
        if not test_mode:
            cert_info["thumbprint"] = re.sub(r"\s+", "", cert_thumbprint).upper()
            cert_info["source"] = "Windows Certificate Store · CurrentUser\\My"

        stamp_file = request.files.get("stamp")
        stamp_bytes = b""
        stamp_ext = ""
        if stamp_file and stamp_file.filename:
            stamp_ext = Path(stamp_file.filename).suffix.lower()
            if stamp_ext not in {".png", ".jpg", ".jpeg"}:
                return jsonify(ok=False, error="Obrázek razítka musí být PNG nebo JPG."), 400
            stamp_bytes = stamp_file.read()
            if len(stamp_bytes) > 25 * 1024 * 1024:
                return jsonify(ok=False, error="Obrázek razítka je příliš velký."), 400

        if approval is not None:
            actual_intent = _canonical_signing_intent(meta, stamp_bytes)
            if _intent_digest(actual_intent) != str(approval.get("intent_digest") or ""):
                return jsonify(ok=False, error="Podpisová metadata nebo grafika se po lokálním potvrzení změnily."), 403

        if stamp_bytes:
            with tempfile.NamedTemporaryFile(prefix="2020-stamp-", suffix=stamp_ext, delete=False) as tmp:
                tmp.write(stamp_bytes)
                stamp_path = tmp.name

        out_zip = io.BytesIO()
        used_names: set[str] = set()
        manifest_files = []

        # PDFs are already compressed internally; recompressing them inside ZIP
        # burns CPU for very little size reduction. STORE changes no PDF bytes.
        buffered_pdfs = []
        for idx, uploaded in enumerate(pdfs):
            original_name = uploaded.filename or f"document_{idx+1}.pdf"
            raw_pdf = uploaded.read()
            if not raw_pdf.startswith(b"%PDF-"):
                raise ValueError(f"{original_name}: soubor nevypadá jako PDF.")
            if approval is not None:
                expected_doc = (approval.get("documents") or [])[idx]
                actual_hash = hashlib.sha256(raw_pdf).hexdigest()
                if (
                    str(expected_doc.get("name") or "") != original_name
                    or int(expected_doc.get("size") or 0) != len(raw_pdf)
                    or str(expected_doc.get("sha256") or "").lower() != actual_hash
                ):
                    raise PermissionError(
                        f"{original_name}: obsah PDF se po lokálním potvrzení změnil."
                    )
            buffered_pdfs.append((original_name, raw_pdf))

        # Approval is strictly one-shot: consume it before the private key can
        # be used. Any failure after this point requires a fresh confirmation.
        if approval is not None:
            approval["used"] = True

        with zipfile.ZipFile(out_zip, "w", compression=zipfile.ZIP_STORED) as zf:
            for idx, (original_name, raw_pdf) in enumerate(buffered_pdfs):
                doc_meta = docs_meta[idx] if isinstance(docs_meta[idx], dict) else {}
                try:
                    signed = _sign_one(
                        raw_pdf,
                        signer=signer,
                        document_meta=doc_meta,
                        common_meta=meta,
                        timestamper=timestamper,
                        stamp_path=stamp_path,
                    )
                except Exception as exc:
                    raise RuntimeError(f"PAdES SIGN [{original_name}]: {exc}") from exc
                requested_output = str(doc_meta.get("output_name") or original_name)
                append_ear = bool(meta.get("append_ear", True))
                requested_output = _ear_name(requested_output) if append_ear else _safe_name(requested_output)
                out_name = _unique_name(requested_output, used_names)
                zf.writestr(out_name, signed)
                manifest_files.append(
                    {
                        "source": str(doc_meta.get("name") or original_name),
                        "output": out_name,
                        "standard": str(meta.get("output_standard") or "PDF/A-3b"),
                        "profile": "PAdES B-T" if profile == "bt" else "PAdES B-B",
                        "visible": bool(doc_meta.get("placement")),
                        "docmdp": "ANNOTATE",
                    }
                )

            manifest = {
                "tool": "20-20 TOOLBOX · Autorizace PDF",
                "bridge_version": APP_VERSION,
                "created_utc": datetime.now(timezone.utc).isoformat(),
                "profile": "PAdES B-T" if profile == "bt" else "PAdES B-B",
                "test_mode": test_mode,
                "output_standard": str(meta.get("output_standard") or "PDF/A-3b"),
                "append_ear": bool(meta.get("append_ear", True)),
                "docmdp": "ANNOTATE",
                "tsa_url": tsa_url if profile == "bt" else None,
                "tsa_authenticated": bool(tsa_user) if profile == "bt" else False,
                "tsa_test_mode": bool(meta.get("tsa_test_mode", False)) if profile == "bt" else False,
                "certificate": cert_info,
                "files": manifest_files,
            }
            zf.writestr("20-20_autorizace_manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))

        out_zip.seek(0)
        name = "autorizovane_pdf_" + datetime.now().strftime("%Y-%m-%d_%H%M") + ".zip"
        return send_file(
            out_zip,
            mimetype="application/zip",
            as_attachment=True,
            download_name=name,
            max_age=0,
        )

    except Exception as exc:
        print("[AuthorizationBridge] signing error:", traceback.format_exc(), flush=True)
        return jsonify(ok=False, error=str(exc)), 400
    finally:
        if stamp_path:
            try:
                os.remove(stamp_path)
            except OSError:
                pass


if __name__ == "__main__":
    print(f"20-20 AuthorizationBridge v{APP_VERSION} · http://{HOST}:{PORT}", flush=True)
    app.run(host=HOST, port=PORT, threaded=True, debug=False, use_reloader=False)
) { throw 'Neplatný thumbprint certifikátu.' }

$cert = Get-ChildItem -Path 'Cert:\CurrentUser\My' -ErrorAction Stop |
  Where-Object { (($_.Thumbprint -replace ' ','').ToUpperInvariant()) -eq $thumb } |
  Select-Object -First 1

if ($null -eq $cert) {
  $cert = Get-ChildItem -Path 'Cert:\LocalMachine\My' -ErrorAction SilentlyContinue |
    Where-Object { (($_.Thumbprint -replace ' ','').ToUpperInvariant()) -eq $thumb } |
    Select-Object -First 1
}

if ($null -eq $cert) { throw 'Vybraný certifikát nebyl nalezen ve Windows úložišti.' }
if (-not $cert.HasPrivateKey) { throw 'Vybraný certifikát nemá dostupný privátní klíč.' }

$rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
if ($null -eq $rsa) { throw 'Privátní RSA klíč není dostupný přes Windows provider.' }
try {
  if ($rsa.KeySize -lt 2048) { throw 'RSA klíč je kratší než 2048 bitů.' }
  Write-Output $rsa.KeySize
} finally {
  $rsa.Dispose()
}
"""


def _verify_windows_private_key_available(signer: "WindowsStoreSigner") -> None:
    raw = _run_powershell(
        _WINDOWS_KEY_PROBE_PS,
        {"TWENTY20_CERT_THUMBPRINT": signer.thumbprint},
        timeout=30,
    )
    match = re.search(r"\d{4,5}", raw or "")
    if not match or int(match.group(0)) < 2048:
        raise ValueError("Windows nepotvrdil dostupný RSA privátní klíč o délce alespoň 2048 bitů.")


def _build_timestamper(meta: Dict[str, Any]):
    profile = str(meta.get("profile") or "bt").lower()
    tsa_url = str(meta.get("tsa_url") or "").strip()
    tsa_user = str(meta.get("tsa_user") or "").strip()
    tsa_password = str(meta.get("tsa_password") or "")
    tsa_test_mode = bool(meta.get("tsa_test_mode", False))

    if profile != "bt":
        return None
    if not re.match(r"^https?://", tsa_url, re.I):
        raise ValueError("Pro PAdES B-T je nutná platná HTTP(S) adresa RFC 3161 TSA serveru.")
    if bool(tsa_user) != bool(tsa_password):
        raise ValueError("Pro přihlášení k TSA musí být vyplněn login i heslo.")

    if tsa_test_mode:
        if tsa_url != "http://127.0.0.1:8094/test-tsa":
            raise ValueError("TEST TSA musí používat lokální adresu 127.0.0.1:8094/test-tsa.")
        if not (
            secrets.compare_digest(tsa_user, _TEST_TSA_USER)
            and secrets.compare_digest(tsa_password, _TEST_TSA_PASSWORD)
        ):
            raise PermissionError("Neplatný TEST TSA login nebo heslo.")
        return _get_test_tsa()

    auth = BasicAuth(tsa_user, tsa_password) if tsa_user else None
    return timestamps.HTTPTimeStamper(tsa_url, auth=auth, timeout=15)


def _verify_tsa_login(timestamper) -> None:
    if timestamper is None:
        return
    probe_digest = hashlib.sha256(b"20-20 TOOLBOX TSA PREFLIGHT").digest()
    asyncio.run(timestamper.async_timestamp(probe_digest, "sha256"))


def _fmt_dt(value: Any) -> str:
    try:
        if value is None:
            return ""
        if hasattr(value, "astimezone"):
            value = value.astimezone()
        return value.strftime("%d.%m.%Y %H:%M:%S %Z").strip()
    except Exception:
        return str(value)



def _run_powershell(script: str, env_extra: Optional[Dict[str, str]] = None, timeout: int = 30) -> str:
    if os.name != "nt":
        raise RuntimeError("Windows Certificate Store je dostupný pouze ve Windows.")
    env = os.environ.copy()
    if env_extra:
        env.update(env_extra)
    proc = subprocess.run(
        ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "-"],
        input=script,
        text=True,
        capture_output=True,
        env=env,
        timeout=timeout,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "PowerShell selhal.").strip()
        raise RuntimeError(detail)
    return (proc.stdout or "").strip()


_WINDOWS_CERT_LIST_PS = r"""
$ErrorActionPreference = 'Stop'
$items = @()

$stores = @(
  @{ Path = 'Cert:\CurrentUser\My'; Location = 'CurrentUser' },
  @{ Path = 'Cert:\LocalMachine\My'; Location = 'LocalMachine' }
)

foreach ($entry in $stores) {
  try {
    $certs = @(Get-ChildItem -Path $entry.Path -ErrorAction Stop)
  } catch {
    continue
  }

  foreach ($cert in $certs) {
    try {
      $oid = ''
      $friendly = ''
      try { $oid = [string]$cert.PublicKey.Oid.Value } catch {}
      try { $friendly = [string]$cert.PublicKey.Oid.FriendlyName } catch {}

      $keyType = 'UNKNOWN'
      if ($oid -eq '1.2.840.113549.1.1.1' -or $friendly -match 'RSA') {
        $keyType = 'RSA'
      } elseif ($oid -eq '1.2.840.10045.2.1' -or $friendly -match 'ECC|ECDSA') {
        $keyType = 'ECDSA'
      }

      $keyBits = 0
      if ($keyType -eq 'RSA') {
        try {
          $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($cert)
          if ($null -ne $rsa) {
            $keyBits = $rsa.KeySize
            $rsa.Dispose()
          }
        } catch {}
      }

      $items += [pscustomobject]@{
        thumbprint = (($cert.Thumbprint -replace ' ','').ToUpperInvariant())
        display_name = $cert.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName,$false)
        subject = [string]$cert.Subject
        issuer = [string]$cert.Issuer
        serial = [string]$cert.SerialNumber
        valid_from = $cert.NotBefore.ToString('o')
        valid_to = $cert.NotAfter.ToString('o')
        has_private_key = [bool]$cert.HasPrivateKey
        key_type = $keyType
        key_bits = $keyBits
        supported = [bool]($cert.HasPrivateKey -and $keyType -eq 'RSA')
        store_location = [string]$entry.Location
        store_name = 'My'
      }
    } catch {
      continue
    }
  }
}

@($items | Sort-Object valid_to -Descending) | ConvertTo-Json -Compress -Depth 4
"""


_WINDOWS_CERT_DER_PS = r"""
$ErrorActionPreference = 'Stop'
$thumb = ($env:TWENTY20_CERT_THUMBPRINT -replace ' ','').ToUpperInvariant()
$outFile = $env:TWENTY20_CERT_FILE

if ($thumb -notmatch '^[0-9A-F]{40,128}$') { throw 'Neplatný thumbprint certifikátu.' }
if ([string]::IsNullOrWhiteSpace($outFile)) { throw 'Chybí dočasná cesta pro veřejný certifikát.' }

$cert = Get-ChildItem -Path 'Cert:\CurrentUser\My' -ErrorAction Stop |
  Where-Object { (($_.Thumbprint -replace ' ','').ToUpperInvariant()) -eq $thumb } |
  Select-Object -First 1

if ($null -eq $cert) {
  $cert = Get-ChildItem -Path 'Cert:\LocalMachine\My' -ErrorAction SilentlyContinue |
    Where-Object { (($_.Thumbprint -replace ' ','').ToUpperInvariant()) -eq $thumb } |
    Select-Object -First 1
}

if ($null -eq $cert) { throw 'Vybraný certifikát nebyl nalezen ve Windows úložišti.' }
if (-not $cert.HasPrivateKey) { throw 'Vybraný certifikát nemá dostupný privátní klíč.' }

Export-Certificate -Cert $cert -FilePath $outFile -Type CERT -Force | Out-Null
"""


_WINDOWS_RSA_SIGN_PS = r"""
$ErrorActionPreference = 'Stop'
$thumb = ($env:TWENTY20_CERT_THUMBPRINT -replace ' ','').ToUpperInvariant()
if ($thumb -notmatch '^[0-9A-F]{40,128}$') { throw 'Neplatný thumbprint certifikátu.' }
$data = [Convert]::FromBase64String($env:TWENTY20_SIGN_DATA)
$store = New-Object System.Security.Cryptography.X509Certificates.X509Store('My','CurrentUser')
$store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
try {
  $cert = $store.Certificates | Where-Object { (($_.Thumbprint -replace ' ','').ToUpperInvariant()) -eq $thumb } | Select-Object -First 1
  if ($null -eq $cert) { throw 'Vybraný certifikát už není ve Windows úložišti.' }
  if (-not $cert.HasPrivateKey) { throw 'Privátní klíč vybraného certifikátu není dostupný.' }
  $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
  if ($null -eq $rsa) { throw 'Toolbox zatím podporuje podpis certifikátem s RSA privátním klíčem.' }
  try {
    $sig = $rsa.SignData(
      $data,
      [System.Security.Cryptography.HashAlgorithmName]::SHA256,
      [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
    )
    [Convert]::ToBase64String($sig)
  } finally {
    $rsa.Dispose()
  }
} finally {
  $store.Close()
}
"""


def _windows_certificates() -> List[Dict[str, Any]]:
    raw = _run_powershell(_WINDOWS_CERT_LIST_PS, timeout=20)
    if not raw:
        return []
    data = json.loads(raw)
    if isinstance(data, dict):
        data = [data]
    if not isinstance(data, list):
        return []
    now = datetime.now(timezone.utc)
    out: List[Dict[str, Any]] = []
    for item in data:
        if not isinstance(item, dict):
            continue
        try:
            valid_to = datetime.fromisoformat(str(item.get("valid_to") or "").replace("Z", "+00:00"))
            if valid_to.tzinfo is None:
                valid_to = valid_to.astimezone()
            item["expired"] = valid_to.astimezone(timezone.utc) <= now
        except Exception:
            item["expired"] = False
        out.append(item)
    return out


def _windows_cert_der(thumbprint: str) -> bytes:
    thumbprint = re.sub(r"\s+", "", str(thumbprint or "")).upper()
    if not re.fullmatch(r"[0-9A-F]{40,128}", thumbprint):
        raise ValueError("Neplatný thumbprint certifikátu.")

    temp_path = None
    try:
        fd, temp_path = tempfile.mkstemp(prefix="2020-public-cert-", suffix=".cer")
        os.close(fd)

        _run_powershell(
            _WINDOWS_CERT_DER_PS,
            {
                "TWENTY20_CERT_THUMBPRINT": thumbprint,
                "TWENTY20_CERT_FILE": temp_path,
            },
            timeout=20,
        )

        with open(temp_path, "rb") as fh:
            raw = fh.read()

        if len(raw) < 128:
            raise ValueError(
                "Windows vyexportoval neplatný veřejný certifikát "
                f"({len(raw)} B)."
            )
        return raw
    finally:
        if temp_path:
            try:
                os.remove(temp_path)
            except OSError:
                pass


def _windows_sign_data(thumbprint: str, data: bytes) -> bytes:
    raw = _run_powershell(
        _WINDOWS_RSA_SIGN_PS,
        {
            "TWENTY20_CERT_THUMBPRINT": thumbprint,
            "TWENTY20_SIGN_DATA": base64.b64encode(data).decode("ascii"),
        },
        timeout=120,
    )
    return base64.b64decode(raw, validate=True)


class WindowsStoreSigner(signers.ExternalSigner):
    def __init__(self, thumbprint: str):
        try:
            cert_der = _windows_cert_der(thumbprint)
        except Exception as exc:
            raise RuntimeError("WINDOWS CERT READ: " + str(exc)) from exc
        try:
            crypto_cert = x509.load_der_x509_certificate(cert_der)
        except Exception as exc:
            raise RuntimeError("WINDOWS CERT ASN1: " + str(exc)) from exc
        public_key = crypto_cert.public_key()
        if not isinstance(public_key, rsa.RSAPublicKey):
            raise ValueError("Toolbox zatím podporuje Windows podpisové certifikáty s RSA klíčem.")
        self.thumbprint = re.sub(r"\s+", "", thumbprint).upper()
        self.signature_size = (public_key.key_size + 7) // 8
        super().__init__(
            signing_cert=asn1_x509.Certificate.load(cert_der),
            cert_registry=None,
            signature_value=self.signature_size,
            signature_mechanism=algos.SignedDigestAlgorithm({"algorithm": "sha256_rsa"}),
        )

    async def async_sign_raw(self, data: bytes, digest_algorithm: str, dry_run: bool = False) -> bytes:
        if dry_run:
            return b"\x00" * self.signature_size
        if str(digest_algorithm or "").lower().replace("-", "") != "sha256":
            raise ValueError("Windows signer je nastavený na SHA-256.")
        return _windows_sign_data(self.thumbprint, data)



def _get_test_tsa() -> DummyTimeStamper:
    global _TEST_TSA
    if _TEST_TSA is not None:
        return _TEST_TSA

    key = rsa.generate_private_key(public_exponent=65537, key_size=3072)
    subject = issuer = x509.Name(
        [
            x509.NameAttribute(NameOID.COUNTRY_NAME, "CZ"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "20-20 TEST TSA"),
            x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, "TEST TEST TEST - NOT QUALIFIED"),
            x509.NameAttribute(NameOID.COMMON_NAME, "TEST TEST TEST - 20-20 LOCAL TSA"),
        ]
    )
    now = datetime.now(timezone.utc)
    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - timedelta(days=1))
        .not_valid_after(now + timedelta(days=3650))
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .add_extension(
            x509.KeyUsage(
                digital_signature=True,
                content_commitment=False,
                key_encipherment=False,
                data_encipherment=False,
                key_agreement=False,
                key_cert_sign=False,
                crl_sign=False,
                encipher_only=False,
                decipher_only=False,
            ),
            critical=True,
        )
        .add_extension(
            x509.ExtendedKeyUsage([ExtendedKeyUsageOID.TIME_STAMPING]),
            critical=True,
        )
        .sign(key, hashes.SHA256())
    )

    cert_der = cert.public_bytes(serialization.Encoding.DER)
    key_der = key.private_bytes(
        serialization.Encoding.DER,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    )
    _TEST_TSA = DummyTimeStamper(
        tsa_cert=asn1_x509.Certificate.load(cert_der),
        tsa_key=asn1_keys.PrivateKeyInfo.load(key_der),
        certs_to_embed=None,
        include_nonce=True,
    )
    return _TEST_TSA


@app.post("/test-tsa")
def local_test_tsa():
    try:
        if request.remote_addr not in {"127.0.0.1", "::1"}:
            return Response("TEST TSA je dostupná jen lokálně.", status=403)

        auth = request.authorization
        user_ok = bool(auth) and secrets.compare_digest(auth.username or "", _TEST_TSA_USER)
        pass_ok = bool(auth) and secrets.compare_digest(auth.password or "", _TEST_TSA_PASSWORD)
        if not (user_ok and pass_ok):
            return Response(
                "TEST TEST TEST - neplatný login k lokální TSA.",
                status=401,
                headers={"WWW-Authenticate": 'Basic realm="20-20 TEST TSA"'},
            )

        raw = request.get_data(cache=False)
        if not raw:
            return Response("Prázdný RFC 3161 požadavek.", status=400)

        ts_req = tsp.TimeStampReq.load(raw)
        ts_resp = _get_test_tsa().request_tsa_response(ts_req)
        return Response(
            ts_resp.dump(),
            status=200,
            content_type="application/timestamp-reply",
            headers={"X-20-20-Test-TSA": "TEST TEST TEST"},
        )
    except Exception as exc:
        print("[AuthorizationBridge] TEST TSA error:", traceback.format_exc(), flush=True)
        return Response("TEST TSA chyba: " + str(exc), status=400)


def _load_signer(pfx_bytes: bytes, password: str) -> signers.SimpleSigner:
    path = None
    try:
        with tempfile.NamedTemporaryFile(prefix="2020-auth-", suffix=".pfx", delete=False) as tmp:
            tmp.write(pfx_bytes)
            path = tmp.name
        signer = signers.SimpleSigner.load_pkcs12(
            path,
            passphrase=password.encode("utf-8") if password else None,
        )
        if signer is None:
            raise ValueError("Certifikát se nepodařilo načíst. Zkontroluj heslo a obsah PFX/P12.")
        return signer
    finally:
        if path:
            try:
                os.remove(path)
            except OSError:
                pass


def _make_test_signer() -> signers.SimpleSigner:
    """Create a short-lived local self-signed certificate for TEST mode."""
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = issuer = x509.Name(
        [
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "20-20 TOOLBOX"),
            x509.NameAttribute(NameOID.COMMON_NAME, "20-20 TOOLBOX TEST SIGNATURE"),
        ]
    )
    now = datetime.now(timezone.utc)
    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - timedelta(minutes=5))
        .not_valid_after(now + timedelta(days=1))
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .sign(key, hashes.SHA256())
    )
    pfx_bytes = pkcs12.serialize_key_and_certificates(
        name=b"20-20 TOOLBOX TEST",
        key=key,
        cert=cert,
        cas=None,
        encryption_algorithm=serialization.NoEncryption(),
    )
    return _load_signer(pfx_bytes, "")


def _cert_payload(signer: signers.SimpleSigner) -> dict[str, Any]:
    cert = signer.signing_cert
    validity = cert["tbs_certificate"]["validity"]
    subject_native = cert.subject.native or {}
    display_name = (
        subject_native.get("common_name")
        or subject_native.get("name")
        or subject_native.get("organization_name")
        or ""
    )
    return {
        "subject": cert.subject.human_friendly,
        "display_name": str(display_name or ""),
        "issuer": cert.issuer.human_friendly,
        "serial": str(cert.serial_number),
        "valid_from": _fmt_dt(validity["not_before"].native),
        "valid_to": _fmt_dt(validity["not_after"].native),
    }


def _safe_name(name: str, fallback: str = "document.pdf") -> str:
    name = os.path.basename(name or fallback)
    name = re.sub(r"[\\/:*?\"<>|\x00-\x1f]", "_", name).strip(" .")
    if not name:
        name = fallback
    if not name.lower().endswith(".pdf"):
        name += ".pdf"
    return name


def _ear_name(name: str) -> str:
    base = _safe_name(name)
    stem, _ext = os.path.splitext(base)
    if not stem.lower().endswith("_ear"):
        stem += "_EAR"
    return stem + ".pdf"


def _unique_name(name: str, used: set[str]) -> str:
    base = _safe_name(name)
    stem, ext = os.path.splitext(base)
    candidate = base
    n = 2
    while candidate.lower() in used:
        if stem.lower().endswith("_ear"):
            candidate = f"{stem[:-4]}_{n}_EAR{ext}"
        else:
            candidate = f"{stem}_{n}{ext}"
        n += 1
    used.add(candidate.lower())
    return candidate


def _validate_box(box: Any) -> Tuple[int, int, int, int]:
    if not isinstance(box, list) or len(box) != 4:
        raise ValueError("Neplatný obdélník viditelného podpisu.")
    vals = [float(x) for x in box]
    x1, y1, x2, y2 = vals
    if x2 <= x1 or y2 <= y1:
        raise ValueError("Obdélník podpisu má nulovou nebo zápornou velikost.")
    if max(abs(x) for x in vals) > 100000:
        raise ValueError("Souřadnice podpisu jsou mimo očekávaný rozsah.")
    return tuple(int(round(x)) for x in vals)  # type: ignore[return-value]


def _stamp_style(stamp_path: Optional[str]):
    if stamp_path:
        # Static image appearance: the image itself is the signature appearance.
        return stamp.StaticStampStyle(
            background=images.PdfImage(stamp_path),
            background_opacity=1.0,
            border_width=0,
        )
    # Text fallback uses only ASCII to stay compatible with the default font.
    return stamp.TextStampStyle(
        stamp_text="Podepsal: %(signer)s\nCas: %(ts)s",
        border_width=1,
        background_opacity=0.0,
    )


def _sign_one(
    pdf_bytes: bytes,
    signer: signers.Signer,
    document_meta: dict[str, Any],
    common_meta: dict[str, Any],
    timestamper,
    stamp_path: Optional[str],
) -> bytes:
    field_name = "Signature_2020_" + os.urandom(8).hex()
    placement = document_meta.get("placement")

    new_field = None
    appearance = None
    if placement:
        page = int(placement.get("page", 0))
        if page < 0:
            raise ValueError("Číslo stránky podpisu je neplatné.")
        box = _validate_box(placement.get("box"))
        new_field = fields.SigFieldSpec(
            sig_field_name=field_name,
            on_page=page,
            box=box,
        )
        appearance = _stamp_style(stamp_path)
    else:
        # box=None => invisible signature field.
        new_field = fields.SigFieldSpec(sig_field_name=field_name)

    sig_meta = signers.PdfSignatureMetadata(
        field_name=field_name,
        md_algorithm="sha256",
        subfilter=fields.SigSeedSubFilter.PADES,
        reason=common_meta.get("reason") or None,
        location=common_meta.get("location") or None,
        contact_info=common_meta.get("contact") or None,
        certify=False,
    )

    input_stream = io.BytesIO(pdf_bytes)
    output_stream = io.BytesIO()
    writer = IncrementalPdfFileWriter(input_stream)
    pdf_signer = signers.PdfSigner(
        sig_meta,
        signer=signer,
        timestamper=timestamper,
        stamp_style=appearance,
        new_field_spec=new_field,
    )
    pdf_signer.sign_pdf(writer, output=output_stream)
    return output_stream.getvalue()


@app.get("/status")
def status():
    return jsonify(
        ok=True,
        service="20-20 AuthorizationBridge",
        version=APP_VERSION,
        pyhanko=getattr(pyhanko, "__version__", "unknown"),
        host=HOST,
        port=PORT,
        features={
            "test_signing": True,
            "dedicated_test_endpoint": True,
            "pdfa3_input": True,
            "origin_lock": True,
            "session_token": True,
            "fast_zip": True,
            "optional_ear_suffix": True,
            "tsa_basic_auth": True,
            "windows_cert_store": True,
            "local_test_tsa": True,
            "tsa_preflight": True,
            "local_sign_approval": True,
        },
    )


@app.get("/windows-certificates")
def windows_certificates():
    try:
        return jsonify(ok=True, certificates=_windows_certificates())
    except Exception as exc:
        return jsonify(ok=False, error=str(exc)), 400


@app.post("/windows-certificate-info")
def windows_certificate_info():
    try:
        payload = request.get_json(silent=True) or {}
        thumbprint = str(payload.get("thumbprint") or "").strip()
        signer = WindowsStoreSigner(thumbprint)
        return jsonify(ok=True, thumbprint=thumbprint, **_cert_payload(signer))
    except Exception as exc:
        return jsonify(ok=False, error=str(exc)), 400


@app.post("/preflight-sign")
def preflight_sign():
    try:
        meta = request.get_json(silent=True) or {}
        document_count = int(meta.get("document_count") or 0)
        if document_count < 1 or document_count > 10000:
            return jsonify(ok=False, error="Neplatný počet dokumentů pro podpis."), 400

        cert_thumbprint = str(meta.get("certificate_thumbprint") or "").strip()
        if not cert_thumbprint:
            return jsonify(ok=False, error="Vyber podpisový certifikát z Windows."), 400

        profile = str(meta.get("profile") or "bt").lower()
        if profile not in {"bb", "bt"}:
            return jsonify(ok=False, error="Podporované profily jsou PAdES B-B a B-T."), 400

        approval = None
        if not test_mode:
            _cleanup_approvals()
            approval_token = str(meta.get("approval_token") or "")
            approval = _SIGN_APPROVALS.get(approval_token)
            if not approval or bool(approval.get("used")):
                return jsonify(ok=False, error="Chybí platné lokální potvrzení podpisové dávky."), 403
            expected = _approval_context(meta, len(pdfs))
            if approval.get("context") != expected:
                return jsonify(ok=False, error="Podpisová dávka neodpovídá lokálně potvrzenému požadavku."), 403
            expected_docs = approval.get("documents") or []
            if len(expected_docs) != len(pdfs):
                return jsonify(ok=False, error="Počet PDF neodpovídá lokálně potvrzené dávce."), 403

        # 1) Certifikát + privátní klíč ověřit ještě před PDF/A konverzí.
        signer = WindowsStoreSigner(cert_thumbprint)
        cert_info = _cert_payload(signer)
        crypto_cert = x509.load_der_x509_certificate(signer.signing_cert.dump())
        now = datetime.now(timezone.utc)
        valid_from = getattr(crypto_cert, "not_valid_before_utc", crypto_cert.not_valid_before.replace(tzinfo=timezone.utc))
        valid_to = getattr(crypto_cert, "not_valid_after_utc", crypto_cert.not_valid_after.replace(tzinfo=timezone.utc))
        if now < valid_from or now > valid_to:
            return jsonify(ok=False, error="Vybraný podpisový certifikát není v tuto chvíli platný."), 400
        try:
            key_usage = crypto_cert.extensions.get_extension_for_class(x509.KeyUsage).value
            if not (key_usage.digital_signature or key_usage.content_commitment):
                return jsonify(ok=False, error="Vybraný certifikát nemá povolené použití pro elektronický podpis."), 400
        except x509.ExtensionNotFound:
            pass
        _verify_windows_private_key(signer)

        # 2) U B-T skutečně kontaktovat TSA a ověřit credentials + RFC3161 odpověď.
        try:
            timestamper = _build_timestamper(meta)
            _verify_tsa_login(timestamper)
        except PermissionError as exc:
            return jsonify(ok=False, error=str(exc)), 401
        except Exception as exc:
            return jsonify(ok=False, error="TSA ověření selhalo: " + str(exc)), 400

        # 3) Issue a short-lived preflight token. No document conversion has
        # happened yet, so this token only proves cert/TSA readiness.
        _cleanup_approvals()
        preflight_token = secrets.token_urlsafe(32)
        context = _approval_context(meta, document_count)
        _PREFLIGHTS[preflight_token] = {
            "context": context,
            "certificate_name": str(cert_info.get("display_name") or cert_info.get("subject") or "Windows certifikát"),
            "expires": datetime.now(timezone.utc).timestamp() + _APPROVAL_TTL_SECONDS,
            "used": False,
        }
        return jsonify(
            ok=True,
            preflight_token=preflight_token,
            expires_in=_APPROVAL_TTL_SECONDS,
            certificate=cert_info,
            tsa_verified=(profile == "bt"),
        )
    except Exception as exc:
        print("[AuthorizationBridge] preflight error:", traceback.format_exc(), flush=True)
        return jsonify(ok=False, error=str(exc)), 400


@app.post("/approve-sign")
def approve_sign():
    try:
        payload = request.get_json(silent=True) or {}
        preflight_token = str(payload.get("preflight_token") or "")
        documents = payload.get("documents")
        if not isinstance(documents, list) or not documents:
            return jsonify(ok=False, error="Chybí finální dokumenty k potvrzení."), 400

        _cleanup_approvals()
        preflight = _PREFLIGHTS.get(preflight_token)
        if not preflight or bool(preflight.get("used")):
            return jsonify(ok=False, error="Preflight vypršel nebo není platný. Spusť export znovu."), 403

        context = preflight.get("context") or {}
        if int(context.get("document_count") or 0) != len(documents):
            return jsonify(ok=False, error="Počet finálních PDF neodpovídá předběžné kontrole."), 403

        clean_docs = []
        for item in documents:
            if not isinstance(item, dict):
                return jsonify(ok=False, error="Neplatný popis finálního PDF."), 400
            name = str(item.get("name") or "")
            digest = str(item.get("sha256") or "").lower()
            size = int(item.get("size") or 0)
            if not name or not re.fullmatch(r"[0-9a-f]{64}", digest) or size < 1:
                return jsonify(ok=False, error="Neplatný SHA-256 otisk finálního PDF."), 400
            clean_docs.append({"name": name, "sha256": digest, "size": size})

        if not _native_sign_confirmation(
            str(preflight.get("certificate_name") or "Windows certifikát"),
            len(clean_docs),
            str(context.get("profile") or "bt"),
            str(context.get("tsa_url") or ""),
        ):
            return jsonify(ok=False, error="Podpisová dávka nebyla ve Windows potvrzena."), 403

        preflight["used"] = True
        approval_token = secrets.token_urlsafe(32)
        _SIGN_APPROVALS[approval_token] = {
            "context": context,
            "documents": clean_docs,
            "expires": datetime.now(timezone.utc).timestamp() + _APPROVAL_TTL_SECONDS,
            "used": False,
        }
        return jsonify(ok=True, approval_token=approval_token, expires_in=_APPROVAL_TTL_SECONDS)
    except Exception as exc:
        print("[AuthorizationBridge] approval error:", traceback.format_exc(), flush=True)
        return jsonify(ok=False, error=str(exc)), 400


@app.post("/sign-batch")
@app.post("/sign-batch-test")
def sign_batch():
    stamp_path = None
    try:
        pdfs = request.files.getlist("pdfs")
        metadata_raw = request.form.get("metadata", "")

        if not pdfs:
            return jsonify(ok=False, error="Nebyla odeslána žádná PDF."), 400
        try:
            meta = json.loads(metadata_raw)
        except Exception:
            return jsonify(ok=False, error="Metadata požadavku nejsou platný JSON."), 400

        test_mode = request.path.endswith("/sign-batch-test") or bool(meta.get("test_mode"))
        cert_thumbprint = str(meta.get("certificate_thumbprint") or "").strip()
        if not test_mode and not cert_thumbprint:
            return jsonify(ok=False, error="Vyber podpisový certifikát z Windows."), 400

        docs_meta = meta.get("documents")
        if not isinstance(docs_meta, list) or len(docs_meta) != len(pdfs):
            return jsonify(ok=False, error="Počet dokumentů neodpovídá metadatům."), 400

        profile = str(meta.get("profile") or "bt").lower()
        if profile not in {"bb", "bt"}:
            return jsonify(ok=False, error="Podporované profily jsou PAdES B-B a B-T."), 400

        tsa_url = str(meta.get("tsa_url") or "").strip()
        tsa_user = str(meta.get("tsa_user") or "").strip()
        tsa_test_mode = bool(meta.get("tsa_test_mode", False))
        try:
            timestamper = _build_timestamper(meta)
        except PermissionError as exc:
            return jsonify(ok=False, error=str(exc)), 401

        signer = _make_test_signer() if test_mode else WindowsStoreSigner(cert_thumbprint)
        cert_info = _cert_payload(signer)
        if not test_mode:
            cert_info["thumbprint"] = re.sub(r"\s+", "", cert_thumbprint).upper()
            cert_info["source"] = "Windows Certificate Store · CurrentUser\\My"

        stamp_file = request.files.get("stamp")
        if stamp_file and stamp_file.filename:
            ext = Path(stamp_file.filename).suffix.lower()
            if ext not in {".png", ".jpg", ".jpeg"}:
                return jsonify(ok=False, error="Obrázek razítka musí být PNG nebo JPG."), 400
            with tempfile.NamedTemporaryFile(prefix="2020-stamp-", suffix=ext, delete=False) as tmp:
                tmp.write(stamp_file.read())
                stamp_path = tmp.name

        out_zip = io.BytesIO()
        used_names: set[str] = set()
        manifest_files = []

        # PDFs are already compressed internally; recompressing them inside ZIP
        # burns CPU for very little size reduction. STORE changes no PDF bytes.
        with zipfile.ZipFile(out_zip, "w", compression=zipfile.ZIP_STORED) as zf:
            for idx, uploaded in enumerate(pdfs):
                original_name = uploaded.filename or f"document_{idx+1}.pdf"
                raw_pdf = uploaded.read()
                if not raw_pdf.startswith(b"%PDF-"):
                    raise ValueError(f"{original_name}: soubor nevypadá jako PDF.")

                if approval is not None:
                    expected_doc = (approval.get("documents") or [])[idx]
                    actual_hash = hashlib.sha256(raw_pdf).hexdigest()
                    if (
                        str(expected_doc.get("name") or "") != original_name
                        or int(expected_doc.get("size") or 0) != len(raw_pdf)
                        or str(expected_doc.get("sha256") or "").lower() != actual_hash
                    ):
                        raise PermissionError(
                            f"{original_name}: obsah PDF se po lokálním potvrzení změnil."
                        )

                doc_meta = docs_meta[idx] if isinstance(docs_meta[idx], dict) else {}
                try:
                    signed = _sign_one(
                        raw_pdf,
                        signer=signer,
                        document_meta=doc_meta,
                        common_meta=meta,
                        timestamper=timestamper,
                        stamp_path=stamp_path,
                    )
                except Exception as exc:
                    raise RuntimeError(f"PAdES SIGN [{original_name}]: {exc}") from exc
                requested_output = str(doc_meta.get("output_name") or original_name)
                append_ear = bool(meta.get("append_ear", True))
                requested_output = _ear_name(requested_output) if append_ear else _safe_name(requested_output)
                out_name = _unique_name(requested_output, used_names)
                zf.writestr(out_name, signed)
                manifest_files.append(
                    {
                        "source": str(doc_meta.get("name") or original_name),
                        "output": out_name,
                        "standard": str(meta.get("output_standard") or "PDF/A-3b"),
                        "profile": "PAdES B-T" if profile == "bt" else "PAdES B-B",
                        "visible": bool(doc_meta.get("placement")),
                    }
                )

            if approval is not None:
                approval["used"] = True

            manifest = {
                "tool": "20-20 TOOLBOX · Autorizace PDF",
                "bridge_version": APP_VERSION,
                "created_utc": datetime.now(timezone.utc).isoformat(),
                "profile": "PAdES B-T" if profile == "bt" else "PAdES B-B",
                "test_mode": test_mode,
                "output_standard": str(meta.get("output_standard") or "PDF/A-3b"),
                "append_ear": bool(meta.get("append_ear", True)),
                "tsa_url": tsa_url if profile == "bt" else None,
                "tsa_authenticated": bool(tsa_user) if profile == "bt" else False,
                "tsa_test_mode": bool(meta.get("tsa_test_mode", False)) if profile == "bt" else False,
                "certificate": cert_info,
                "files": manifest_files,
            }
            zf.writestr("20-20_autorizace_manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))

        out_zip.seek(0)
        name = "autorizovane_pdf_" + datetime.now().strftime("%Y-%m-%d_%H%M") + ".zip"
        return send_file(
            out_zip,
            mimetype="application/zip",
            as_attachment=True,
            download_name=name,
            max_age=0,
        )

    except Exception as exc:
        print("[AuthorizationBridge] signing error:", traceback.format_exc(), flush=True)
        return jsonify(ok=False, error=str(exc)), 400
    finally:
        if stamp_path:
            try:
                os.remove(stamp_path)
            except OSError:
                pass


if __name__ == "__main__":
    print(f"20-20 AuthorizationBridge v{APP_VERSION} · http://{HOST}:{PORT}", flush=True)
    app.run(host=HOST, port=PORT, threaded=True, debug=False, use_reloader=False)
