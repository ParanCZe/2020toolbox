"""Offline end-to-end TEST B-LT: trust is explicit and never public."""
import io
import json
import unittest
import zipfile
from unittest.mock import patch
from asn1crypto import pem, x509
from pypdf import PdfWriter
from pyhanko.pdf_utils.reader import PdfFileReader
from pyhanko.sign.validation import validate_pdf_signature
from pyhanko.sign.validation.dss import DocumentSecurityStore
from pyhanko_certvalidator import ValidationContext
import authorization_bridge as bridge
import pdf_ltv


class CompleteTestLtTests(unittest.TestCase):
    def export(self):
        w = PdfWriter()
        w.add_blank_page(width=420, height=594)
        source = io.BytesIO()
        w.write(source)
        meta = {"profile": "lt", "test_mode": True, "tsa_test_mode": True,
                "tsa_url": "http://127.0.0.1:8094/test-tsa", "tsa_user": "TEST",
                "tsa_password": "TEST-ONLY", "documents": [{}]}
        with bridge.app.test_client() as client, patch.object(
                bridge, "WindowsStoreSigner", side_effect=AssertionError("Windows must not be used")), patch.object(
                bridge.timestamps, "HTTPTimeStamper", side_effect=AssertionError("No external TSA")):
            response = client.post("/sign-batch-test", headers={"Origin": "https://parancze.github.io",
                                   "X-20-20-Session": bridge._SESSION_TOKEN},
                                   data={"metadata": json.dumps(meta), "pdfs": (io.BytesIO(source.getvalue()), "test.pdf")},
                                   content_type="multipart/form-data")
        self.assertEqual(200, response.status_code)
        return response

    def test_test_lt_has_self_contained_evidence_and_one_timestamp(self):
        before = bridge._TEST_TSA_ISSUED
        response = self.export()
        self.assertEqual(1, bridge._TEST_TSA_ISSUED - before)
        self.assertEqual("0", response.headers["X-20-20-LT-Fallback"])
        with zipfile.ZipFile(io.BytesIO(response.data)) as z:
            manifest = json.loads(z.read("20-20_autorizace_manifest.json"))
            self.assertIn("PAdES B-LT", manifest["profile"])
            self.assertTrue(manifest["test_signer"])
            self.assertTrue(manifest["not_qualified_test_output"])
            self.assertEqual("unverified", manifest["qes_validation"])
            self.assertEqual("unverified", manifest["qtsa_validation"])
            self.assertNotIn("POZOR_PAdES_LT_NEPROVEDENO.txt", z.namelist())
            self.assertIn("TEST_NEPLATNE_PRO_URAD.txt", z.namelist())
            root_pem = z.read("TEST_ROOT_CA.pem")
            root = x509.Certificate.load(pem.unarmor(root_pem)[2])
            pdf = z.read(next(n for n in z.namelist() if n.endswith(".pdf")))
        evidence = pdf_ltv.inspect_lt_evidence(pdf)
        self.assertGreaterEqual(evidence["ocsp"], 3)
        self.assertGreaterEqual(evidence["crl"], 2)
        reader = PdfFileReader(io.BytesIO(pdf))
        dss = DocumentSecurityStore.read_dss(reader)
        context = dss.as_validation_context(dict(trust_roots=[root], allow_fetching=False, revocation_mode="hard-fail"))
        status = validate_pdf_signature(reader.embedded_signatures[0], signer_validation_context=context,
                                        ts_validation_context=context)
        self.assertTrue(status.intact)
        self.assertTrue(status.valid)
        self.assertTrue(status.trusted)
        self.assertTrue(status.timestamp_validity.intact)
        self.assertTrue(status.timestamp_validity.valid)
        self.assertTrue(status.timestamp_validity.trusted)
        self.assertFalse(status.docmdp_ok is False)
        # An embedded root is not public trust. Never install it in the OS.
        untrusted = dss.as_validation_context(dict(trust_roots=[], allow_fetching=False, revocation_mode="hard-fail"))
        public_status = validate_pdf_signature(reader.embedded_signatures[0], signer_validation_context=untrusted,
                                               ts_validation_context=untrusted)
        self.assertFalse(public_status.trusted)

    def test_expired_cache_refreshes_without_changing_inflight_snapshot(self):
        from dataclasses import replace
        from datetime import datetime, timedelta, timezone
        original = bridge._get_test_pki()
        expired = replace(original, refresh_after=datetime.now(timezone.utc) - timedelta(seconds=1))
        with patch.object(bridge, "_TEST_PKI", expired):
            renewed = bridge._get_test_pki()
            self.assertNotEqual(original.root.dump(), renewed.root.dump())
            meta = {"profile": "lt", "tsa_test_mode": True,
                    "tsa_url": "http://127.0.0.1:8094/test-tsa", "tsa_user": "TEST", "tsa_password": "TEST-ONLY"}
            self.assertIs(original.timestamper, bridge._build_timestamper(meta, test_pki=original))

    def test_concurrent_first_use_has_one_shared_pki(self):
        from concurrent.futures import ThreadPoolExecutor
        with patch.object(bridge, "_TEST_PKI", None):
            with ThreadPoolExecutor(max_workers=4) as pool:
                results = list(pool.map(lambda _: bridge._get_test_pki(), range(8)))
            self.assertTrue(all(value is results[0] for value in results))

    def test_missing_test_revocation_evidence_keeps_bt_fallback(self):
        pki = bridge._get_test_pki()
        empty = ValidationContext(trust_roots=[pki.root], other_certs=list(pki.issuers),
                                  ocsps=[], crls=[], allow_fetching=False, revocation_mode="hard-fail")
        before = bridge._TEST_TSA_ISSUED
        with patch.object(type(pki), "validation_context", return_value=empty):
            response = self.export()
        self.assertEqual(1, bridge._TEST_TSA_ISSUED - before)
        self.assertEqual("1", response.headers["X-20-20-LT-Fallback"])
        with zipfile.ZipFile(io.BytesIO(response.data)) as z:
            manifest = json.loads(z.read("20-20_autorizace_manifest.json"))
            self.assertIn("LT fallback", manifest["profile"])
            self.assertTrue(manifest["lt_fallback_warnings"])
            self.assertIn("POZOR_PAdES_LT_NEPROVEDENO.txt", z.namelist())


if __name__ == "__main__":
    unittest.main()
