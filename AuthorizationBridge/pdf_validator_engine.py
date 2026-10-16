"""Independent, local PDF/A-3b + qualified eIDAS validation for 20-20 TOOLBOX.

Invoked as a subprocess by AuthorizationBridge. A failed trust-list download
must NEVER be presented as a cryptographically invalid signature.
The signed PDF is not uploaded to the web; pyHanko retrieves public trust
lists and revocation data (CRL/OCSP) over the network.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
import urllib.request
from datetime import timedelta
from pathlib import Path


MAX_OUTPUT = 120_000
ROOT = Path(os.environ.get("LOCALAPPDATA") or str(Path.home()))
INSTALL_DIR = ROOT / "20-20-TOOLBOX" / "PDFValidator"
VERAPDF_CANDIDATES = [
    INSTALL_DIR / "veraPDF" / "verapdf.bat",
    INSTALL_DIR / "veraPDF" / "bin" / "verapdf.bat",
]
JAVA = INSTALL_DIR / "jre" / "bin" / "java.exe"


def parse_verapdf(xml: str) -> tuple[str, list[str]]:
    try:
        root = ET.fromstring(xml)
    except ET.ParseError:
        return "unverified", ["veraPDF nevrátil validní XML report."]
    reports = [x for x in root.iter() if x.tag.split("}")[-1] == "validationReport"]
    if len(reports) != 1:
        return "unverified", ["Chybí jednoznačný validační report veraPDF."]
    report = reports[0]
    errors = []
    for rule in report.iter():
        if rule.tag.split("}")[-1] != "rule":
            continue
        if any(c.tag.split("}")[-1] == "check" and c.get("status") == "failed" for c in rule.iter()):
            errors.append("ISO 19005-3: "
                          f"článek {rule.get('clause','?')}, test {rule.get('testNumber','?')}. "
                          f"{rule.get('description','')}")
    compliant = (report.get("isCompliant") or "").lower()
    if compliant == "true":
        return "valid", []
    if compliant == "false":
        return "invalid", errors[:20] or ["PDF nesplňuje PDF/A-3b (veraPDF)."]
    return "unverified", ["Výsledek veraPDF neobsahuje stav isCompliant."]


def parse_ades(code: int, stdout: str, stderr: str) -> dict:
    # Preserve independent "cryptographically sound" facts even when network
    # failures make trust or qualified status indeterminate.
    fields = re.split(r"(?m)^Field \d+: [^\r\n]+\r?\n", stdout)[1:]
    count = len(fields)
    if not count:
        return dict(signature="unverified", timestamp="unverified",
                    crypto="unverified", count=0,
                    messages=["Nepodařilo se načíst podrobný výsledek ověření podpisů."])

    crypto_bad = any("The signature is cryptographically unsound." in f for f in fields)
    crypto_good = all("The signature is cryptographically sound." in f for f in fields)
    full = all("The signature covers the entire file." in f for f in fields)
    tsa_bad = any("The timestamp token is cryptographically unsound." in f for f in fields)
    tsa_present = all("Signature timestamp token:" in f for f in fields)
    tsa_sound = all("The timestamp token is cryptographically sound." in f for f in fields)
    trusted_qualified = all(
        "The signature is judged VALID." in f
        and "The signer's certificate is trusted." in f
        and "The signer's certificate is qualified." in f
        for f in fields
    )
    qualified_tsa = all(
        "The TSA certificate is trusted." in f
        and "The time stamping authority's certificate is qualified." in f
        and "The time stamping authority is directly identified as a QTST." in f
        for f in fields
    )
    trust_problem = ("Failed to download trusted list" in stderr
                     or "No path to trust anchor found" in stdout
                     or "Errors encountered during trust list processing" in stderr)

    messages = []
    if trust_problem:
        messages.append("Důvěryhodný seznam se nepodařilo zpracovat (např. HTTP 406). "
                        "Podpis se proto nepovažuje za neplatný; kvalifikaci nelze ověřit.")
    if not full:
        messages.append("Nelze potvrdit, že podpis pokrývá celý PDF soubor.")
    if not tsa_present:
        messages.append("Chybí samostatně ověřené podpisové časové razítko.")
    if crypto_bad:
        messages.append("Kryptografická integrita alespoň jednoho podpisu selhala.")
    if tsa_bad:
        messages.append("Kryptografická integrita alespoň jednoho časového razítka selhala.")
    if code != 0 and not trust_problem and not (crypto_bad or tsa_bad):
        messages.append("eIDAS ověřování se nedokončilo; detail je v reportu.")

    return dict(
        signature=("invalid" if crypto_bad else
                   "valid" if code == 0 and trusted_qualified and crypto_good and full else "unverified"),
        timestamp=("invalid" if tsa_bad else
                   "valid" if code == 0 and qualified_tsa and tsa_sound and tsa_present else "unverified"),
        crypto="invalid" if crypto_bad else "valid" if crypto_good and full else "unverified",
        count=count,
        messages=messages
    )



def prefetch_czech_trusted_list(python_exe: Path) -> str:
    """Work around CZ TL HTTP 406 from pyHanko's duplicated Accept headers.

    Cache a fresh copy obtained with a normal Accept header. pyHanko still
    verifies its actual XML signature against the EU LOTL and designated
    national list-signing certificates; merely caching does NOT confer trust.
    """
    url = "https://tsl.gov.cz/publ/TSL_CZ.xtsl"
    helper = r'''
import sys, urllib.request, xml.etree.ElementTree as ET
from datetime import timedelta
from pyhanko.cli.cache import get_eutl_cache_dir
from pyhanko.sign.validation.qualified.eutl_fetch import FileSystemTLCache
url="https://tsl.gov.cz/publ/TSL_CZ.xtsl"
cache=FileSystemTLCache(get_eutl_cache_dir(None), timedelta(days=2))
try:
    cached=cache[url]
    if cached.startswith("<?xml") or "TrustServiceStatusList" in cached[:400]:
        print("CZ TL: platna cache", flush=True)
        sys.exit(0)
except KeyError:
    pass
req=urllib.request.Request(url,headers={"Accept":"*/*", "User-Agent":"20-20-PDF-Validator/1.0"})
with urllib.request.urlopen(req,timeout=20) as response:
    if response.geturl() != url:
        raise RuntimeError("CZ TL byla presmerovana na neocekavanou adresu.")
    body=response.read(16*1024*1024+1)
    if len(body)>16*1024*1024:raise RuntimeError("CZ TL presahla 16 MB.")
xml=body.decode("utf-8-sig")
root=ET.fromstring(xml)
if root.tag.split("}")[-1]!="TrustServiceStatusList":
    raise RuntimeError("Odpoved neni ETSI trusted list XML.")
cache[url]=xml
print("CZ TL pripravena pro kryptograficke overeni pyHanko.",flush=True)
'''
    try:
        proc = subprocess.run(
            [str(python_exe), "-c", helper],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            stdin=subprocess.DEVNULL, timeout=45,
            env={**os.environ, "PYTHONUTF8":"1"},
        )
        if proc.returncode:
            return ("Předběžné stažení CZ TL se nezdařilo; "
                    "eIDAS validace ji zkusí sama. " +
                    (proc.stderr or proc.stdout)[-700:])
        return (proc.stdout or "").strip()
    except (OSError, subprocess.TimeoutExpired) as exc:
        return "Důvěryhodný seznam nelze připravit: " + str(exc)


def check(pdf: Path) -> dict:
    if not pdf.is_file() or pdf.suffix.lower() != ".pdf":
        raise ValueError("Očekáván vstupní soubor PDF.")
    size = pdf.stat().st_size
    if size < 5 or size > 150 * 1024 * 1024:
        raise ValueError("PDF překročilo limit 150 MB nebo je prázdné.")
    with pdf.open("rb") as f:
        if f.read(5) != b"%PDF-":
            raise ValueError("Soubor nemá PDF hlavičku.")
    digest = hashlib.sha256()
    with pdf.open("rb") as digest_file:
        for chunk in iter(lambda: digest_file.read(1024 * 1024), b""):
            digest.update(chunk)
    checksum = digest.hexdigest()
    result = {
        "file": pdf.name,
        "sha256": checksum,
        "pdfa": "unverified",
        "signature": "unverified",
        "timestamp": "unverified",
        "crypto": "unverified",
        "signatures": 0,
        "messages": [],
        "report": ""
    }
    text_report = []
    env = dict(os.environ)
    if JAVA.is_file():
        env["JAVA_HOME"] = str(JAVA.parent.parent)
        env["PATH"] = str(JAVA.parent) + os.pathsep + env.get("PATH", "")

    cmd = next((x for x in VERAPDF_CANDIDATES if x.is_file()), None)
    if cmd is None:
        result["messages"].append("veraPDF není nainstalováno v lokální složce PDFValidator.")
    else:
        try:
            p = subprocess.run([str(cmd), "--format", "xml", "--flavour", "3b", str(pdf)],
                               capture_output=True, text=True, errors="replace",
                               timeout=180, stdin=subprocess.DEVNULL, env=env)
            result["pdfa"], errs = parse_verapdf(p.stdout)
            result["messages"].extend(errs)
            text_report.append("veraPDF PDF/A-3b:\n" + p.stdout[-MAX_OUTPUT:] + "\n" + p.stderr[-4000:])
        except (OSError, subprocess.TimeoutExpired) as ex:
            result["messages"].append("Nástroj veraPDF nelze spustit: " + str(ex))

    # The validator uses a SEPARATE virtual environment, not the private key
    # / Windows certificate signing environment of AuthorizationBridge.
    py = INSTALL_DIR / "venv" / "Scripts" / "python.exe"
    if not py.is_file():
        result["messages"].append("Lokální pyHanko eIDAS není nainstalované; spusť instalátor PDF Validatoru.")
    else:
        try:
            cache_note = prefetch_czech_trusted_list(py)
            if cache_note:
                result["messages"].append(cache_note)
            proc = subprocess.run(
                [str(py), "-m", "pyhanko", "sign", "adesverify",
                 "--eutl-territories", "cz", "--require-qualified",
                 "--pretty-print", str(pdf)],
                capture_output=True, text=True, errors="replace",
                timeout=330, stdin=subprocess.DEVNULL,
                env={**env, "PYTHONUTF8": "1"}
            )
            detail = parse_ades(proc.returncode, proc.stdout or "", proc.stderr or "")
            result.update({k: detail[k] for k in ("signature", "timestamp", "crypto")})
            result["signatures"] = detail["count"]
            result["messages"].extend(detail["messages"])
            text_report.append("pyHanko eIDAS / EU LOTL + CZ TL:\n" +
                               (proc.stdout or "")[-MAX_OUTPUT:] + "\n--- STDERR ---\n" +
                               (proc.stderr or "")[-MAX_OUTPUT:])
        except (OSError, subprocess.TimeoutExpired) as ex:
            result["messages"].append("pyHanko eIDAS nelze dokončit: " + str(ex))
    result["report"] = ("\n\n".join(text_report))[-MAX_OUTPUT:]
    return result


def self_test() -> None:
    ok = '<batch><validationReport isCompliant="true" /></batch>'
    bad = ('<batch><validationReport isCompliant="false"><rule '
           'clause="6.1.13" testNumber="3"><check status="failed" />'
           '</rule></validationReport></batch>')
    assert parse_verapdf(ok)[0] == "valid"
    assert parse_verapdf(bad)[0] == "invalid"
    assert "6.1.13" in parse_verapdf(bad)[1][0]
    assert parse_verapdf("<garbled")[0] == "unverified"
    assert parse_ades(1, "", "Failed to download trusted list")[ "signature"] == "unverified"
    assert parse_ades(0, "Field 1: S\nThe signature is cryptographically unsound.", "")["crypto"] == "invalid"
    print("validator engine self test passed")


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        self_test()
    else:
        if len(sys.argv) != 2:
            raise SystemExit("Usage: pdf_validator_engine.py input.pdf")
        try:
            print(json.dumps(check(Path(sys.argv[1])), ensure_ascii=False))
        except Exception as exc:
            print(json.dumps({"error":str(exc)}, ensure_ascii=False))
            raise SystemExit(1)
