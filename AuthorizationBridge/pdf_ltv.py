"""Post-sign PAdES B-LT augmentation for 20-20 AuthorizationBridge.

Never requests a TSA timestamp. Signing happens separately with the existing,
fixed-reservation B-T flow. This module appends *validation material only* as
a PDF incremental update and refuses to report LT if evidence is absent.

EU DSS independently decides trust and qualified QES/QTSA status.
"""
from __future__ import annotations

import asyncio
import hashlib
import io
from typing import Iterable
from datetime import datetime, timezone, timedelta

from asn1crypto import cms as asn1_cms, crl as asn1_crl, ocsp as asn1_ocsp, x509 as asn1_x509
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


def _signing_certificate(container: asn1_cms.ContentInfo) -> asn1_x509.Certificate:
    """Locate the actual CMS signer's certificate, never merely the first one."""
    signed = container["content"]
    infos = signed["signer_infos"]
    if len(infos) != 1 or infos[0]["sid"].name != "issuer_and_serial_number":
        raise ValueError("Nelze jednoznačně identifikovat podpisový certifikát CMS.")
    identifier = infos[0]["sid"].chosen
    for item in signed["certificates"]:
        if item.name != "certificate":
            continue
        cert = item.chosen
        if (cert.serial_number == identifier["serial_number"].native
                and cert.issuer == identifier["issuer"]):
            return cert
    raise ValueError("Certifikát podepisujícího není vložený v CMS.")


def _target_certificates(signature) -> tuple[asn1_x509.Certificate, asn1_x509.Certificate]:
    document_signer = _signing_certificate(
        asn1_cms.ContentInfo.load(signature.pkcs7_content)
    )
    timestamp_signer = _signing_certificate(
        asn1_cms.ContentInfo.load(_signature_timestamp_bytes(signature))
    )
    return document_signer, timestamp_signer


def _stream_bytes(ref) -> bytes:
    # pyHanko StreamObject has a decoded `.data` property, whereas pypdf's
    # StreamObject exposes `.get_data()`. We read with pyHanko here.
    stream = _deref(ref)
    decoder = getattr(stream, "get_data", None)
    if callable(decoder):
        return decoder()
    return stream.data


def _utc(value):
    if value is None:
        return None
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def _evidence_window_ok(this_update, next_update, *, at_time=None) -> bool:
    """Freshness only; does NOT validate responder signatures or trust."""
    now = _utc(at_time) if at_time is not None else datetime.now(timezone.utc)
    start, end = _utc(this_update), _utc(next_update)
    skew = timedelta(minutes=5)
    return bool(start is not None and end is not None
                and start <= now + skew and end >= now - skew and end > start)


def _matching_good_ocsp(dss, certificate: asn1_x509.Certificate) -> bool:
    for entry in _deref(dss.get("/OCSPs") or []):
        try:
            response = asn1_ocsp.OCSPResponse.load(_stream_bytes(entry))
            if response["response_status"].native != "successful":
                continue
            basic = response["response_bytes"]["response"].parsed
            for record in basic["tbs_response_data"]["responses"]:
                cert_id = record["cert_id"]
                if cert_id["serial_number"].native != certificate.serial_number:
                    continue
                algorithm = cert_id["hash_algorithm"]["algorithm"].native
                if algorithm not in {"sha1", "sha256", "sha384", "sha512"}:
                    continue
                expected = hashlib.new(algorithm, certificate.issuer.dump()).digest()
                if cert_id["issuer_name_hash"].native != expected:
                    continue
                if record["cert_status"].name != "good":
                    continue
                if not _evidence_window_ok(record["this_update"].native, record["next_update"].native):
                    continue
                return True
        except (ValueError, TypeError, KeyError, AttributeError):
            continue
    return False


def _matching_crl(dss, certificate: asn1_x509.Certificate) -> bool:
    for entry in _deref(dss.get("/CRLs") or []):
        try:
            report = asn1_crl.CertificateList.load(_stream_bytes(entry))
            body = report["tbs_cert_list"]
            if body["issuer"] != certificate.issuer:
                continue
            if not _evidence_window_ok(body["this_update"].native, body["next_update"].native):
                continue
            revoked = body["revoked_certificates"]
            if revoked.native is not None and any(
                item["user_certificate"].native == certificate.serial_number
                for item in revoked
            ):
                continue
            return True
        except (ValueError, TypeError, KeyError, AttributeError):
            continue
    return False


def _ensure_two_revocation_paths(dss, signature) -> None:
    """Structural fail-closed guard; qualification remains EU DSS's task.

    A valid-looking OCSP for only the signing key is NOT evidence for the TSA.
    Each cert's revocation status must have matching evidence in the DSS.
    pyHanko's hard-fail validation context must still validate that evidence.
    """
    for label, cert in zip(
        ("podpisový certifikát", "certifikát časové autority"),
        _target_certificates(signature),
    ):
        if not (_matching_good_ocsp(dss, cert) or _matching_crl(dss, cert)):
            raise ValueError(
                "PDF /DSS nemá odpovídající OCSP/CRL pro " + label +
                ". Údaje nelze vydávat za dokončené PAdES B-LT."
            )


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
    _ensure_two_revocation_paths(dss, sig)
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
            # Caller-supplied issuers are evidence, never trusted anchors.
            other_certs=[asn1_x509.Certificate.load(cert) for cert in issuer_der],
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
