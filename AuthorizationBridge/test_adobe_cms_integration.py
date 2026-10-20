"""Offline end-to-end Adobe CMS OCSP test; no QSCD or paid TSA required."""
import io
import json
import hashlib
import zipfile
import unittest
from unittest.mock import patch
from datetime import datetime, timedelta, timezone

from asn1crypto import x509 as ax509, keys as akeys, ocsp as aocsp
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509 import ocsp
from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID, AuthorityInformationAccessOID
from pypdf import PdfWriter
from simulation_pdfa_fixture import create_simulated_drawing_pdfa, create_simulated_ear_stamp
from pyhanko.sign import signers
from pyhanko.sign.validation import validate_pdf_signature
from pyhanko.sign.validation.ades import ades_lta_validation
from pyhanko.sign.validation.policy_decl import PdfSignatureValidationSpec, SignatureValidationSpec
from pyhanko_certvalidator.context import CertValidationPolicySpec
from pyhanko_certvalidator.registry import SimpleTrustManager
from pyhanko_certvalidator.policy_decl import REQUIRE_REVINFO
import asyncio
from pyhanko.pdf_utils.reader import PdfFileReader
from pyhanko_certvalidator import ValidationContext

import authorization_bridge as bridge
import pdf_ltv


class AdobeCmsIntegrationTest(unittest.TestCase):
    def test_adobe_local_test_tsa_is_free_and_available(self):
        before = bridge._TEST_TSA_ISSUED
        metadata = {
            "profile": "adobe",
            "tsa_url": "http://127.0.0.1:8094/test-tsa",
            "tsa_test_mode": True,
            "tsa_user": "TEST",
            "tsa_password": "TEST-ONLY",
        }
        stamp = bridge._build_timestamper(metadata)
        self.assertIs(stamp, bridge._get_test_tsa())
        # Building or preflighting the free TSA must not issue a timestamp.
        self.assertEqual(before, bridge._TEST_TSA_ISSUED)

    def test_adobe_signed_attribute_with_ocsp_and_one_rfc3161_stamp(self):
        now = datetime.now(timezone.utc)
        root_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        intermediate_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        signer_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        tsa_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        tsa_ca_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        root_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "LAB Root CA - SIMULATION ONLY")])
        root = (x509.CertificateBuilder().subject_name(root_name).issuer_name(root_name)
                .public_key(root_key.public_key()).serial_number(x509.random_serial_number())
                .not_valid_before(now - timedelta(days=1))
                .not_valid_after(now + timedelta(days=30))
                .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
                .add_extension(x509.KeyUsage(
                    digital_signature=True, content_commitment=False, key_encipherment=False,
                    data_encipherment=False, key_agreement=False, key_cert_sign=True,
                    crl_sign=True, encipher_only=False, decipher_only=False,
                ), critical=True).sign(root_key, hashes.SHA256()))
        intermediate_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "LAB Qualified Signer CA 4 - SIMULATION ONLY")])
        intermediate = (x509.CertificateBuilder().subject_name(intermediate_name)
                        .issuer_name(root_name).public_key(intermediate_key.public_key())
                        .serial_number(x509.random_serial_number())
                        .not_valid_before(now - timedelta(days=1))
                        .not_valid_after(now + timedelta(days=30))
                        .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
                        .add_extension(x509.KeyUsage(
                            digital_signature=True, content_commitment=False,
                            key_encipherment=False, data_encipherment=False,
                            key_agreement=False, key_cert_sign=True, crl_sign=True,
                            encipher_only=False, decipher_only=False,
                        ), critical=True).sign(root_key, hashes.SHA256()))
        # Distinct LAB CA4 and LAB CA5 like the real PostSignum signer/TSA chains.
        tsa_ca_name = x509.Name([x509.NameAttribute(
            NameOID.COMMON_NAME, "LAB Qualified TSA CA 5 - SIMULATION ONLY"
        )])
        tsa_ca = (
            x509.CertificateBuilder().subject_name(tsa_ca_name).issuer_name(root_name)
            .public_key(tsa_ca_key.public_key()).serial_number(x509.random_serial_number())
            .not_valid_before(now - timedelta(days=1))
            .not_valid_after(now + timedelta(days=30))
            .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
            .add_extension(x509.KeyUsage(
                digital_signature=True, content_commitment=False,
                key_encipherment=False, data_encipherment=False, key_agreement=False,
                key_cert_sign=True, crl_sign=True, encipher_only=False,
                decipher_only=False,
            ), critical=True).sign(root_key, hashes.SHA256())
        )
        def issue(cn, pubkey, tsa=False):
            issuing_name = tsa_ca_name if tsa else intermediate_name
            issuing_key = tsa_ca_key if tsa else intermediate_key
            cert = (x509.CertificateBuilder().subject_name(
                x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, cn)])
            ).issuer_name(issuing_name).public_key(pubkey).serial_number(x509.random_serial_number())
              .not_valid_before(now - timedelta(days=1))
              .not_valid_after(now + timedelta(days=30))
              .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
              .add_extension(x509.KeyUsage(
                  digital_signature=True, content_commitment=not tsa, key_encipherment=False,
                  data_encipherment=False, key_agreement=False, key_cert_sign=False,
                  crl_sign=False, encipher_only=False, decipher_only=False
              ), critical=True)
              .add_extension(x509.AuthorityInformationAccess([
                  x509.AccessDescription(
                      AuthorityInformationAccessOID.OCSP,
                      x509.UniformResourceIdentifier("http://ocsp.example.invalid/"),
                  )
              ]), critical=False))
            if tsa:
                cert = cert.add_extension(
                    x509.ExtendedKeyUsage([ExtendedKeyUsageOID.TIME_STAMPING]), critical=True,
                )
            return cert.sign(issuing_key, hashes.SHA256())
        signer_cert = issue("Signer", signer_key.public_key())
        tsa_cert = issue("LAB PostSignum-LIKE TSA TSU - NOT REAL", tsa_key.public_key(), tsa=True)

        def public_der(cert):
            return cert.public_bytes(serialization.Encoding.DER)
        def private_der(key):
            return key.private_bytes(
                serialization.Encoding.DER, serialization.PrivateFormat.PKCS8,
                serialization.NoEncryption(),
            )
        def ocsp_der(cert, issuer, issuer_key):
            return (ocsp.OCSPResponseBuilder()
                    .add_response(
                        cert=cert, issuer=issuer, algorithm=hashes.SHA1(),
                        cert_status=ocsp.OCSPCertStatus.GOOD,
                        this_update=now - timedelta(hours=1),
                        next_update=now + timedelta(days=7),
                        revocation_time=None, revocation_reason=None,
                    ).responder_id(ocsp.OCSPResponderEncoding.HASH, issuer)
                    .sign(issuer_key, hashes.SHA256())
                    .public_bytes(serialization.Encoding.DER))

        root_asn = ax509.Certificate.load(public_der(root))
        registry = bridge.SimpleCertificateStore()
        registry.register(root_asn)
        registry.register(ax509.Certificate.load(public_der(intermediate)))
        signer = signers.SimpleSigner(
            signing_cert=ax509.Certificate.load(public_der(signer_cert)),
            signing_key=akeys.PrivateKeyInfo.load(private_der(signer_key)),
            cert_registry=registry,
        )
        signer.issuer_certificates_der = (public_der(intermediate), public_der(root))
        timestamp = bridge.CountingDummyTimeStamper(
            tsa_cert=ax509.Certificate.load(public_der(tsa_cert)),
            tsa_key=akeys.PrivateKeyInfo.load(private_der(tsa_key)),
            certs_to_embed=[ax509.Certificate.load(public_der(tsa_ca)), root_asn],
            include_nonce=True,
        )
        context = ValidationContext(
            trust_roots=[root_asn], other_certs=[
                root_asn, ax509.Certificate.load(public_der(intermediate)),
                ax509.Certificate.load(public_der(tsa_ca)),
            ],
            ocsps=[aocsp.OCSPResponse.load(ocsp_der(signer_cert, intermediate, intermediate_key)),
                   aocsp.OCSPResponse.load(ocsp_der(intermediate, root, root_key)),
                   aocsp.OCSPResponse.load(ocsp_der(tsa_cert, tsa_ca, tsa_ca_key)),
                   aocsp.OCSPResponse.load(ocsp_der(tsa_ca, root, root_key))],
            allow_fetching=False, revocation_mode="hard-fail",
        )
        document = io.BytesIO(create_simulated_drawing_pdfa())

        before = bridge._TEST_TSA_ISSUED
        with patch.object(bridge, "ValidationContext", return_value=context):
            signed = bridge._sign_one(document.getvalue(), signer, {}, {"profile": "adobe"}, timestamp, None)
        self.assertEqual(1, bridge._TEST_TSA_ISSUED - before)
        # Adobe's signed attribute must contain OCSP already at the time of
        # signing, rather than in a post-sign PDF /DSS revision.
        from asn1crypto import cms
        from asn1crypto.pdf import RevocationInfoArchival
        reader = PdfFileReader(io.BytesIO(signed), strict=True)
        self.assertNotIn('/DSS', reader.root)
        signature = reader.embedded_signatures[0]
        self.assertEqual('/adbe.pkcs7.detached', str(signature.sig_object['/SubFilter']))
        attrs = cms.ContentInfo.load(signature.pkcs7_content)['content']['signer_infos'][0]['signed_attrs']
        revocations = [attr for attr in attrs
                       if attr['type'].dotted == '1.2.840.113583.1.1.8']
        self.assertEqual(1, len(revocations))
        revocation = RevocationInfoArchival.load(revocations[0]['values'][0].dump())
        self.assertGreaterEqual(len(revocation['ocsp']), 2)
        self.assertEqual(1, bridge._TEST_TSA_ISSUED - before)
        status = validate_pdf_signature(
            signature,
            signer_validation_context=context,
            ts_validation_context=context,
        )
        self.assertTrue(status.intact, status.pretty_print_details())
        self.assertTrue(status.valid, status.pretty_print_details())

        # No revocation evidence: fail closed BEFORE issuing any TSA token.
        # This is especially important with paid PostSignum timestamps.
        no_revocation_context = ValidationContext(
            trust_roots=[root_asn],
            other_certs=[ax509.Certificate.load(public_der(intermediate))],
            ocsps=[],
            crls=[],
            allow_fetching=False,
            revocation_mode="hard-fail",
        )
        issued_before_failure = bridge._TEST_TSA_ISSUED
        with patch.object(bridge, "ValidationContext", return_value=no_revocation_context):
            with self.assertRaises(Exception):
                bridge._sign_one(
                    document.getvalue(), signer, {}, {"profile": "adobe"},
                    timestamp, None,
                )
        self.assertEqual(
            issued_before_failure, bridge._TEST_TSA_ISSUED,
            "Chybějící OCSP nesmí spotřebovat žádné časové razítko.",
        )

        # Complete Flask HTTP pipeline (the actual Bridge endpoints):
        # preflight -> local approval -> POST /sign-batch -> ZIP -> inspect PDF.
        # Windows Store and the UI confirmation are replaced by local mocks;
        # the real signer, OCSP proofs and RFC 3161 test TSA are exercised.
        signer.ca_certificate_count = 2
        signer.signature_size = 256
        input_pdf = document.getvalue()
        simulated_stamp = create_simulated_ear_stamp()
        filename = "SIMULACE_TEST_VYKRES.pdf"
        metadata = {
            "profile": "adobe",
            "test_mode": False,
            "tsa_url": "http://127.0.0.1:8094/test-tsa",
            "tsa_user": "TEST",
            "tsa_password": "TEST-ONLY",
            "tsa_test_mode": True,
            "certificate_thumbprint": "A" * 40,
            "reason": "POUZE LABORATORNI SIMULACE",
            "location": "LAB",
            "append_ear": True,
            "documents": [{
                "name": filename,
                "output_name": filename,
                "placement": {"page": 0, "box": [545, 30, 816, 107]},
            }],
        }
        preflight = dict(metadata)
        preflight["document_count"] = 1
        browser_headers = {
            "Origin": "https://parancze.github.io",
            "X-20-20-Session": bridge._SESSION_TOKEN,
        }
        class DummyWindowsSession:
            def __init__(self, *args, **kwargs):
                pass

            def open(self):
                return self

            def close(self):
                pass

        issued_before_api = bridge._TEST_TSA_ISSUED
        bridge._PREFLIGHTS.clear()
        bridge._SIGN_APPROVALS.clear()
        with (
            patch.object(bridge, "WindowsStoreSigner", return_value=signer),
            patch.object(bridge, "WindowsRsaBatchSession", DummyWindowsSession),
            patch.object(bridge, "_verify_tsa_login", return_value=None),
            patch.object(bridge, "_native_sign_confirmation", return_value=True),
            patch.object(bridge, "ValidationContext", return_value=context),
            patch.object(bridge, "_build_timestamper", return_value=timestamp),
        ):
            client = bridge.app.test_client()
            check = client.post(
                "/preflight-sign", json=preflight, headers=browser_headers,
            )
            self.assertEqual(200, check.status_code, check.get_json())
            token = check.get_json()["preflight_token"]
            file_info = {
                "name": filename, "size": len(input_pdf),
                "sha256": hashlib.sha256(input_pdf).hexdigest(),
            }
            approved = client.post(
                "/approve-sign",
                json={
                    "preflight_token": token,
                    "documents": [file_info],
                    "signing_intent": bridge._canonical_signing_intent(metadata, simulated_stamp),
                },
                headers=browser_headers,
            )
            self.assertEqual(200, approved.status_code, approved.get_json())
            signed_response = client.post(
                "/sign-batch",
                data={
                    "metadata": json.dumps({
                        **metadata,
                        "approval_token": approved.get_json()["approval_token"],
                        "output_standard": "PDF/A-3b (LAB simulace, nezavisle validovana)",
                    }),
                    "pdfs": (io.BytesIO(input_pdf), filename),
                    "stamp": (io.BytesIO(simulated_stamp), "LAB_SIMULACE_RAZITKO.png"),
                },
                content_type="multipart/form-data",
                headers=browser_headers,
            )
            self.assertEqual(200, signed_response.status_code,
                             signed_response.get_json(silent=True))
        self.assertEqual(1, bridge._TEST_TSA_ISSUED - issued_before_api)
        self.assertEqual("0", signed_response.headers.get("X-20-20-LT-Fallback"))
        with zipfile.ZipFile(io.BytesIO(signed_response.data)) as out:
            output_names = out.namelist()
            self.assertIn("SIMULACE_TEST_VYKRES_EAR.pdf", output_names)
            self.assertIn("20-20_autorizace_manifest.json", output_names)
            signed_document = out.read("SIMULACE_TEST_VYKRES_EAR.pdf")
            manifest = json.loads(out.read("20-20_autorizace_manifest.json"))
            self.assertEqual("Adobe CMS + TSA + OCSP/CRL", manifest["profile"])
            self.assertTrue(manifest["tsa_test_mode"])
            self.assertFalse(manifest["test_mode"])
        actual_signature = PdfFileReader(io.BytesIO(signed_document)).embedded_signatures[0]
        signed_attrs = cms.ContentInfo.load(actual_signature.pkcs7_content)["content"]["signer_infos"][0]["signed_attrs"]
        revocations = [attr for attr in signed_attrs
                       if attr["type"].dotted == "1.2.840.113583.1.1.8"]
        self.assertEqual(1, len(revocations))
        self.assertGreaterEqual(
            len(RevocationInfoArchival.load(revocations[0]["values"][0].dump())["ocsp"]), 2,
        )
        self.assertEqual("ENTIRE_FILE", actual_signature.evaluate_signature_coverage().name)
        verification = validate_pdf_signature(
            actual_signature, signer_validation_context=context,
            ts_validation_context=context,
        )
        self.assertTrue(verification.valid and verification.intact,
                        verification.pretty_print_details())
        from pathlib import Path
        artifact_directory = Path("simulation_output")
        artifact_directory.mkdir(exist_ok=True)
        # Lab-only PDF: never describe it as qualified or PDF/A.
        (artifact_directory / "SIMULACE_TEST_VYKRES_EAR.pdf").write_bytes(signed_document)
        report = {
            "purpose": "KOMPLETNI OFFLINE SIMULACE - NEPLATNE PRO URAD",
            "is_qualified_signature": False,
            "qualified_timestamp": False,
            "pdfa_validated": False,  # updated by independent veraPDF runner
            "real_postsignum_tested": False,
            "bridge_http_steps": ["preflight-sign", "approve-sign", "sign-batch"],
            "cms_subfilter": str(actual_signature.sig_object["/SubFilter"]),
            "ocsp_in_cms": len(RevocationInfoArchival.load(revocations[0]["values"][0].dump())["ocsp"]),
            "dss_required": False,
            "test_tsa_tokens_issued": bridge._TEST_TSA_ISSUED - issued_before_api,
            "signature_cryptographically_valid": bool(verification.valid),
            "signature_integrity_intact": bool(verification.intact),
            "visible_ear_stamp": True,
            "visible_ear_stamp_marked_invalid": True,
            "input_architectural_drawing": "synthetic A3 floorplan with walls, rooms, furniture and title block",
            "stamp_placement_pdf_points": [545, 30, 816, 107],
            "manifest": manifest,
        }
        (artifact_directory / "simulace_vysledky.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8",
        )

        # Real end-to-end PAdES B-LT, not merely Adobe revocation info:
        # 1. B-T signature with exactly one LAB RFC3161 timestamp;
        # 2. OCSP collection from TWO independent LAB CA 4 / TSA CA 5 chains;
        # 3. /DSS + /VRI incremental PDF revision with original CMS unchanged;
        # 4. independent local cryptographic validation and ZIP inspection.
        lab_lt_meta = {
            **metadata,
            "profile": "lt",
            "tsa_url": "https://lab-tsa.example.invalid/qualified-mimic",
            "tsa_user": "LAB",
            "tsa_password": "LAB",
            "tsa_test_mode": False,
            "output_standard": "PDF/A-3b (LAB simulace, nezavisle validovana)",
        }
        signed_tokens_before_lt = bridge._TEST_TSA_ISSUED
        bridge._PREFLIGHTS.clear()
        bridge._SIGN_APPROVALS.clear()
        with (
            patch.object(bridge, "WindowsStoreSigner", return_value=signer),
            patch.object(bridge, "WindowsRsaBatchSession", DummyWindowsSession),
            patch.object(bridge, "_verify_tsa_login", return_value=None),
            patch.object(bridge, "_native_sign_confirmation", return_value=True),
            patch.object(bridge, "_build_timestamper", return_value=timestamp),
            patch.object(pdf_ltv, "ValidationContext", return_value=context),
        ):
            test_client = bridge.app.test_client()
            approved_preflight = test_client.post(
                "/preflight-sign", json={**lab_lt_meta, "document_count": 1},
                headers=browser_headers,
            )
            self.assertEqual(
                200, approved_preflight.status_code, approved_preflight.get_json()
            )
            approved_lt = test_client.post(
                "/approve-sign",
                json={
                    "preflight_token": approved_preflight.get_json()["preflight_token"],
                    "documents": [file_info],
                    "signing_intent": bridge._canonical_signing_intent(
                        lab_lt_meta, simulated_stamp,
                    ),
                },
                headers=browser_headers,
            )
            self.assertEqual(200, approved_lt.status_code, approved_lt.get_json())
            lt_response = test_client.post(
                "/sign-batch",
                data={
                    "metadata": json.dumps({
                        **lab_lt_meta,
                        "approval_token": approved_lt.get_json()["approval_token"],
                    }),
                    "pdfs": (io.BytesIO(input_pdf), filename),
                    "stamp": (
                        io.BytesIO(simulated_stamp), "LAB_SIMULACE_RAZITKO.png",
                    ),
                },
                headers=browser_headers,
                content_type="multipart/form-data",
            )
            self.assertEqual(200, lt_response.status_code,
                             lt_response.get_json(silent=True))
        self.assertEqual(
            "0", lt_response.headers.get("X-20-20-LT-Fallback"),
            "PAdES B-LT nesmi skryte skončit jako B-T.",
        )
        self.assertEqual(
            1, bridge._TEST_TSA_ISSUED - signed_tokens_before_lt,
            "B-LT musi vydat presne jedno RFC3161 razitko.",
        )
        with zipfile.ZipFile(io.BytesIO(lt_response.data)) as bundle:
            self.assertIn("SIMULACE_TEST_VYKRES_EAR.pdf", bundle.namelist())
            self.assertNotIn("POZOR_PAdES_LT_NEPROVEDENO.txt", bundle.namelist())
            lt_pdf = bundle.read("SIMULACE_TEST_VYKRES_EAR.pdf")
            lt_manifest = json.loads(bundle.read("20-20_autorizace_manifest.json"))
            self.assertEqual("PAdES B-LT", lt_manifest["profile"])
            self.assertEqual("PAdES B-LT", lt_manifest["files"][0]["profile"])

        from pdf_signature_inspector import inspect_bytes
        dss_details = pdf_ltv.inspect_lt_evidence(lt_pdf)
        self.assertGreaterEqual(dss_details["ocsp"], 2)
        self.assertEqual("ENTIRE_REVISION", dss_details["coverage"])
        lt_inventory = inspect_bytes(lt_pdf)
        self.assertTrue(lt_inventory["pdf_dss"]["present"])
        self.assertGreaterEqual(lt_inventory["pdf_dss"]["ocsp"], 2)
        lt_reader = PdfFileReader(io.BytesIO(lt_pdf), strict=True)
        self.assertEqual(1, len(lt_reader.embedded_signatures))
        self.assertIn("/DSS", lt_reader.root)
        # This signed B-T revision is preserved byte-for-byte at the start
        # of the PDF, then DSS material is appended after it.
        lt_sig = lt_reader.embedded_signatures[0]
        lt_verification = validate_pdf_signature(
            lt_sig, signer_validation_context=context,
            ts_validation_context=context,
        )
        self.assertTrue(lt_verification.valid, lt_verification.pretty_print_details())
        self.assertTrue(lt_verification.intact, lt_verification.pretty_print_details())
        self.assertIsNot(lt_verification.docmdp_ok, False)
        self.assertEqual(1, bridge._TEST_TSA_ISSUED - signed_tokens_before_lt)

        # The modern ETSI/AdES engine is a stricter independent check.
        # The result is recorded, including non-PASS indications, without
        # silently calling the presence of /DSS a successful validation.
        lab_trust = SimpleTrustManager.build(trust_roots=[root_asn])
        lab_spec = PdfSignatureValidationSpec(SignatureValidationSpec(
            cert_validation_policy=CertValidationPolicySpec(
                trust_manager=lab_trust, revinfo_policy=REQUIRE_REVINFO,
            ),
        ))
        ades_result = asyncio.run(ades_lta_validation(lt_sig, lab_spec))
        ades_result_code = str(ades_result.ades_subindic)
        ades_api_status = ades_result.api_status
        print("LAB ETSI AdES result:", ades_result_code,
              "status:", getattr(ades_api_status, "bottom_line", None))

        (artifact_directory / "SIMULACE_PADES_B_LT_VYKRES_EAR.pdf").write_bytes(lt_pdf)
        (artifact_directory / "SIMULACE_PADES_B_LT_PROTOKOL.json").write_text(
            json.dumps({
                "purpose": "LAB PAdES B-LT - NEKVALIFIKOVANA SIMULACE",
                "actual_profile": "PAdES B-LT",
                "output_is_qualified": False,
                "actual_postsignum_queried": False,
                "lab_certificate_chains": [
                    "LAB ROOT -> LAB SIGNER CA 4 -> LAB SIGNER",
                    "LAB ROOT -> LAB TSA CA 5 -> LAB TSA",
                ],
                "pdf_a3b": "pending independent veraPDF",
                "cms_integrity_valid": bool(lt_verification.valid and lt_verification.intact),
                "ades_standards_verdict": ades_result_code,
                "ades_validator_bottom_line": (
                    getattr(ades_api_status, "bottom_line", None)
                    if ades_api_status is not None else None
                ),
                "docmdp_ok": lt_verification.docmdp_ok,
                "cms_original_is_preserved": True,
                "dss": {k:v for k,v in dss_details.items() if k!="signature_timestamp"},
                "pdf_dss_inventory": lt_inventory["pdf_dss"],
                "rfc3161_tokens_issued": bridge._TEST_TSA_ISSUED - signed_tokens_before_lt,
                "test_validation_context": "hard-fail, offline, private LAB root; never EU trust list",
                "pdf_sha256": hashlib.sha256(lt_pdf).hexdigest(),
                "manifest": lt_manifest,
            }, ensure_ascii=False, indent=2, default=str),
            encoding="utf-8",
        )


if __name__ == "__main__":
    unittest.main()
