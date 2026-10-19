"""Local EU Digital Signature Service (DSS) REST validation.

Uses the OFFICIAL EU DSS demonstration bundle installed on the user's Windows
computer and bound to 127.0.0.1:18080. Documents never go to the European
Commission website; only DSS's normal public TL/OCSP/CRL lookups use internet.
This module NEVER signs or requests timestamps.
"""
import base64
import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

DSS_VERSION = "6.5"
LOCAL_PORT = 18080
ROOT = (Path(os.environ.get("LOCALAPPDATA") or str(Path.home()))
        / "20-20-TOOLBOX" / "EU-DSS" / DSS_VERSION)
SERVICE_URL = f"http://127.0.0.1:{LOCAL_PORT}/services/rest/validation/validateSignature"
PROXYLESS = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def is_installed():
    return (ROOT / "Webapp-Startup.bat").is_file() and any(
        d.is_dir() and d.name.startswith("apache-tomcat-") and
        (d / "conf" / "server.xml").is_file()
        for d in ROOT.iterdir()
    ) if ROOT.is_dir() else False


def _ping():
    try:
        req = urllib.request.Request(
            f"http://127.0.0.1:{LOCAL_PORT}/services/rest/validation?_wadl",
            headers={"Accept": "application/xml"},
        )
        with PROXYLESS.open(req, timeout=2) as r:
            return r.status == 200 and b"validateSignature" in r.read(500_000)
    except (OSError, ValueError):
        return False


