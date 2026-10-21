"""Real synthetic PKI tests; no production keys or paid TSA requests."""
import io
import unittest
from asn1crypto import cms
from pypdf import PdfReader
from pyhanko.pdf_utils.reader import PdfFileReader
from pyhanko.sign.validation import validate_pdf_signature
from pyhanko_certvalidator import ValidationContext
import authorization_bridge as bridge
from signing_test_utils import signing_fixture


class AdobeExportTests(unittest.TestCase):
    def test_adobe_export_embeds_verified_revocation_and_one_timestamp(self):
        signer, tsa, context, source = signing_fixture()
        before = bridge._TEST_TSA_ISSUED
        signed = bridge._sign_one(source, signer, {}, {"profile": "adobe"}, tsa, None,
                                  validation_context=context)
        self.assertEqual(1, bridge._TEST_TSA_ISSUED - before)
        sig = PdfFileReader(io.BytesIO(signed)).embedded_signatures[0]
        self.assertEqual("/adbe.pkcs7.detached", str(sig.sig_object["/SubFilter"]))
        self.assertEqual("ENTIRE_FILE", sig.evaluate_signature_coverage().name)
        self.assertEqual(2, sig.sig_object["/Reference"][0]["/TransformParams"]["/P"])
        info = cms.ContentInfo.load(sig.pkcs7_content)["content"]["signer_infos"][0]
        attrs = {a["type"].native: a["values"][0] for a in info["signed_attrs"]}
        self.assertGreaterEqual(len(attrs["adobe_revocation_info_archival"]["ocsp"]), 1)
        self.assertEqual(1, sum(a["type"].native == "signature_time_stamp_token" for a in info["unsigned_attrs"]))
        self.assertNotIn("/DSS", PdfFileReader(io.BytesIO(signed)).root)
        status = validate_pdf_signature(sig, signer_validation_context=context, ts_validation_context=context)
        self.assertTrue(status.intact)
        self.assertTrue(status.valid)
        self.assertTrue(status.trusted)

    def test_missing_revocation_fails_before_timestamp(self):
        signer, tsa, context, source = signing_fixture()
        empty = ValidationContext(trust_roots=list(signer.cert_registry),
                                  allow_fetching=False, ocsps=[], crls=[], revocation_mode="hard-fail")
        before = bridge._TEST_TSA_ISSUED
        with self.assertRaises(Exception):
            bridge._sign_one(source, signer, {}, {"profile": "adobe"}, tsa, None,
                             validation_context=empty)
        self.assertEqual(before, bridge._TEST_TSA_ISSUED)

    def test_revoked_signer_rejected_without_consuming_timestamp(self):
        signer, tsa, context, source = signing_fixture(revoked_signer=True)
        before = bridge._TEST_TSA_ISSUED
        with self.assertRaises(Exception):
            bridge._sign_one(source, signer, {}, {"profile": "adobe"}, tsa, None,
                             validation_context=context)
        self.assertEqual(before, bridge._TEST_TSA_ISSUED)

    def test_missing_issuer_chain_rejected_without_consuming_timestamp(self):
        signer, tsa, context, source = signing_fixture()
        before = bridge._TEST_TSA_ISSUED
        with self.assertRaisesRegex(ValueError, "řetězec"):
            bridge._sign_one(source, signer, {}, {"profile": "adobe"}, tsa, None)
        self.assertEqual(before, bridge._TEST_TSA_ISSUED)

    def test_adobe_requires_timestamp(self):
        signer, tsa, context, source = signing_fixture()
        with self.assertRaises(ValueError):
            bridge._sign_one(source, signer, {}, {"profile": "adobe"}, None, None,
                             validation_context=context)

    def test_validation_does_not_treat_declared_pdfa_as_verified(self):
        from unittest.mock import patch
        with patch("pdf_validator_engine.VERAPDF", ()):
            result = bridge._export_validation(b"%PDF-1.7\n")
        self.assertEqual("unverified", result["pdfa"])
        self.assertEqual("unverified", result["signature"])
        self.assertEqual("unverified", result["timestamp"])

    def test_export_manifest_preserves_unknown_validation_and_test_qualification(self):
        import json
        import zipfile
        from unittest.mock import patch
        signer, tsa, context, source = signing_fixture()
        with bridge.app.test_client() as client, patch("pdf_validator_engine.VERAPDF", ()):
            response = client.post("/sign-batch-test", headers={
                "Origin": "https://parancze.github.io", "X-20-20-Session": bridge._SESSION_TOKEN,
            }, data={"metadata": json.dumps({"profile": "bb", "documents": [{}]}),
                     "pdfs": (io.BytesIO(source), "drawing.pdf")}, content_type="multipart/form-data")
        self.assertEqual(200, response.status_code)
        self.assertEqual("unverified", response.headers["X-20-20-Validation"])
        self.assertIn("X-20-20-Validation", response.headers["Access-Control-Expose-Headers"])
        archive = zipfile.ZipFile(io.BytesIO(response.data))
        manifest = json.loads(archive.read("20-20_autorizace_manifest.json"))
        self.assertEqual("unverified", manifest["pdfa_validation"])
        self.assertEqual("unverified", manifest["qes_validation"])
        self.assertTrue(any(n.endswith(".validation.json") for n in archive.namelist()))

    def test_slow_optional_validation_preserves_signed_timestamped_zip(self):
        import json
        import subprocess
        import sys
        import zipfile
        from pathlib import Path
        from unittest.mock import patch
        signer, tsa, context, source = signing_fixture()
        before = bridge._TEST_TSA_ISSUED
        metadata = {"profile": "bt", "documents": [{}], "tsa_test_mode": True,
                    "tsa_url": "http://127.0.0.1:8094/test-tsa", "tsa_user": "TEST", "tsa_password": "TEST-ONLY"}
        with bridge.app.test_client() as client, patch("pdf_validator_engine.VERAPDF", (Path(sys.executable),)), patch(
                "authorization_bridge.subprocess.Popen") as runner, patch("authorization_bridge.os.killpg"):
            runner.return_value.wait.side_effect = [subprocess.TimeoutExpired("veraPDF", 10), 0]
            runner.return_value.poll.return_value = 0
            response = client.post("/sign-batch-test", headers={
                "Origin": "https://parancze.github.io", "X-20-20-Session": bridge._SESSION_TOKEN,
            }, data={"metadata": json.dumps(metadata), "pdfs": (io.BytesIO(source), "drawing.pdf")},
                                   content_type="multipart/form-data")
        self.assertEqual(200, response.status_code)
        self.assertEqual(1, bridge._TEST_TSA_ISSUED - before)
        self.assertLessEqual(runner.return_value.wait.call_args_list[0].kwargs["timeout"], 10)
        self.assertFalse(Path(runner.call_args.args[0][-1]).exists())
        archive = zipfile.ZipFile(io.BytesIO(response.data))
        pdf = archive.read(next(n for n in archive.namelist() if n.endswith(".pdf")))
        self.assertEqual(1, len(PdfFileReader(io.BytesIO(pdf)).embedded_signatures))
        self.assertEqual("unverified", response.headers["X-20-20-Validation"])

    @unittest.skipIf(__import__("os").name == "nt", "POSIX worker fixture; Windows tree uses taskkill")
    def test_real_slow_validator_is_bounded_without_pipe_deadlock(self):
        import tempfile
        import time
        from pathlib import Path
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as directory:
            worker = Path(directory) / "verapdf"
            worker.write_text("#!/usr/bin/env python3\nimport time\ntime.sleep(60)\n")
            worker.chmod(0o700)
            started = time.monotonic()
            with patch("pdf_validator_engine.VERAPDF", (worker,)):
                result = bridge._export_validation(b"%PDF-1.7\n", timeout=0.1)
            self.assertLess(time.monotonic() - started, 2)
            self.assertEqual("unverified", result["pdfa"])

    def test_validation_aggregation_never_hides_failure(self):
        self.assertEqual("unverified", bridge._combined_validation([]))
        self.assertEqual("invalid", bridge._combined_validation([
            {"pdfa": "invalid", "signature": "valid", "timestamp": "unverified"}]))
        self.assertEqual("valid", bridge._combined_validation([
            {"pdfa": "valid", "signature": "valid", "timestamp": "valid"}]))

    def test_visible_text_uses_embedded_font(self):
        signer, tsa, context, source = signing_fixture()
        signed = bridge._sign_one(source, signer, {"placement": {"page": 0, "box": [10,10,300,100]}}, {}, None, None)
        widget = PdfReader(io.BytesIO(signed)).pages[0]["/Annots"][0].get_object()
        resources = widget["/AP"]["/N"]["/Resources"]
        fonts = resources["/Font"]
        self.assertTrue(fonts)
        for ref in fonts.values():
            font = ref.get_object()
            if "/DescendantFonts" in font:
                font = font["/DescendantFonts"][0].get_object()
            descriptor = font["/FontDescriptor"]
            self.assertTrue(any(k in descriptor for k in ("/FontFile", "/FontFile2", "/FontFile3")))

if __name__ == "__main__":
    unittest.main()
