"""Read-only inventory of PAdES/CMS evidence embedded in a PDF.

Presence of certificates, OCSP/CRL or an RFC3161 token is NOT evidence that
the certificate, revocation response or timestamp is trusted or valid.
EU DSS performs qualified validation separately.

No network requests and no signing/private-key operations take place here.
"""
from __future__ import annotations

import io
from pathlib import Path
from typing import Any

from asn1crypto import cms
from pyhanko.pdf_utils.reader import PdfFileReader

_RFC3161_SIGNATURE_TIMESTAMP = "1.2.840.113549.1.9.16.2.14"
_ADOBE_REVOCATION_INFO = "1.2.840.113583.1.1.8"
_ETSI_REVOCATION_VALUES = "1.2.840.113549.1.9.16.2.24"


def _dereference(value: Any):
    if value is not None and hasattr(value, "get_object"):
        return value.get_object()
    return value


def _pdf_array_count(dictionary: Any, key: str) -> int:
    if dictionary is None:
        return 0
    obj = _dereference(dictionary.get(key))
    if obj is None:
        return 0
    return len(obj) if isinstance(obj, (list, tuple)) else 0


def _attributes(signer_info: cms.SignerInfo):
    oids = []
    for key in ("signed_attrs", "unsigned_attrs"):
        attrs = signer_info[key]
        if attrs is None or getattr(attrs, "native", None) is None:
            continue
        try:
            for entry in attrs:
                oids.append(entry["type"].dotted)
        except (TypeError, ValueError, KeyError):
            continue
    return oids


def inspect_bytes(pdf: bytes) -> dict:
    """Record presence and coverage only. Never return a validity verdict."""
    result = {
        "status": "unverified",
        "signatures": [],
        "pdf_dss": {"present": False, "certificates": 0, "ocsp": 0, "crl": 0},
        "messages": [],
    }
    try:
        reader = PdfFileReader(io.BytesIO(pdf), strict=False)
        dss = _dereference(reader.root.get("/DSS"))
        if dss is not None:
            result["pdf_dss"] = {
                "present": True,
                "certificates": _pdf_array_count(dss, "/Certs"),
                "ocsp": _pdf_array_count(dss, "/OCSPs"),
                "crl": _pdf_array_count(dss, "/CRLs"),
            }

        for sig in reader.embedded_signatures:
            details = {
                "field": str(sig.field_name or ""),
                "subfilter": "",
                "covers_whole_file": None,
                "certificates_in_cms": 0,
                "timestamp_tokens_in_cms": 0,
                "revocation_values_in_cms": False,
                "cms_readable": False,
            }
            try:
                sig_obj = _dereference(sig.sig_object)
                if sig_obj is not None:
                    filt = _dereference(sig_obj.get("/SubFilter"))
                    details["subfilter"] = str(filt or "").lstrip("/")
                coverage = sig.evaluate_signature_coverage()
                details["covers_whole_file"] = (
                    getattr(coverage, "name", "") == "ENTIRE_FILE"
                )
                parsed = cms.ContentInfo.load(sig.pkcs7_content)
                if parsed["content_type"].native != "signed_data":
                    raise ValueError("CMS neobsahuje SignedData.")
                signed_data = parsed["content"]
                cert_set = signed_data["certificates"]
                if cert_set is not None and getattr(cert_set, "native", None) is not None:
                    details["certificates_in_cms"] = sum(
                        1 for cert in cert_set if cert.name == "certificate"
                    )
                for signer_info in signed_data["signer_infos"]:
                    attr_oids = _attributes(signer_info)
                    details["timestamp_tokens_in_cms"] += attr_oids.count(
                        _RFC3161_SIGNATURE_TIMESTAMP
                    )
                    if any(oid in attr_oids for oid in (
                        _ADOBE_REVOCATION_INFO, _ETSI_REVOCATION_VALUES,
                    )):
                        details["revocation_values_in_cms"] = True
                details["cms_readable"] = True
            except Exception as exc:
                result["messages"].append(
                    "Podpisové pole " + (details["field"] or "(bez názvu)") +
                    " nelze úplně technicky zkontrolovat: " + str(exc)[:220]
                )
            result["signatures"].append(details)
        result["status"] = "inspected"
    except Exception as exc:
        result["messages"].append(
            "Technický obsah PDF se nepodařilo načíst: " + str(exc)[:300]
        )
    return result


def inspect_file(pdf: Path) -> dict:
    return inspect_bytes(pdf.read_bytes())


def compare_evidence(result: dict) -> dict:
    """Compare independent evidence without promoting presence to validity."""
    structure = result.get("structure") or {}
    if structure.get("status") != "inspected":
        return {"status": "unverified", "messages": [
            "Technická struktura nebyla přečtena. Nejde o důkaz neplatnosti."
        ]}
    signatures = structure.get("signatures") or []
    notes = []
    contradictions = []
    if result.get("crypto") == "valid" and not signatures:
        contradictions.append(
            "EU DSS potvrdilo kryptografii, ale lokální parser nenašel podpis."
        )
    if result.get("signature") == "valid" and result.get("crypto") == "invalid":
        contradictions.append(
            "EU DSS hlásí kvalifikovaný podpis, ale kryptografie je neplatná."
        )
    if result.get("crypto") == "valid" and isinstance(result.get("signatures"), int):
        if len(signatures) != result["signatures"]:
            contradictions.append(
                "EU DSS a lokální parser uvádějí odlišný počet podpisů."
            )
    if not signatures:
        notes.append("Soubor neobsahuje běžné elektronické podpisové pole.")
    if signatures and any(s.get("cms_readable") is False for s in signatures):
        notes.append("U některých podpisů nelze přečíst kompletní CMS údaje.")
    if signatures and any(s.get("covers_whole_file") is False for s in signatures):
        notes.append(
            "Alespoň jeden podpis nepokrývá konečný soubor. Může jít o další revizi PDF; "
            "ověř historii změn v EU DSS."
        )
    if signatures and any(
        s.get("cms_readable") and s.get("certificates_in_cms", 0) < 2
        for s in signatures
    ):
        notes.append(
            "V CMS některého podpisu nejsou další certifikáty CA. "
            "Externí validátor je může potřebovat získat samostatně."
        )
    dss = structure.get("pdf_dss") or {}
    has_pdf_revocation = dss.get("ocsp", 0) > 0 or dss.get("crl", 0) > 0
    has_cms_revocation = any(
        s.get("revocation_values_in_cms") for s in signatures
    )
    if signatures and not has_pdf_revocation and not has_cms_revocation:
        notes.append(
            "V PDF nebyly nalezeny přibalené OCSP/CRL podklady; "
            "EU DSS je může získat online. Absence nedokazuje neplatnost."
        )
    if result.get("signature") == "unverified":
        notes.append("Kvalifikovaný status podpisu nebyl potvrzen EU DSS.")
    if result.get("pdfa") == "unverified":
        notes.append("Soulad s PDF/A-3b není nezávisle potvrzen veraPDF.")
    if result.get("crypto") == "unverified" and signatures:
        notes.append("Kryptografická integrita nebyla ověřena EU DSS.")
    if result.get("timestamp") == "unverified" and any(
        s.get("timestamp_tokens_in_cms") for s in signatures
    ):
        notes.append("Razítko je vložené, ale EU DSS nepotvrdilo jeho kvalifikovanou platnost.")

    return {
        "status": "conflict" if contradictions else "warning" if notes else "consistent",
        "messages": contradictions + notes,
    }
