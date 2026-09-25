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
import subprocess
import base64
import tempfile
import traceback
import zipfile
from datetime import datetime, timezone, timedelta
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


APP_VERSION = "1.9.4"
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
_TEST_TSA_USER = "TEST"
_TEST_TSA_PASSWORD = "TEST-ONLY"
_TEST_TSA = None


def _origin_allowed(origin: Optional[str]) -> bool:
    if not origin:
        return False
    origin = origin.rstrip("/")
    if origin in _TRUSTED_ORIGINS:
        return True
    return bool(re.match(r"^http://(?:127\.0\.0\.1|localhost)(?::\d+)?$", origin, re.I))


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
if ($thumb -notmatch '^[0-9A-F]{40,128}$') { throw 'Neplatný thumbprint certifikátu.' }
$store = New-Object System.Security.Cryptography.X509Certificates.X509Store('My','CurrentUser')
$store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
try {
  $cert = $store.Certificates | Where-Object { (($_.Thumbprint -replace ' ','').ToUpperInvariant()) -eq $thumb } | Select-Object -First 1
  if ($null -eq $cert) { throw 'Vybraný certifikát už není ve Windows úložišti.' }
  if (-not $cert.HasPrivateKey) { throw 'Vybraný certifikát nemá dostupný privátní klíč.' }
  [Convert]::ToBase64String($cert.RawData)
} finally {
  $store.Close()
}
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
    output = _run_powershell(
        _WINDOWS_CERT_DER_PS,
        {"TWENTY20_CERT_THUMBPRINT": thumbprint},
        timeout=20,
    )

    # PowerShell can prepend/append host noise on some PCs. Extract the
    # certificate payload instead of decoding the entire stdout blindly.
    candidates = re.findall(r"[A-Za-z0-9+/=]{128,}", output or "")
    if not candidates:
        raise ValueError("Windows nevrátil čitelná data certifikátu.")
    encoded = max(candidates, key=len)
    raw = base64.b64decode(encoded, validate=True)
    if len(raw) < 128 or not raw.startswith(b"0"):
        raise ValueError(
            "Windows vrátil neplatný DER certifikát "
            f"(velikost {len(raw)} B, začátek {raw[:8].hex()})."
        )
    return raw


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
        tsa_password = str(meta.get("tsa_password") or "")
        tsa_test_mode = bool(meta.get("tsa_test_mode", False))
        if profile == "bt":
            if not re.match(r"^https?://", tsa_url, re.I):
                return jsonify(ok=False, error="Pro PAdES B-T je nutná platná HTTP(S) adresa RFC 3161 TSA serveru."), 400
            if bool(tsa_user) != bool(tsa_password):
                return jsonify(ok=False, error="Pro přihlášení k TSA musí být vyplněn login i heslo."), 400

            if tsa_test_mode:
                if tsa_url != "http://127.0.0.1:8094/test-tsa":
                    return jsonify(ok=False, error="TEST TSA musí používat lokální adresu 127.0.0.1:8094/test-tsa."), 400
                if not (
                    secrets.compare_digest(tsa_user, _TEST_TSA_USER)
                    and secrets.compare_digest(tsa_password, _TEST_TSA_PASSWORD)
                ):
                    return jsonify(ok=False, error="Neplatný TEST TSA login nebo heslo."), 401
                # Generate the RFC3161 token directly in-process. This avoids a
                # fragile HTTP loopback while preserving the exact timestamp
                # token format that pyHanko embeds into PAdES B-T.
                try:
                    timestamper = _get_test_tsa()
                except Exception as exc:
                    raise RuntimeError("TEST TSA INIT: " + str(exc)) from exc
            else:
                auth = BasicAuth(tsa_user, tsa_password) if tsa_user else None
                timestamper = timestamps.HTTPTimeStamper(
                    tsa_url,
                    auth=auth,
                    timeout=15,
                )
        else:
            timestamper = None

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
