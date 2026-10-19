"""2020 Toolbox read-only PDF Validator: veraPDF + local EU DSS 6.5.

Runs as a subprocess under AuthorizationBridge. Separate independent engines;
an outage in EU DSS must NEVER conceal a confirmed veraPDF result.
No signing key, PIN, PostSignum credentials, or TSA issuance API is used.
"""
import hashlib
import json
import os
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from eu_dss_validator import check as check_eu_dss, DSS_VERSION
from pdf_signature_inspector import inspect_file, compare_evidence

ROOT = Path(os.environ.get("LOCALAPPDATA") or str(Path.home()))
INSTALL_DIR = ROOT / "20-20-TOOLBOX" / "PDFValidator"
JAVA = INSTALL_DIR / "jre" / "bin" / "java.exe"
VERAPDF = (
    INSTALL_DIR / "veraPDF" / "verapdf.bat",
    INSTALL_DIR / "veraPDF" / "bin" / "verapdf.bat",
)


def parse_verapdf(xml_text):
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        return "unverified", ["veraPDF nevrátilo platný XML report."]
    reports = [e for e in root.iter() if e.tag.split("}")[-1] == "validationReport"]
    if len(reports) != 1:
        return "unverified", ["veraPDF nevrátilo právě jeden validační report."]
    report = reports[0]
    compliant = report.get("isCompliant", "").lower()
    failures = []
    for rule in report.iter():
        if rule.tag.split("}")[-1] != "rule":
            continue
        if any(c.tag.split("}")[-1] == "check" and c.get("status") == "failed"
               for c in rule.iter()):
            failures.append(
                "ISO 19005-3: čl. " + rule.get("clause", "?") +
                ", test " + rule.get("testNumber", "?") + " " +
                rule.get("description", "")
            )
    if compliant == "true":
        return "valid", []
    if compliant == "false":
        return "invalid", failures[:12] or ["PDF/A-3b nevyhovuje."]
    return "unverified", ["veraPDF neuvedlo jednoznačný stav."]


def check(pdf):
    if not pdf.is_file() or pdf.stat().st_size < 5:
        raise ValueError("Vstupní soubor PDF chybí nebo je prázdný.")
    if pdf.stat().st_size > 150 * 1024 * 1024:
        raise ValueError("PDF přesahuje limit 150 MB.")
    with pdf.open("rb") as inp:
        if inp.read(5) != b"%PDF-":
            raise ValueError("Chybí hlavička PDF.")
    dig = hashlib.sha256()
    with pdf.open("rb") as inp:
        for block in iter(lambda: inp.read(1024 * 1024), b""):
            dig.update(block)
    result = dict(
        file=pdf.name, sha256=dig.hexdigest(),
        pdfa="unverified", crypto="unverified",
        signature="unverified", timestamp="unverified",
        signatures=0, timestamp_count=0, messages=[], report="",
        structure={"status": "unverified", "signatures": [], "pdf_dss": {}},
        consistency={"status": "unverified", "messages": []},
        engines={"pdfa":"veraPDF 1.30.3", "eidas":"EU DSS " + DSS_VERSION},
    )
    reports = []
    # Purely structural evidence; qualified/trust verdicts stay with EU DSS.
    # Never let structural parsing failures hide veraPDF or EU DSS results.
    try:
        result["structure"] = inspect_file(pdf)
    except Exception as exc:
        result["messages"].append("Technický parser PDF není dostupný: " + str(exc)[:220])
    cmd = next((p for p in VERAPDF if p.is_file()), None)
    if cmd is None:
        result["messages"].append("veraPDF není nainstalováno.")
    else:
        env = dict(os.environ)
        if JAVA.is_file():
            env["JAVA_HOME"] = str(JAVA.parent.parent)
            env["PATH"] = str(JAVA.parent) + os.pathsep + env.get("PATH", "")
        try:
            p = subprocess.run(
                [str(cmd), "--format", "xml", "--flavour", "3b", str(pdf)],
                capture_output=True, text=True, encoding="utf-8", errors="replace",
                timeout=180, stdin=subprocess.DEVNULL, env=env,
            )
            result["pdfa"], errors = parse_verapdf(p.stdout)
            result["messages"].extend(errors)
            reports.append("veraPDF PDF/A-3b:\n" + p.stdout[-40_000:] +
                           "\n" + p.stderr[-2000:])
        except (OSError, subprocess.TimeoutExpired) as exc:
            result["messages"].append("veraPDF nelze dokončit: " + str(exc))

    try:
        eidas = check_eu_dss(pdf)
        for key in ("signature", "timestamp", "crypto", "signatures", "timestamp_count"):
            if key in eidas:
                result[key] = eidas[key]
        result["messages"].extend(eidas.get("messages", []))
        reports.append("EU DSS kvalifikovaná validace:\n" + eidas.get("report", ""))
    except Exception as exc:
        result["messages"].append(
            "EU DSS se nepodařilo dokončit: " + str(exc)[:700] +
            ". PDF/A zůstává nezávisle ověřené."
        )
    result["consistency"] = compare_evidence(result)
    result["report"] = "\n\n".join(reports)[-130_000:]
    return result


def self_test():
    yes = '<report><validationReport isCompliant="true" /></report>'
    no = ('<report><validationReport isCompliant="false"><rule clause="6.1.13" '
          'testNumber="3"><check status="failed"/></rule></validationReport></report>')
    assert parse_verapdf(yes)[0] == "valid"
    assert parse_verapdf(no)[0] == "invalid"
    assert "6.1.13" in parse_verapdf(no)[1][0]
    assert parse_verapdf("<broken")[0] == "unverified"
    assert json.dumps({"name":"Čeština \ufffd"}, ensure_ascii=True).isascii()
    print("EU DSS + veraPDF parser smoke tests passed")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
    elif len(sys.argv) == 2:
        try:
            print(json.dumps(check(Path(sys.argv[1])), ensure_ascii=True))
        except Exception as exc:
            print(json.dumps({"error":str(exc)}, ensure_ascii=True))
            sys.exit(1)
    else:
        raise SystemExit("Usage: pdf_validator_engine.py input.pdf | --self-test")
