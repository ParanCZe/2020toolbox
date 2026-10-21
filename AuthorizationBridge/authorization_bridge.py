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
import sys
import secrets
import asyncio
import hashlib
import ctypes
import threading
import subprocess
import base64
import tempfile
import traceback
import zipfile
import urllib.request
from functools import lru_cache
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
from pyhanko_certvalidator.registry import SimpleCertificateStore
from asn1crypto import x509 as asn1_x509, algos, keys as asn1_keys, tsp
from aiohttp import BasicAuth, ClientSession, ClientTimeout

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID


APP_VERSION = "2.4.1"
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
_TEST_TSA_ISSUED = 0
_TEST_TSA_COUNTER_LOCK = threading.Lock()
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
        response.headers["Access-Control-Expose-Headers"] = "X-20-20-LT-Fallback"
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
    tsa_user = str(meta.get("tsa_user") or "")
    tsa_password = str(meta.get("tsa_password") or "")
    return {
        "certificate_thumbprint": re.sub(r"\s+", "", str(meta.get("certificate_thumbprint") or "")).upper(),
        "profile": str(meta.get("profile") or "bt").lower(),
        "tsa_url": str(meta.get("tsa_url") or "").strip(),
        "tsa_user": tsa_user.strip(),
        "tsa_credential_hash": hashlib.sha256((tsa_user + "\0" + tsa_password).encode("utf-8")).hexdigest(),
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
    payload = json.dumps(intent, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _native_sign_confirmation(
    cert_name: str,
    document_count: int,
    profile: str,
    tsa_url: str,
    documents: Optional[List[Dict[str, Any]]] = None,
    signing_intent: Optional[Dict[str, Any]] = None,
) -> bool:
    if os.name != "nt":
        return False
    tsa_label = "bez TSA"
    if profile in {"bt", "lt"}:
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
    fingerprint_short = " ".join(batch_fingerprint[i:i+4] for i in range(0, 32, 4))
    intent = signing_intent or {}
    reason = str(intent.get("reason") or "")
    location = str(intent.get("location") or "")
    message = (
        "20-20 TOOLBOX chce použít váš podpisový certifikát.\n\n"
        f"Certifikát: {cert_name}\n"
        f"Počet PDF: {document_count}\n"
        f"Profil: {'PAdES B-LT' if profile == 'lt' else ('PAdES B-T' if profile == 'bt' else 'PAdES B-B')}\n"
        f"TSA: {tsa_label}\n"
        f"Důvod: {reason or 'neuveden'}\n"
        f"Místo: {location or 'neuvedeno'}\n"
        f"Otisk dávky: {fingerprint_short}\n\n"
        + (("Dokumenty:\n" + file_lines + "\n\n") if file_lines else "")
        + "Povolit tuto jednu podpisovou dávku?"
    )
    result = ctypes.windll.user32.MessageBoxW(
        None,
        message,
        "20-20 TOOLBOX · Potvrzení podpisu",
        0x00000004 | 0x00000030 | 0x00040000,
    )
    return result == 6


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


def _run_powershell_file(
    script: str,
    env_extra: Optional[Dict[str, str]] = None,
    timeout: int = 30,
) -> str:
    if os.name != "nt":
        raise RuntimeError("Windows Certificate Store je dostupný pouze ve Windows.")

    env = os.environ.copy()
    if env_extra:
        env.update(env_extra)

    script_path = None
    try:
        fd, script_path = tempfile.mkstemp(
            prefix="2020-auth-script-",
            suffix=".ps1",
            text=True,
        )
        os.close(fd)
        with open(script_path, "w", encoding="utf-8-sig", newline="\r\n") as fh:
            fh.write(script)

        proc = subprocess.run(
            [
                "powershell.exe",
                "-NoProfile",
                "-NonInteractive",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                script_path,
            ],
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
    finally:
        if script_path:
            try:
                os.remove(script_path)
            except OSError:
                pass


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
        supported = [bool]($keyType -eq 'RSA')
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


_WINDOWS_CERT_CHAIN_PS = r"""
$ErrorActionPreference = 'Stop'
$thumb = ($env:TWENTY20_CERT_THUMBPRINT -replace ' ','').ToUpperInvariant()
if ($thumb -notmatch '^[0-9A-F]{40,128}$') { throw 'Neplatný thumbprint certifikátu.' }
$cert = Get-ChildItem -Path 'Cert:\CurrentUser\My' -ErrorAction Stop |
  Where-Object { (($_.Thumbprint -replace ' ','').ToUpperInvariant()) -eq $thumb } |
  Select-Object -First 1
if ($null -eq $cert) {
  $cert = Get-ChildItem -Path 'Cert:\LocalMachine\My' -ErrorAction SilentlyContinue |
    Where-Object { (($_.Thumbprint -replace ' ','').ToUpperInvariant()) -eq $thumb } |
    Select-Object -First 1
}
if ($null -eq $cert) { throw 'Certifikát nebyl ve Windows nalezen.' }

# Public certificate chain only; never opens the token's private key.
$chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
try {
  $chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
  $chain.ChainPolicy.VerificationFlags = [System.Security.Cryptography.X509Certificates.X509VerificationFlags]::AllowUnknownCertificateAuthority
  $chain.ChainPolicy.UrlRetrievalTimeout = [TimeSpan]::FromSeconds(7)
  [void]$chain.Build($cert)
  if ($chain.ChainElements.Count -lt 1) { throw 'Řetězec certifikátů nelze sestavit.' }
  $first = ($chain.ChainElements[0].Certificate.Thumbprint -replace ' ','').ToUpperInvariant()
  if ($first -ne $thumb) { throw 'Nesouhlasí výchozí certifikát řetězce.' }
  $issuerCerts = @()
  for ($i = 1; $i -lt $chain.ChainElements.Count; $i++) {
    $issuerCerts += [Convert]::ToBase64String($chain.ChainElements[$i].Certificate.RawData)
  }
  ConvertTo-Json -InputObject @($issuerCerts) -Compress
} finally {
  $chain.Dispose()
}
"""


_WINDOWS_RSA_SIGN_PS = r"""
$ErrorActionPreference = 'Stop'
$thumb = ($env:TWENTY20_CERT_THUMBPRINT -replace ' ','').ToUpperInvariant()
if ($thumb -notmatch '^[0-9A-F]{40,128}$') { throw 'Neplatný thumbprint certifikátu.' }
$data = [Convert]::FromBase64String($env:TWENTY20_SIGN_DATA)
$outFile = $env:TWENTY20_SIGN_FILE
if ([string]::IsNullOrWhiteSpace($outFile)) { throw 'Chybí dočasná cesta pro RSA podpis.' }

$cert = Get-ChildItem -Path 'Cert:\CurrentUser\My' -ErrorAction Stop |
  Where-Object { (($_.Thumbprint -replace ' ','').ToUpperInvariant()) -eq $thumb } |
  Select-Object -First 1

if ($null -eq $cert) {
  $cert = Get-ChildItem -Path 'Cert:\LocalMachine\My' -ErrorAction SilentlyContinue |
    Where-Object { (($_.Thumbprint -replace ' ','').ToUpperInvariant()) -eq $thumb } |
    Select-Object -First 1
}

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

  if ($null -eq $sig) { throw 'Windows provider nevrátil žádný RSA podpis.' }
  if ($sig.Length -lt 128) { throw ('Windows provider vrátil příliš krátký RSA podpis: ' + $sig.Length + ' B.') }

  [System.IO.File]::WriteAllBytes($outFile, [byte[]]$sig)

  if (-not (Test-Path -LiteralPath $outFile)) {
    throw 'RSA podpisový soubor se nepodařilo vytvořit.'
  }

  $written = [System.IO.File]::ReadAllBytes($outFile)
  if ($written.Length -ne $sig.Length) {
    throw ('RSA podpis nebyl zapsán celý: provider=' + $sig.Length + ' B, soubor=' + $written.Length + ' B.')
  }
} finally {
  $rsa.Dispose()
}
"""


_WINDOWS_RSA_BATCH_WORKER_PS = r"""
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Write-Protocol([string]$text) {
  [Console]::Out.WriteLine($text)
  [Console]::Out.Flush()
}

try {
  $thumb = ($env:TWENTY20_CERT_THUMBPRINT -replace ' ','').ToUpperInvariant()
  if ($thumb -notmatch '^[0-9A-F]{40,128}$') { throw 'Neplatný thumbprint certifikátu.' }

  $cert = Get-ChildItem -Path 'Cert:\CurrentUser\My' -ErrorAction Stop |
    Where-Object { (($_.Thumbprint -replace ' ','').ToUpperInvariant()) -eq $thumb } |
    Select-Object -First 1

  if ($null -eq $cert) {
    $cert = Get-ChildItem -Path 'Cert:\LocalMachine\My' -ErrorAction SilentlyContinue |
      Where-Object { (($_.Thumbprint -replace ' ','').ToUpperInvariant()) -eq $thumb } |
      Select-Object -First 1
  }

  if ($null -eq $cert) { throw 'Vybraný certifikát už není ve Windows úložišti.' }
  if (-not $cert.HasPrivateKey) { throw 'Privátní klíč vybraného certifikátu není dostupný.' }

  # QSCD/token providers may report 0 or a wrong KeySize on the private RSA handle.
  # Validate the cryptographic strength using the public RSA modulus in the
  # selected certificate; the actual signature must also verify against it.
  $publicRsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($cert)
  if ($null -eq $publicRsa) { throw 'Veřejný RSA klíč certifikátu není dostupný.' }
  if ($publicRsa.KeySize -lt 2048) {
    $publicRsa.Dispose()
    throw 'Veřejný RSA klíč certifikátu je kratší než 2048 bitů.'
  }

  $expectedSignatureSize = [int][Math]::Ceiling($publicRsa.KeySize / 8.0)
  $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
  if ($null -eq $rsa) {
    $publicRsa.Dispose()
    throw 'Toolbox zatím podporuje podpis certifikátem s RSA privátním klíčem.'
  }

  Write-Protocol ('READY|' + $publicRsa.KeySize)

  try {
    while ($true) {
      $line = [Console]::In.ReadLine()
      if ($null -eq $line -or $line -eq 'QUIT') { break }
      if ([string]::IsNullOrWhiteSpace($line)) { continue }

      try {
        $data = [Convert]::FromBase64String($line)
        $sig = $rsa.SignData(
          $data,
          [System.Security.Cryptography.HashAlgorithmName]::SHA256,
          [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        )
        if ($null -eq $sig -or $sig.Length -ne $expectedSignatureSize) {
          throw 'Windows provider vrátil RSA podpis neodpovídající délky.'
        }
        if (-not ($publicRsa.VerifyData(
          $data,
          $sig,
          [System.Security.Cryptography.HashAlgorithmName]::SHA256,
          [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        ))) {
          throw 'Windows provider vytvořil podpis, který neodpovídá vybranému certifikátu.'
        }
        Write-Protocol ('OK|' + [Convert]::ToBase64String($sig))
      } catch {
        $msg = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($_.Exception.Message))
        Write-Protocol ('ERR|' + $msg)
      }
    }
  } finally {
    $rsa.Dispose()
    $publicRsa.Dispose()
  }
} catch {
  $msg = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($_.Exception.Message))
  Write-Protocol ('FATAL|' + $msg)
  exit 1
}
"""


_WINDOWS_KEY_PROBE_PS = r"""
$ErrorActionPreference = 'Stop'
$thumb = ($env:TWENTY20_CERT_THUMBPRINT -replace ' ','').ToUpperInvariant()
if ($thumb -notmatch '^[0-9A-F]{40,128}$') { throw 'Neplatný thumbprint certifikátu.' }

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

$publicRsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($cert)
if ($null -eq $publicRsa) { throw 'Veřejný RSA klíč certifikátu není dostupný.' }
try {
  if ($publicRsa.KeySize -lt 2048) { throw 'Veřejný RSA klíč certifikátu je kratší než 2048 bitů.' }
  $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
  if ($null -eq $rsa) { throw 'Privátní RSA klíč není dostupný přes Windows provider.' }
  $rsa.Dispose()
} finally {
  $publicRsa.Dispose()
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


def _windows_certificate_chain_der(thumbprint: str) -> List[bytes]:
    """Read intermediate and root certificates from Windows, without private keys."""
    thumbprint = re.sub(r"\s+", "", str(thumbprint or "")).upper()
    if not re.fullmatch(r"[0-9A-F]{40,128}", thumbprint):
        raise ValueError("Neplatný thumbprint certifikátu.")
    value = _run_powershell(
        _WINDOWS_CERT_CHAIN_PS, {"TWENTY20_CERT_THUMBPRINT": thumbprint}, timeout=30
    )
    encoded = json.loads(value)
    if not isinstance(encoded, list) or len(encoded) > 12:
        raise ValueError("Neplatný seznam certifikátů od Windows.")
    return [base64.b64decode(item, validate=True) for item in encoded]


def _certificate_registry_for_chain(
    leaf_der: bytes, issuer_certificates_der: List[bytes]
) -> SimpleCertificateStore:
    """Trustless store: each public issuer must have signed the previous cert."""
    registry = SimpleCertificateStore()
    child = x509.load_der_x509_certificate(leaf_der)
    for item in issuer_certificates_der:
        parent = x509.load_der_x509_certificate(item)
        child.verify_directly_issued_by(parent)
        registry.register(asn1_x509.Certificate.load(item))
        child = parent
    return registry


# The two hashes come from public issuer certificates in a PDF-XChange
# reference signature independently verified against the user's leaf cert.
# They pin *downloaded bytes*, NOT trusted certificate authorities.
_POSTSIGNUM_QCA4_ISSUERS = (
    ("https://www.postsignum.cz/files/ca/postsignum_qca4_sub.cer",
     "4779ba66c768fe7e5a5bb74a225fa8b69cd6942af481355630e5ad78b34dff2b"),
    ("https://www.postsignum.cz/files/ca/postsignum_qca4_root.cer",
     "ac7f7862e685c7a7d9826a58ea32d183d4893fcc8f8fd6d900c9769a987e77f0"),
)


def _uses_postsignum_qca4(leaf_der: bytes) -> bool:
    leaf = x509.load_der_x509_certificate(leaf_der)
    attrs = leaf.issuer.get_attributes_for_oid(NameOID.COMMON_NAME)
    return bool(attrs) and attrs[0].value == "PostSignum Qualified CA 4"


@lru_cache(maxsize=2)
def _download_pinned_issuer(url: str, expected_sha256: str) -> bytes:
    """Fetch an official HTTPS DER cert and verify its exact published hash."""
    allowed = dict(_POSTSIGNUM_QCA4_ISSUERS)
    if url not in allowed or expected_sha256 != allowed[url]:
        raise ValueError("Nepovolený nebo změněný vydávající certifikát CA.")
    request = urllib.request.Request(url, headers={"User-Agent": "20-20-AuthorizationBridge/2"})
    with urllib.request.urlopen(request, timeout=8) as response:
        der = response.read(100_001)
    if len(der) > 100_000 or len(der) < 128:
        raise ValueError("Chybná velikost staženého veřejného certifikátu CA.")
    if hashlib.sha256(der).hexdigest() != expected_sha256:
        raise ValueError("Otisk staženého certifikátu PostSignum nesouhlasí s referencí.")
    x509.load_der_x509_certificate(der)
    return der


def _postsignum_qca4_chain(leaf_der: bytes) -> List[bytes]:
    if not _uses_postsignum_qca4(leaf_der):
        return []
    leaf = x509.load_der_x509_certificate(leaf_der)
    aia = leaf.extensions.get_extension_for_class(x509.AuthorityInformationAccess).value
    from cryptography.x509.oid import AuthorityInformationAccessOID
    issuers = {str(x.access_location.value) for x in aia
               if x.access_method == AuthorityInformationAccessOID.CA_ISSUERS}
    if "http://crt.postsignum.cz/crt/psqualifiedca4.crt" not in issuers:
        raise ValueError("Certifikát PostSignum odkazuje na neznámého vydavatele.")
    certs = [_download_pinned_issuer(url, digest) for url, digest in _POSTSIGNUM_QCA4_ISSUERS]
    # The leaf must be signed by the intermediate, and the intermediate by
    # the root. These issuer certificates are never added to a trust store.
    _certificate_registry_for_chain(leaf_der, certs)
    return certs



def _windows_sign_data(thumbprint: str, data: bytes) -> bytes:
    # Use a unique directory but do NOT pre-create the output file.
    # This makes "provider never wrote anything" distinguishable from a real
    # zero-length result and avoids transient locks on a pre-created temp file.
    with tempfile.TemporaryDirectory(prefix="2020-rsa-signature-") as temp_dir:
        signature_path = os.path.join(temp_dir, "signature.bin")

        _run_powershell_file(
            _WINDOWS_RSA_SIGN_PS,
            {
                "TWENTY20_CERT_THUMBPRINT": thumbprint,
                "TWENTY20_SIGN_DATA": base64.b64encode(data).decode("ascii"),
                "TWENTY20_SIGN_FILE": signature_path,
            },
            timeout=120,
        )

        if not os.path.exists(signature_path):
            raise ValueError(
                "Windows provider podpis vytvořil bez chyby, ale nevznikl podpisový soubor."
            )

        with open(signature_path, "rb") as fh:
            signature = fh.read()

        if len(signature) < 128:
            raise ValueError(
                f"Windows vrátil neplatný RSA podpis ({len(signature)} B)."
            )
        return signature


def _verify_windows_private_key_available(signer: "WindowsStoreSigner") -> None:
    # Success/failure is determined by the PowerShell exit code only.
    # Do not parse stdout here: Windows PowerShell output encoding can vary
    # by machine and provider (including QSCD/smart-card providers).
    _run_powershell(
        _WINDOWS_KEY_PROBE_PS,
        {"TWENTY20_CERT_THUMBPRINT": signer.thumbprint},
        timeout=30,
    )
    if int(getattr(signer, "signature_size", 0)) * 8 < 2048:
        raise ValueError("RSA klíč je kratší než 2048 bitů.")


class WindowsRsaBatchSession:
    """Keep one Windows/QSCD RSA handle open for one signing batch."""

    def __init__(self, thumbprint: str, expected_signature_size: int):
        self.thumbprint = re.sub(r"\s+", "", str(thumbprint or "")).upper()
        self.expected_signature_size = int(expected_signature_size)
        self._proc = None
        self._script_path = None

    def open(self) -> "WindowsRsaBatchSession":
        if os.name != "nt":
            raise RuntimeError("Windows podpisová session je dostupná pouze ve Windows.")
        if self._proc is not None:
            return self

        fd, self._script_path = tempfile.mkstemp(
            prefix="2020-rsa-batch-", suffix=".ps1"
        )
        os.close(fd)
        with open(self._script_path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(_WINDOWS_RSA_BATCH_WORKER_PS)

        env = os.environ.copy()
        env["TWENTY20_CERT_THUMBPRINT"] = self.thumbprint

        self._proc = subprocess.Popen(
            [
                "powershell.exe",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                self._script_path,
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            env=env,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )

        line = self._proc.stdout.readline().strip() if self._proc.stdout else ""
        if not line.startswith("READY|"):
            self.close()
            if line.startswith("FATAL|"):
                try:
                    detail = base64.b64decode(line.split("|", 1)[1]).decode(
                        "utf-8", "replace"
                    )
                except Exception:
                    detail = "Windows podpisovou session se nepodařilo otevřít."
                raise RuntimeError(detail)
            raise RuntimeError("Windows podpisovou session se nepodařilo inicializovat.")
        return self

    def sign(self, data: bytes) -> bytes:
        if self._proc is None or self._proc.poll() is not None:
            raise RuntimeError("Windows podpisová session není aktivní.")
        if not self._proc.stdin or not self._proc.stdout:
            raise RuntimeError("Windows podpisová session nemá komunikační kanál.")

        self._proc.stdin.write(base64.b64encode(data).decode("ascii") + "\n")
        self._proc.stdin.flush()

        line = self._proc.stdout.readline().strip()
        if line.startswith("ERR|") or line.startswith("FATAL|"):
            try:
                detail = base64.b64decode(line.split("|", 1)[1]).decode(
                    "utf-8", "replace"
                )
            except Exception:
                detail = "Windows provider podpis odmítl."
            raise RuntimeError(detail)
        if not line.startswith("OK|"):
            raise RuntimeError("Windows provider vrátil neplatnou odpověď.")

        signature = base64.b64decode(line.split("|", 1)[1], validate=True)
        if len(signature) != self.expected_signature_size:
            raise RuntimeError(
                f"Windows provider vrátil podpis neočekávané délky "
                f"({len(signature)} B, očekáváno {self.expected_signature_size} B)."
            )
        return signature

    def close(self) -> None:
        proc = self._proc
        self._proc = None
        if proc is not None:
            try:
                if proc.poll() is None and proc.stdin:
                    proc.stdin.write("QUIT\n")
                    proc.stdin.flush()
            except Exception:
                pass
            try:
                proc.wait(timeout=3)
            except Exception:
                try:
                    proc.kill()
                except Exception:
                    pass
        if self._script_path:
            try:
                os.remove(self._script_path)
            except OSError:
                pass
            self._script_path = None


class WindowsStoreSigner(signers.ExternalSigner):
    def __init__(
        self,
        thumbprint: str,
        sign_session: Optional[WindowsRsaBatchSession] = None,
    ):
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
        self.sign_session = sign_session
        windows_chain_error = ""
        try:
            ca_certs = _windows_certificate_chain_der(self.thumbprint)
            ca_store = _certificate_registry_for_chain(cert_der, ca_certs)
        except Exception as exc:
            windows_chain_error = str(exc)
            ca_certs, ca_store = [], SimpleCertificateStore()

        if _uses_postsignum_qca4(cert_der) and len(ca_certs) < 2:
            # Require the full real-CA chain BEFORE approving even one PDF.
            # Never spend a paid PostSignum TSA timestamp on a known
            # incomplete PostSignum signer CMS certificate chain.
            try:
                ca_certs = _postsignum_qca4_chain(cert_der)
                ca_store = _certificate_registry_for_chain(cert_der, ca_certs)
            except Exception as exc:
                raise RuntimeError(
                    "Chybí ověřený řetězec PostSignum Qualified CA 4. "
                    "Podepisování dávky zastaveno před použitím TSA. "
                    "Windows: " + (windows_chain_error or "jen část řetězce") +
                    "; PostSignum CA: " + str(exc)
                ) from exc
        elif windows_chain_error:
            print("[AuthorizationBridge] CA chain unavailable:", windows_chain_error, flush=True)

        self.ca_certificate_count = len(ca_certs)
        self.issuer_certificates_der = tuple(ca_certs)
        super().__init__(
            signing_cert=asn1_x509.Certificate.load(cert_der),
            cert_registry=ca_store,
            signature_value=self.signature_size,
            signature_mechanism=algos.SignedDigestAlgorithm({"algorithm": "sha256_rsa"}),
        )

    async def async_sign_raw(self, data: bytes, digest_algorithm: str, dry_run: bool = False) -> bytes:
        if dry_run:
            return b"\x00" * self.signature_size
        if str(digest_algorithm or "").lower().replace("-", "") != "sha256":
            raise ValueError("Windows signer je nastavený na SHA-256.")
        if self.sign_session is not None:
            return self.sign_session.sign(data)
        return _windows_sign_data(self.thumbprint, data)



class CountingDummyTimeStamper(DummyTimeStamper):
    """Local TEST TSA with an exact counter of generated timestamp tokens."""

    def request_tsa_response(self, req: tsp.TimeStampReq) -> tsp.TimeStampResp:
        global _TEST_TSA_ISSUED
        response = super().request_tsa_response(req)
        with _TEST_TSA_COUNTER_LOCK:
            _TEST_TSA_ISSUED += 1
        return response


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
    _TEST_TSA = CountingDummyTimeStamper(
        tsa_cert=asn1_x509.Certificate.load(cert_der),
        tsa_key=asn1_keys.PrivateKeyInfo.load(key_der),
        certs_to_embed=None,
        include_nonce=True,
    )
    return _TEST_TSA


def _is_local_test_lt(meta: Dict[str, Any]) -> bool:
    """Explicit local TSA selection; never bypass production LT checks otherwise."""
    return (
        str(meta.get("profile") or "").lower() == "lt"
        and meta.get("tsa_test_mode") is True
        and str(meta.get("tsa_url") or "").strip() == "http://127.0.0.1:8094/test-tsa"
    )


def _build_timestamper(meta: Dict[str, Any]):
    profile = str(meta.get("profile") or "bt").lower()
    tsa_url = str(meta.get("tsa_url") or "").strip()
    tsa_user = str(meta.get("tsa_user") or "").strip()
    tsa_password = str(meta.get("tsa_password") or "")
    tsa_test_mode = bool(meta.get("tsa_test_mode", False))

    if profile not in {"bt", "lt"}:
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


async def _async_verify_tsa_credentials(meta: Dict[str, Any]) -> None:
    profile = str(meta.get("profile") or "bt").lower()
    if profile not in {"bt", "lt"}:
        return

    tsa_url = str(meta.get("tsa_url") or "").strip()
    tsa_user = str(meta.get("tsa_user") or "").strip()
    tsa_password = str(meta.get("tsa_password") or "")
    tsa_test_mode = bool(meta.get("tsa_test_mode", False))

    if tsa_test_mode:
        if not (
            secrets.compare_digest(tsa_user, _TEST_TSA_USER)
            and secrets.compare_digest(tsa_password, _TEST_TSA_PASSWORD)
        ):
            raise PermissionError("Neplatný TEST TSA login nebo heslo.")
        return

    auth = BasicAuth(tsa_user, tsa_password) if tsa_user else None
    timeout = ClientTimeout(total=15)

    # Deliberately malformed RFC 3161 body. This checks HTTPS reachability
    # and HTTP Basic credentials without requesting a valid timestamp token.
    # A valid TSA must reject this body, so no paid timestamp is issued.
    headers = {
        "Content-Type": "application/timestamp-query",
        "Accept": "application/timestamp-reply",
        "Cache-Control": "no-store",
    }
    async with ClientSession(timeout=timeout) as session:
        async with session.post(
            tsa_url,
            data=b"\x30\x00",
            headers=headers,
            auth=auth,
            allow_redirects=False,
        ) as response:
            await response.read()
            if response.status in {401, 403}:
                raise PermissionError("Neplatný login nebo heslo k TSA.")
            if 300 <= response.status < 400:
                raise ValueError(
                    f"TSA server vrátil přesměrování HTTP {response.status}."
                )
            if response.status >= 500:
                raise ValueError(
                    f"TSA server je dočasně nedostupný (HTTP {response.status})."
                )


def _verify_tsa_login(meta: Dict[str, Any]) -> None:
    asyncio.run(_async_verify_tsa_credentials(meta))


@app.get("/test-tsa-stats")
def test_tsa_stats():
    with _TEST_TSA_COUNTER_LOCK:
        issued = int(_TEST_TSA_ISSUED)
    return jsonify(ok=True, issued=issued)


@app.post("/test-tsa-stats/reset")
def reset_test_tsa_stats():
    global _TEST_TSA_ISSUED
    with _TEST_TSA_COUNTER_LOCK:
        _TEST_TSA_ISSUED = 0
    return jsonify(ok=True, issued=0)


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
    # ISO 19005-3 clause 6.1.13: decoded PDF strings must not exceed
    # 32767 bytes. This value is HEX CHARACTERS, not decoded bytes.
    # 65532 hex characters => 32766 decoded bytes, within PDF/A-3b.
    #
    # Keep explicit sizing: pyHanko's automatic CMS/TSA estimation can
    # consume an ADDITIONAL paid timestamp for every drawing.
    # Never automatically retry after a CMS reservation overflow; the TSA
    # could already have issued one chargeable timestamp.
    hex_reservation = 65532
    if hex_reservation // 2 > 32767:
        raise RuntimeError("Podpisová rezervace přesahuje limit PDF/A-3b.")
    try:
        pdf_signer.sign_pdf(
            writer,
            output=output_stream,
            bytes_reserved=hex_reservation,
        )
    except Exception as exc:
        if "reserved" in str(exc).lower() or "space" in str(exc).lower():
            raise RuntimeError(
                "Podpis nebo TSA překročily kapacitu PDF/A-3b rezervace. "
                "Podepisování neopakuj automaticky — TSA už mohla vydat razítko."
            ) from exc
        raise
    return output_stream.getvalue()



# Independent read-only local validation; never accesses Windows private keys.
# Origin and X-20-20-Session are enforced by protect_local_bridge().
@app.get("/validator-status")
def validator_status():
    validator_root = Path(os.environ.get("LOCALAPPDATA") or str(Path.home())) / "20-20-TOOLBOX" / "PDFValidator"
    dss_dir = Path(os.environ.get("LOCALAPPDATA") or str(Path.home())) / "20-20-TOOLBOX" / "EU-DSS"
    dss_install = dss_dir / "6.5" / "Webapp-Startup.bat"
    dss_running = False
    if dss_install.is_file():
        try:
            from eu_dss_validator import _ping as check_local_dss
            dss_running = bool(check_local_dss())
        except Exception:
            pass
    proc = _DSS_INSTALL_PROCESS
    installing = proc is not None and proc.poll() is None
    dss_install_error = ""
    dss_start_log = ""
    if dss_install.is_file() and not dss_running:
        log_path = dss_dir / "6.5" / "startup.log"
        if log_path.is_file():
            with log_path.open("rb") as stream:
                stream.seek(0, 2)
                stream.seek(max(0, stream.tell() - 1000))
                dss_start_log = stream.read(1000).decode("utf-8", errors="replace").strip()[-700:]
    if proc is not None and proc.poll() not in (None, 0):
        log_path = dss_dir / "install.log"
        if log_path.is_file():
            dss_install_error = log_path.read_text(encoding="utf-8-sig", errors="replace")[-800:]
    verapdf_ready = any(p.is_file() for p in (
        validator_root / "veraPDF" / "verapdf.bat",
        validator_root / "veraPDF" / "bin" / "verapdf.bat",
    ))
    return jsonify(
        ok=True, bridge_version=APP_VERSION,
        verapdf_ready=verapdf_ready,
        eidas_ready=(validator_root / "venv" / "Scripts" / "python.exe").is_file(),
        tsa_ready=False,  # legacy pyHanko QTSA no longer used
        dss_ready=dss_running,
        dss_installed=dss_install.is_file(),
        dss_installing=installing,
        dss_install_error=dss_install_error,
        dss_start_log=dss_start_log,
        read_only=True,
    )


# DSS download is deliberately initiated only by an explicit Toolbox click.
# It downloads the official read-only demonstration bundle; no signing access.
_DSS_INSTALL_PROCESS = None


@app.post("/install-eu-dss")
def install_eu_dss_endpoint():
    global _DSS_INSTALL_PROCESS
    if os.name != "nt":
        return jsonify(ok=False, error="Automatická instalace EU DSS je určena pro Windows."), 400
    root = Path(os.environ.get("LOCALAPPDATA") or str(Path.home())) / "20-20-TOOLBOX" / "EU-DSS"
    if (root / "6.5" / "Webapp-Startup.bat").is_file():
        return jsonify(ok=True, status="installed")
    if _DSS_INSTALL_PROCESS is not None and _DSS_INSTALL_PROCESS.poll() is None:
        return jsonify(ok=True, status="installing")
    installer = Path(__file__).with_name("INSTALL_EU_DSS.ps1")
    if not installer.is_file():
        return jsonify(ok=False, error="Chybí lokální INSTALL_EU_DSS.ps1; aktualizuj Bridge."), 503
    root.mkdir(parents=True, exist_ok=True)
    try:
        _DSS_INSTALL_PROCESS = subprocess.Popen(
            ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
             "-File", str(installer)],
            cwd=str(root), stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
    except OSError as exc:
        return jsonify(ok=False, error="Nelze spustit instalátor EU DSS: " + str(exc)), 500
    return jsonify(ok=True, status="installing")


@app.post("/validate-pdf")
def validate_pdf_endpoint():
    upload = request.files.get("file")
    if not upload:
        return jsonify(ok=False, error="Nebyl přiložen PDF soubor."), 400
    # Multipart upload limit 150 MB. The checker itself re-verifies size.
    if request.content_length and request.content_length > 151 * 1024 * 1024:
        return jsonify(ok=False, error="PDF je větší než 150 MB."), 413
    runner = Path(__file__).with_name("pdf_validator_engine.py")
    if not runner.is_file():
        return jsonify(ok=False, error="Chybí modul pdf_validator_engine.py; spusť nový instalátor Bridge."), 503
    with tempfile.TemporaryDirectory(prefix="2020-pdf-validate-") as tmp:
        input_path = Path(tmp) / "input.pdf"
        size = 0
        with input_path.open("wb") as out:
            while True:
                chunk = upload.stream.read(1024 * 1024)
                if not chunk:
                    break
                size += len(chunk)
                if size > 150 * 1024 * 1024:
                    return jsonify(ok=False, error="PDF překročilo 150 MB."), 413
                out.write(chunk)
        try:
            check = subprocess.run(
                [sys.executable, str(runner), str(input_path)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True, encoding="utf-8", errors="replace",
                stdin=subprocess.DEVNULL, timeout=540,
            )
        except subprocess.TimeoutExpired:
            return jsonify(ok=False, error="Časový limit lokální validace byl překročen (540 s)."), 504
        if check.returncode != 0:
            return jsonify(ok=False, error="Lokální validace selhala.", detail=(check.stderr or check.stdout)[-1500:]), 500
        try:
            result = json.loads(check.stdout)
        except (ValueError, TypeError):
            return jsonify(ok=False, error="Lokální validační proces nevrátil správný JSON."), 500
        return jsonify(ok=True, result=result)


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
            "tsa_nonconsuming_preflight": True,
            "fixed_signature_reservation": True,
            "pdfa3b_signature_string_limit": True,
            "integrated_pdf_validator": True,
            "local_eu_dss_validator": True,
            "pdf_signature_evidence": True,
            "persistent_qscd_batch_session": True,
            "verified_rsa_signatures": True,
            "windows_cert_chain_embedding": True,
            "pades_lt_dss": True,
            "test_tsa_counter": True,
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
        return jsonify(ok=True, thumbprint=thumbprint,
                       ca_certificate_count=signer.ca_certificate_count,
                       **_cert_payload(signer))
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
        if profile not in {"bb", "bt", "lt"}:
            return jsonify(ok=False, error="Podporované profily jsou PAdES B-B, B-T a B-LT."), 400

        if profile == "lt" and not _is_local_test_lt(meta) and (
            bool(meta.get("tsa_test_mode"))
            or str(meta.get("tsa_url") or "").strip().lower().startswith(
                ("http://127.0.0.1", "http://localhost")
            )
        ):
            return jsonify(ok=False, error="Ostré B-LT vyžaduje produkční TSA; pro laboratorní B-LT zvol lokální TEST TSA."), 400

        signer = WindowsStoreSigner(cert_thumbprint)
        if profile == "lt" and not _is_local_test_lt(meta) and signer.ca_certificate_count < 2:
            return jsonify(ok=False, error="PAdES B-LT vyžaduje úplný řetězec CA ještě před žádostí o TSA."), 400
        cert_info = _cert_payload(signer)
        cert_info["ca_certificate_count"] = signer.ca_certificate_count
        crypto_cert = x509.load_der_x509_certificate(signer.signing_cert.dump())

        now = datetime.now(timezone.utc)
        valid_from = getattr(
            crypto_cert,
            "not_valid_before_utc",
            crypto_cert.not_valid_before.replace(tzinfo=timezone.utc),
        )
        valid_to = getattr(
            crypto_cert,
            "not_valid_after_utc",
            crypto_cert.not_valid_after.replace(tzinfo=timezone.utc),
        )
        if now < valid_from or now > valid_to:
            return jsonify(ok=False, error="Vybraný podpisový certifikát není v tuto chvíli platný."), 400

        try:
            key_usage = crypto_cert.extensions.get_extension_for_class(x509.KeyUsage).value
            if not (key_usage.digital_signature or key_usage.content_commitment):
                return jsonify(ok=False, error="Vybraný certifikát nemá povolené použití pro elektronický podpis."), 400
        except x509.ExtensionNotFound:
            pass

        # Do not acquire/use the private key during preflight.
        # _windows_cert_der already verifies that Windows marks a private key
        # as present; the QSCD is only activated during the actual signature.
        try:
            _build_timestamper(meta)
            _verify_tsa_login(meta)
        except PermissionError as exc:
            return jsonify(ok=False, error=str(exc)), 401
        except Exception as exc:
            return jsonify(ok=False, error="TSA ověření selhalo: " + str(exc)), 400

        _cleanup_approvals()
        token = secrets.token_urlsafe(32)
        _PREFLIGHTS[token] = {
            "context": _approval_context(meta, document_count),
            "certificate_name": str(cert_info.get("display_name") or cert_info.get("subject") or "Windows certifikát"),
            "expires": datetime.now(timezone.utc).timestamp() + _APPROVAL_TTL_SECONDS,
            "used": False,
        }

        return jsonify(
            ok=True,
            preflight_token=token,
            expires_in=_APPROVAL_TTL_SECONDS,
            certificate=cert_info,
            tsa_verified=(profile in {"bt", "lt"}),
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
            signing_intent,
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
    rsa_batch_session = None
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
        if profile not in {"bb", "bt", "lt"}:
            return jsonify(ok=False, error="Podporované profily jsou PAdES B-B, B-T a B-LT."), 400
        if profile == "lt" and not _is_local_test_lt(meta) and (
            test_mode or bool(meta.get("tsa_test_mode"))
            or str(meta.get("tsa_url") or "").strip().lower().startswith(
                ("http://127.0.0.1", "http://localhost")
            )
        ):
            return jsonify(ok=False, error="Ostré B-LT vyžaduje skutečný certifikát a kvalifikovanou TSA; pro TEST B-LT použij lokální TEST TSA."), 400

        approval = None
        if not test_mode:
            _cleanup_approvals()
            approval_token = str(meta.get("approval_token") or "")
            approval = _SIGN_APPROVALS.get(approval_token)
            if not approval or bool(approval.get("used")):
                return jsonify(ok=False, error="Chybí platné lokální potvrzení podpisové dávky."), 403

            if approval.get("context") != _approval_context(meta, len(pdfs)):
                return jsonify(ok=False, error="Podpisová dávka neodpovídá lokálně potvrzenému požadavku."), 403

            if len(approval.get("documents") or []) != len(pdfs):
                return jsonify(ok=False, error="Počet PDF neodpovídá lokálně potvrzené dávce."), 403

        tsa_url = str(meta.get("tsa_url") or "").strip()
        tsa_user = str(meta.get("tsa_user") or "").strip()

        try:
            timestamper = _build_timestamper(meta)
        except PermissionError as exc:
            return jsonify(ok=False, error=str(exc)), 401
        except Exception as exc:
            return jsonify(ok=False, error=str(exc)), 400

        signer = _make_test_signer() if test_mode else WindowsStoreSigner(cert_thumbprint)
        if profile == "lt" and not _is_local_test_lt(meta) and (test_mode or getattr(signer, "ca_certificate_count", 0) < 2):
            return jsonify(ok=False, error="PAdES B-LT vyžaduje skutečný Windows certifikát a celý řetězec CA."), 400
        cert_info = _cert_payload(signer)
        if not test_mode:
            cert_info["ca_certificate_count"] = signer.ca_certificate_count
            cert_info["thumbprint"] = re.sub(r"\s+", "", cert_thumbprint).upper()
            cert_info["source"] = "Windows Certificate Store"

            # One provider handle for the whole request. This is the best chance
            # for QSCD middleware to ask for the PIN only once per batch.
            rsa_batch_session = WindowsRsaBatchSession(
                cert_thumbprint,
                signer.signature_size,
            ).open()
            signer.sign_session = rsa_batch_session

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
            if _intent_digest(_canonical_signing_intent(meta, stamp_bytes)) != str(approval.get("intent_digest") or ""):
                return jsonify(ok=False, error="Podpisová metadata nebo grafika se po lokálním potvrzení změnily."), 403

        if stamp_bytes:
            with tempfile.NamedTemporaryFile(prefix="2020-stamp-", suffix=stamp_ext, delete=False) as tmp:
                tmp.write(stamp_bytes)
                stamp_path = tmp.name

        buffered_pdfs = []
        for idx, uploaded in enumerate(pdfs):
            original_name = uploaded.filename or f"document_{idx + 1}.pdf"
            raw_pdf = uploaded.read()

            if not raw_pdf.startswith(b"%PDF-"):
                raise ValueError(f"{original_name}: soubor nevypadá jako PDF.")

            if approval is not None:
                expected_doc = (approval.get("documents") or [])[idx]
                if (
                    str(expected_doc.get("name") or "") != original_name
                    or int(expected_doc.get("size") or 0) != len(raw_pdf)
                    or str(expected_doc.get("sha256") or "").lower() != hashlib.sha256(raw_pdf).hexdigest()
                ):
                    raise PermissionError(f"{original_name}: obsah PDF se po lokálním potvrzení změnil.")

            buffered_pdfs.append((original_name, raw_pdf))

        if approval is not None:
            approval["used"] = True

        out_zip = io.BytesIO()
        laboratory = bool(test_mode or meta.get("tsa_test_mode"))
        used_names: set[str] = set()
        manifest_files = []
        lt_fallback_warnings = []

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
                    lt_failure = None
                    if profile == "lt":
                        from pdf_ltv import append_validated_dss
                        # If revocation fetching fails AFTER TSA issuance,
                        # preserve the signed B-T PDF instead of discarding
                        # the user's already-paid timestamp. Never relabel it LT.
                        try:
                            signed = append_validated_dss(
                                signed, getattr(signer, "issuer_certificates_der", []),
                            )
                        except Exception as exc:
                            lt_failure = str(exc)[:450]
                            lt_fallback_warnings.append(
                                str(original_name) + ": " + lt_failure
                            )
                except Exception as exc:
                    raise RuntimeError(f"PAdES SIGN [{original_name}]: {exc}") from exc

                requested_output = str(doc_meta.get("output_name") or original_name)
                requested_output = _ear_name(requested_output) if bool(meta.get("append_ear", True)) else _safe_name(requested_output)
                out_name = _unique_name(requested_output, used_names)

                zf.writestr(out_name, signed)
                manifest_files.append({
                    "source": str(doc_meta.get("name") or original_name),
                    "output": out_name,
                    "standard": str(meta.get("output_standard") or "PDF/A-3b"),
                    "profile": ("PAdES B-T (LT fallback)" if lt_failure else ("PAdES B-LT" if profile == "lt" else ("PAdES B-T" if profile == "bt" else "PAdES B-B"))) + (" [TEST - not qualified]" if laboratory else ""),
                    "lt_warning": lt_failure,
                    "visible": bool(doc_meta.get("placement")),
                    "docmdp": "ANNOTATE",
                })

            manifest = {
                "tool": "20-20 TOOLBOX · Autorizace PDF",
                "bridge_version": APP_VERSION,
                "created_utc": datetime.now(timezone.utc).isoformat(),
                "profile": ("PAdES B-T (LT fallback)" if lt_fallback_warnings else ("PAdES B-LT" if profile == "lt" else ("PAdES B-T" if profile == "bt" else "PAdES B-B"))) + (" [TEST - not qualified]" if laboratory else ""),
                "test_mode": laboratory,
                "test_signer": test_mode,
                "not_qualified_test_output": laboratory,
                "output_standard": str(meta.get("output_standard") or "PDF/A-3b"),
                "append_ear": bool(meta.get("append_ear", True)),
                "docmdp": "ANNOTATE",
                "tsa_url": tsa_url if profile in {"bt", "lt"} else None,
                "tsa_authenticated": bool(tsa_user) if profile in {"bt", "lt"} else False,
                "tsa_test_mode": bool(meta.get("tsa_test_mode", False)) if profile in {"bt", "lt"} else False,
                "certificate": cert_info,
                "files": manifest_files,
            }
            if lt_fallback_warnings:
                warning = (
                    "POZOR: PAdES B-LT nebylo dokonceno, proto jsou PDF "
                    "ulozena s puvodnim kryptografickym PAdES B-T podpisem "
                    "a jeho jiz vydanym casovym razitkem. "
                    "Nedochazelo k dalsimu TSA pozadavku. "
                    "Tyto soubory nejsou PAdES B-LT. "
                    "Pred odevzdanim over podpis a QTSA v EU DSS.\n\n"
                    + "\n".join(lt_fallback_warnings)
                )
                zf.writestr("POZOR_PAdES_LT_NEPROVEDENO.txt", warning)
            if laboratory:
                zf.writestr(
                    "TEST_NEPLATNE_PRO_URAD.txt",
                    "TEST / LABORATORY ONLY. This document is NOT a qualified "
                    "electronic signature or qualified timestamp. A TEST PAdES B-LT "
                    "label describes only the laboratory structure; trusted "
                    "EU DSS validation must be performed separately.\n",
                )
            manifest["lt_fallback_warnings"] = lt_fallback_warnings
            zf.writestr("20-20_autorizace_manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))

        out_zip.seek(0)
        response = send_file(
            out_zip,
            mimetype="application/zip",
            as_attachment=True,
            download_name="autorizovane_pdf_" + datetime.now().strftime("%Y-%m-%d_%H%M") + ".zip",
            max_age=0,
        )
        response.headers["X-20-20-LT-Fallback"] = "1" if lt_fallback_warnings else "0"
        return response

    except Exception as exc:
        print("[AuthorizationBridge] signing error:", traceback.format_exc(), flush=True)
        return jsonify(ok=False, error=str(exc)), 400
    finally:
        if rsa_batch_session is not None:
            rsa_batch_session.close()
        if stamp_path:
            try:
                os.remove(stamp_path)
            except OSError:
                pass


if __name__ == "__main__":
    print(f"20-20 AuthorizationBridge v{APP_VERSION} · http://{HOST}:{PORT}", flush=True)
    app.run(host=HOST, port=PORT, threaded=True, debug=False, use_reloader=False)
