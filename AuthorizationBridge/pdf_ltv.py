"""Post-sign PAdES B-LT augmentation for 20-20 AuthorizationBridge.

Never requests a TSA timestamp. Signing happens separately with the existing,
fixed-reservation B-T flow. This module appends *validation material only* as
a PDF incremental update and refuses to report LT if evidence is absent.

EU DSS independently decides trust and qualified QES/QTSA status.
"""
from __future__ import annotations

import asyncio
import io
from typing import Iterable

from asn1crypto import x509 as asn1_x509
from pyhanko.pdf_utils.reader import PdfFileReader
from pyhanko.sign.validation.dss import async_add_validation_info
from pyhanko_certvalidator import ValidationContext


def _deref(obj):
    return obj.get_object() if hasattr(obj, "get_object") else obj


def _array_count(dictionary, key):
    data = _deref(dictionary.get(key))
    return len(data) if data is not None else 0


def _signature_timestamp_bytes(embedded_sig) -> bytes:
    from asn1crypto import cms
    signed = cms.ContentInfo.load(embedded_sig.pkcs7_content)["content"]
    for info in signed["signer_infos"]:
        attrs = info["unsigned_attrs"]
        if attrs is None or attrs.native is None:
            continue
        for attr in attrs:
            if attr["type"].dotted == "1.2.840.113549.1.9.16.2.14":
                return attr["values"][0].dump()
    raise ValueError("Podpis neobsahuje časové razítko RFC 3161 (PAdES B-T).")


def inspect_lt_evidence(pdf_bytes: bytes) -> dict:
    reader = PdfFileReader(io.BytesIO(pdf_bytes), strict=True)
    signatures = reader.embedded_signatures
    if len(signatures) != 1:
        raise ValueError("PAdES-LT vyžaduje jediný podpis v dokumentu.")
    sig = signatures[0]
    coverage = sig.evaluate_signature_coverage().name
    if coverage not in {"ENTIRE_FILE", "ENTIRE_REVISION"}:
        raise ValueError("Elektronický podpis nepokrývá původní podepsanou revizi PDF.")
    sig_timestamp = _signature_timestamp_bytes(sig)
    dss = _deref(reader.root.get("/DSS"))
    if dss is None:
        raise ValueError("Ve výsledném PDF není slovník /DSS.")
    count = {key: _array_count(dss, name) for key, name in (
        ("certificates", "/Certs"), ("ocsp", "/OCSPs"), ("crl", "/CRLs")
    )}
    if not count["ocsp"] and not count["crl"]:
        raise ValueError("V /DSS chybějí OCSP/CRL odpovědi.")
    return {**count, "coverage": coverage, "signature_timestamp": sig_timestamp}


def append_validated_dss(
    signed_pdf: bytes, public_issuer_der: Iterable[bytes], *,
    validation_context: ValidationContext | None = None
) -> bytes:
    """Append DSS without timestamping, then verify unchanged CMS/time token.

    On failure the caller must NOT silently label the result PAdES B-LT.
    The issuer root is a collection/validation hint; not proof of QTSP status.
    """
    issuer_der = tuple(public_issuer_der)
    if validation_context is None:
        if not issuer_der:
            raise ValueError("Pro PAdES B-LT chybí řetězec vydávající CA.")
        validation_context = ValidationContext(
            extra_trust_roots=[asn1_x509.Certificate.load(issuer_der[-1])],
            other_certs=[asn1_x509.Certificate.load(cert) for cert in issuer_der[:-1]],
            allow_fetching=True,
            revocation_mode="hard-fail",
        )
    original = PdfFileReader(io.BytesIO(signed_pdf), strict=True).embedded_signatures
    if len(original) != 1:
        raise ValueError("PAdES B-LT očekává jediný původní podpis.")
    original_cms = original[0].pkcs7_content
    original_tst = _signature_timestamp_bytes(original[0])

    async def _append():
        embedded = PdfFileReader(io.BytesIO(signed_pdf), strict=True).embedded_signatures[0]
        return await async_add_validation_info(
            embedded,
            validation_context=validation_context,
            skip_timestamp=False,
            add_vri_entry=True,
        )

    output = asyncio.run(_append())
    if not hasattr(output, "getvalue"):
        output.seek(0)
        result = output.read()
    else:
        result = output.getvalue()
    if not result.startswith(signed_pdf):
        raise ValueError("Inkrementální DSS revize změnila původní podpisová data.")
    validated = inspect_lt_evidence(result)
    updated = PdfFileReader(io.BytesIO(result), strict=True).embedded_signatures[0]
    if updated.pkcs7_content != original_cms:
        raise ValueError("Přidání /DSS změnilo podepsaný CMS obsah.")
    if validated["signature_timestamp"] != original_tst:
        raise ValueError("Přidání /DSS změnilo původní časové razítko.")
    return result