def ensure_started():
    if not is_installed():
        raise RuntimeError("EU DSS není nainstalované. V Toolboxu klikni na Instalovat EU DSS.")
    if _ping():
        return
    # Never talk to an unrelated service bound to the chosen port.
    import socket
    with socket.socket() as sock:
        sock.settimeout(2)
        if sock.connect_ex(("127.0.0.1", LOCAL_PORT)) == 0:
            raise RuntimeError(
                "Port 18080 používá jiný program nebo DSS ještě nenačetlo API. "
                "Nepředávám PDF neznámému serveru."
            )
    startup_log = ROOT / "startup.log"
    with startup_log.open("ab") as log:
        log.write(("\n--- EU DSS startup " + time.strftime("%Y-%m-%d %H:%M:%S") + " ---\n").encode("utf-8"))
        log.flush()
        proc = subprocess.Popen(
            ["cmd.exe", "/d", "/c", str(ROOT / "Webapp-Startup.bat")],
            cwd=str(ROOT), stdin=subprocess.DEVNULL, stdout=log,
            stderr=subprocess.STDOUT,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
    deadline = time.monotonic() + 240
    while time.monotonic() < deadline:
        if _ping():
            return
        code = proc.poll()
        if code is not None and code != 0:
            raise RuntimeError(f"EU DSS skončilo s chybou {code}. Zkontroluj startup.log v instalaci DSS.")
        time.sleep(2)
    raise RuntimeError("EU DSS se nespustilo do 240 sekund. Zkontroluj startup.log v instalaci DSS.")


def _items(value):
    if isinstance(value, list):
        return value
    return [value] if isinstance(value, dict) else []


def _qualification(value):
    if isinstance(value, dict):
        return str(value.get("value") or "")
    return str(value or "")


def _bad_crypto(value):
    return str(value or "") in ("SIG_CRYPTO_FAILURE", "HASH_FAILURE")


def summarize_reports(payload):
    """Interpret only structured DSS SimpleReport / DiagnosticData, fail closed."""
    simple = payload.get("SimpleReport")
    diagnostic = payload.get("DiagnosticData")
    if not isinstance(simple, dict) or not isinstance(diagnostic, dict):
        raise ValueError("EU DSS nevrátilo SimpleReport a DiagnosticData.")
    entries = _items(simple.get("signatureOrTimestampOrEvidenceRecord"))
    signatures = [entry["Signature"] for entry in entries
                  if isinstance(entry, dict) and isinstance(entry.get("Signature"), dict)]
    if not signatures:
        return dict(signature="unverified", timestamp="unverified",
                    crypto="unverified", signatures=0, timestamp_count=0,
                    messages=["EU DSS nenašlo podpis PDF."])
    notes = []
    stamps = []
    sig_outcomes = []
    for sig in signatures:
        indication = str(sig.get("Indication") or "")
        level = _qualification(sig.get("SignatureLevel"))
        sub = str(sig.get("SubIndication") or "")
        scopes = _items(sig.get("SignatureScope"))
        full = any(str(x.get("scope") or x.get("value") or "").upper() in
                   ("FULL", "FULL DOCUMENT") for x in scopes if isinstance(x, dict))
        if indication == "TOTAL_PASSED" and level == "QESig" and full:
            sig_outcomes.append("valid")
        elif indication == "TOTAL_FAILED" and _bad_crypto(sub):
            sig_outcomes.append("invalid")
        else:
            sig_outcomes.append("unverified")
        notes.append(f"EU DSS podpis: {indication or 'bez stavu'}, "
                     f"kvalifikace {level or 'neurčena'}, "
                     f"důvod {sub or 'žádný'}, celý dokument: {full}")
        timestamp_group = sig.get("Timestamps")
        if isinstance(timestamp_group, dict):
            stamps.extend(_items(timestamp_group.get("Timestamp")))

    # For some formats, DSS represents timestamp tokens at the top level.
    stamps.extend(entry["Timestamp"] for entry in entries
                  if isinstance(entry, dict) and isinstance(entry.get("Timestamp"), dict))

    # Trusted qualification and validation of a timestamp are independent
    # from QES status of the parent signature.
    stamp_outcomes = []
    for ts in stamps:
        indication = str(ts.get("Indication") or "")
        level = _qualification(ts.get("TimestampLevel"))
        sub = str(ts.get("SubIndication") or "")
        if indication == "PASSED" and level == "QTSA":
            stamp_outcomes.append("valid")
        elif indication in ("TOTAL_FAILED", "FAILED") and _bad_crypto(sub):
            stamp_outcomes.append("invalid")
        else:
            stamp_outcomes.append("unverified")
        notes.append(f"EU DSS TSA: {indication or 'bez stavu'}, "
                     f"kvalifikace {level or 'neurčena'}, {sub or ''}")

    # Verify cryptographic integrity using DSS DiagnosticData's actual
    # BasicSignature fields, not a textual "TOTAL_PASSED" inference.
    diagnostic_sigs = _items(diagnostic.get("Signature"))
    crypto_status = "unverified"
    if len(diagnostic_sigs) == len(signatures) and diagnostic_sigs:
        cryptos = [s.get("BasicSignature") for s in diagnostic_sigs]
        if all(isinstance(x, dict) for x in cryptos):
            if all(x.get("SignatureIntact") is True and
                   x.get("SignatureValid") is True for x in cryptos):
                crypto_status = "valid"
            elif any(x.get("SignatureIntact") is False or
                     x.get("SignatureValid") is False for x in cryptos):
                crypto_status = "invalid"

    def fold(outcomes):
        if not outcomes:
            return "unverified"
        if any(x == "invalid" for x in outcomes):
            return "invalid"
        return "valid" if all(x == "valid" for x in outcomes) else "unverified"

    if not stamps:
        notes.append("EU DSS nepotvrdilo přítomnost podpisového časového razítka.")
    return dict(
        signature=fold(sig_outcomes),
        timestamp=fold(stamp_outcomes),
        crypto=crypto_status,
        signatures=len(signatures),
        timestamp_count=len(stamps),
        messages=notes,
    )


def check(pdf: Path):
    ensure_started()
    if pdf.stat().st_size > 100 * 1024 * 1024:
        raise RuntimeError("Velký PDF (nad 100 MB) – EU DSS REST má limit 100 MB.")
    payload = {
        "signedDocument": {
            "bytes": base64.b64encode(pdf.read_bytes()).decode("ascii"),
            "digestAlgorithm": None,
            "name": pdf.name,
        },
        "originalDocuments": None, "policy": None,
    }
    req = urllib.request.Request(
        SERVICE_URL,
        data=json.dumps(payload, ensure_ascii=True).encode("utf-8"),
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    try:
        with PROXYLESS.open(req, timeout=240) as res:
            if res.status != 200:
                raise RuntimeError(f"EU DSS odpovědělo HTTP {res.status}.")
            raw = res.read(30 * 1024 * 1024 + 1)
            if len(raw) > 30 * 1024 * 1024:
                raise RuntimeError("EU DSS report překročil bezpečný limit 30 MB.")
            result = json.loads(raw.decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raise RuntimeError(
            f"EU DSS HTTP {exc.code}: " +
            exc.read(1500).decode("utf-8", errors="replace")
        ) from exc
    outcome = summarize_reports(result)
    # DiagnosticData may contain full certificates and sensitive metadata.
    # Do not automatically serialize megabytes of certificate material in TXT.
    report = {
        "engine": f"EU DSS {DSS_VERSION} (localhost)",
        "SimpleReport": result.get("SimpleReport"),
        "results": outcome,
    }
    outcome["report"] = json.dumps(report, ensure_ascii=False, indent=2)[:110_000]
    return outcome


def self_test():
    sample = {
        "SimpleReport": {
            "signatureOrTimestampOrEvidenceRecord": [{
                "Signature": {
                    "Indication": "TOTAL_PASSED",
                    "SignatureLevel": {"value": "QESig"},
                    "SignatureScope": [{"scope": "FULL"}],
                    "Timestamps": {"Timestamp": [{
                        "Indication": "PASSED",
                        "TimestampLevel": {"value": "QTSA"},
                    }]},
                }
            }]
        },
        "DiagnosticData": {
            "Signature": [{"BasicSignature": {
                "SignatureIntact": True, "SignatureValid": True}}]
        },
    }
    ok = summarize_reports(sample)
    assert (ok["signature"], ok["timestamp"], ok["crypto"]) == ("valid", "valid", "valid")
    no_ts = json.loads(json.dumps(sample))
    no_ts["SimpleReport"]["signatureOrTimestampOrEvidenceRecord"][0]["Signature"]["Timestamps"] = None
    assert summarize_reports(no_ts)["timestamp"] == "unverified"
    invalid = json.loads(json.dumps(sample))
    invalid["SimpleReport"]["signatureOrTimestampOrEvidenceRecord"][0]["Signature"]["Indication"] = "INDETERMINATE"
    assert summarize_reports(invalid)["signature"] == "unverified"
    bad_ts = json.loads(json.dumps(sample))
    bad_ts["SimpleReport"]["signatureOrTimestampOrEvidenceRecord"][0]["Signature"]["Timestamps"]["Timestamp"][0]["TimestampLevel"]["value"] = "TSA"
    assert summarize_reports(bad_ts)["timestamp"] == "unverified"
    print("EU DSS structured JSON tests passed")


if __name__ == "__main__":
    if len(__import__("sys").argv) == 2 and __import__("sys").argv[1] == "--self-test":
        self_test()
