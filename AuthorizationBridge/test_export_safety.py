"""Regression tests for paid-token safety and verified-only archival data."""
import io
import json
import unittest
import zipfile
from unittest.mock import patch
from pyhanko_certvalidator import ValidationContext
from pyhanko.pdf_utils.reader import PdfFileReader
import authorization_bridge as bridge
from signing_test_utils import signing_fixture


class ExportSafetyTests(unittest.TestCase):
    def post(self, pdfs, **settings):
        meta = dict(profile="bt", test_mode=True, tsa_test_mode=True,
                    tsa_url="http://127.0.0.1:8094/test-tsa", tsa_user="TEST", tsa_password="TEST-ONLY",
                    documents=[{} for _ in pdfs])
        meta.update(settings)
        with bridge.app.test_client() as client:
            return client.post("/sign-batch-test", headers={
                "Origin": "https://parancze.github.io", "X-20-20-Session": bridge._SESSION_TOKEN,
            }, data={"metadata": json.dumps(meta),
                     "pdfs": [(io.BytesIO(data), f"drawing{i}.pdf") for i, data in enumerate(pdfs)]},
                               content_type="multipart/form-data")

    def test_test_signer_cannot_construct_production_tsa_transport(self):
        _, _, _, source = signing_fixture()
        with patch.object(bridge.timestamps, "HTTPTimeStamper", return_value=bridge._get_test_tsa()) as remote:
            response = self.post([source], tsa_test_mode=False, tsa_url="https://tsa.example.invalid/")
        self.assertEqual(400, response.status_code)
        self.assertFalse(remote.called)

    def test_endpoint_mode_cannot_be_disabled_by_request_metadata(self):
        _, _, _, source = signing_fixture()
        with patch.object(bridge.timestamps, "HTTPTimeStamper", return_value=bridge._get_test_tsa()) as remote:
            response = self.post([source], test_mode=False, tsa_test_mode=False, tsa_url="https://tsa.example.invalid/")
        self.assertEqual(400, response.status_code)
        self.assertFalse(remote.called)

    def test_invalid_later_placement_rejected_before_any_timestamp(self):
        _, _, _, source = signing_fixture()
        before = bridge._TEST_TSA_ISSUED
        response = self.post([source, source], documents=[{}, {"placement": {"page": 99, "box": [10, 10, 100, 100]}}])
        self.assertEqual(400, response.status_code)
        self.assertEqual(before, bridge._TEST_TSA_ISSUED)

    def test_invalid_later_pdf_rejected_before_any_timestamp(self):
        _, _, _, source = signing_fixture()
        before = bridge._TEST_TSA_ISSUED
        response = self.post([source, b"%PDF-broken\n"])
        self.assertEqual(400, response.status_code)
        self.assertEqual(before, bridge._TEST_TSA_ISSUED)

    def test_late_tsa_failure_returns_completed_pdf_and_stops_batch(self):
        _, _, _, source = signing_fixture()
        local = bridge._get_test_tsa()
        class FailingTSA:
            calls = 0
            async def async_timestamp(self, *args, **kwargs):
                self.calls += 1
                if self.calls == 2:
                    raise RuntimeError("simulated TSA outage")
                return await local.async_timestamp(*args, **kwargs)
        tsa = FailingTSA()
        before = bridge._TEST_TSA_ISSUED
        with patch.object(bridge, "_build_timestamper", return_value=tsa):
            response = self.post([source, source, source])
        self.assertEqual(200, response.status_code)
        self.assertEqual("partial", response.headers.get("X-20-20-Batch-Result"))
        self.assertEqual("1", response.headers.get("X-20-20-Completed-Count"))
        self.assertEqual(2, tsa.calls)
        self.assertEqual(1, bridge._TEST_TSA_ISSUED - before)
        with zipfile.ZipFile(io.BytesIO(response.data)) as archive:
            pdfs = [n for n in archive.namelist() if n.endswith(".pdf")]
            self.assertEqual(1, len(pdfs))
            signed = archive.read(pdfs[0])
            self.assertEqual("ENTIRE_FILE", PdfFileReader(io.BytesIO(signed)).embedded_signatures[0].evaluate_signature_coverage().name)
            manifest = json.loads(archive.read("20-20_autorizace_manifest.json"))
            self.assertEqual("partial", manifest["batch_status"])
            self.assertEqual(1, len(manifest["failed_files"]))
            self.assertEqual(1, len(manifest["unprocessed_files"]))
            self.assertIn("POZOR_DAVKA_NEDOKONCENA.txt", archive.namelist())

    def test_crl_fallback_excludes_rejected_ocsp(self):
        signer, tsa, context, source = signing_fixture(with_crl=True)
        forged = context.ocsps[0].copy()
        basic = forged["response_bytes"]["response"].parsed
        signature = bytearray(basic["signature"].native)
        signature[-1] ^= 1
        basic["signature"] = bytes(signature)
        forged["response_bytes"]["response"] = basic
        context = ValidationContext(trust_roots=list(signer.cert_registry),
                                    ocsps=[forged], crls=context.crls,
                                    allow_fetching=False, revocation_mode="hard-fail")
        result = bridge._adobe_revocation_info(signer, context)
        self.assertFalse(result["ocsp"].native)
        self.assertEqual(1, len(result["crl"]))

    def test_corrupted_ocsp_candidate_is_not_embedded(self):
        signer, tsa, context, source = signing_fixture()
        forged = context.ocsps[0].copy()
        basic = forged["response_bytes"]["response"].parsed
        signature = bytearray(basic["signature"].native)
        signature[-1] ^= 1
        basic["signature"] = bytes(signature)
        forged["response_bytes"]["response"] = basic
        context = ValidationContext(trust_roots=list(signer.cert_registry),
                                    ocsps=list(context.ocsps) + [forged],
                                    allow_fetching=False, revocation_mode="hard-fail")
        result = bridge._adobe_revocation_info(signer, context)
        embedded = [entry.dump() for entry in result["ocsp"]]
        self.assertTrue(embedded)
        self.assertNotIn(forged.dump(), embedded)
        # TSA evidence is not part of the signer's Adobe archival attribute.
        self.assertNotIn(context.ocsps[1].dump(), embedded)


if __name__ == "__main__":
    unittest.main()
