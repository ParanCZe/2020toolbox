"""Regression tests: TEST signer + local RFC3161 TSA; no paid requests."""
import io
import json
import unittest
import zipfile

from pypdf import PdfWriter
from pyhanko.pdf_utils.reader import PdfFileReader

import authorization_bridge as bridge


def blank_pdf():
    writer = PdfWriter()
    writer.add_blank_page(width=400, height=600)
    output = io.BytesIO()
    writer.write(output)
    return output.getvalue()


class LocalTestModesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pdf_bytes = blank_pdf()

    def test_local_lt_opt_in_is_explicit(self):
        good = {
            "profile": "lt",
            "tsa_url": "http://127.0.0.1:8094/test-tsa",
            "tsa_test_mode": True,
            "tsa_user": "TEST",
            "tsa_password": "TEST-ONLY",
        }
        self.assertTrue(bridge._is_local_test_lt(good))
        self.assertIs(bridge._build_timestamper(good), bridge._get_test_tsa())
        for bad in (
            {**good, "tsa_test_mode": False},
            {**good, "tsa_url": "http://localhost:8094/test-tsa"},
            {**good, "profile": "bt"},
        ):
            self.assertFalse(bridge._is_local_test_lt(bad))

    def _request(self, profile, test_tsa=True):
        meta = {
            "profile": profile,
            "test_mode": True,
            "tsa_test_mode": test_tsa,
            "tsa_url": "http://127.0.0.1:8094/test-tsa" if test_tsa else "",
            "tsa_user": "TEST" if test_tsa else "",
            "tsa_password": "TEST-ONLY" if test_tsa else "",
            "documents": [{"name": "demo.pdf", "output_name": "demo_EAR.pdf"}],
            "append_ear": True,
            "output_standard": "PDF/A-3b",
            "reason": "TEST",
        }
        origin = "https://parancze.github.io"
        with bridge.app.test_client() as client:
            auth = client.get("/session", headers={"Origin": origin})
            self.assertEqual(200, auth.status_code)
            token = auth.get_json()["token"]
            response = client.post(
                "/sign-batch-test",
                data={
                    "metadata": json.dumps(meta),
                    "pdfs": (io.BytesIO(self.pdf_bytes), "demo.pdf"),
                },
                headers={
                    "Origin": origin,
                    "X-20-20-Session": token,
                },
                content_type="multipart/form-data",
            )
            return response

    def test_local_test_signer_with_one_tsa_timestamp(self):
        start = bridge._TEST_TSA_ISSUED
        response = self._request("bt")
        self.assertEqual(200, response.status_code, response.get_data(as_text=False)[:600].decode('utf-8', 'replace'))
        self.assertEqual(1, bridge._TEST_TSA_ISSUED - start)
        with zipfile.ZipFile(io.BytesIO(response.data)) as package:
            manifest = json.loads(package.read("20-20_autorizace_manifest.json"))
            self.assertTrue(manifest["not_qualified_test_output"])
            self.assertTrue(manifest["tsa_test_mode"])
            self.assertIn("TEST_NEPLATNE_PRO_URAD.txt", package.namelist())
            signature = PdfFileReader(io.BytesIO(package.read("demo_EAR.pdf"))).embedded_signatures[0]
            self.assertEqual("ENTIRE_FILE", signature.evaluate_signature_coverage().name)

    def test_test_lt_never_lies_when_revocation_material_is_missing(self):
        start = bridge._TEST_TSA_ISSUED
        response = self._request("lt")
        self.assertEqual(200, response.status_code, response.get_data(as_text=False)[:600].decode('utf-8', 'replace'))
        self.assertEqual(1, bridge._TEST_TSA_ISSUED - start)
        with zipfile.ZipFile(io.BytesIO(response.data)) as package:
            manifest = json.loads(package.read("20-20_autorizace_manifest.json"))
            self.assertTrue(manifest["not_qualified_test_output"])
            self.assertTrue(manifest["lt_fallback_warnings"])
            self.assertIn("LT fallback", manifest["profile"])
            self.assertIn("POZOR_PAdES_LT_NEPROVEDENO.txt", package.namelist())
            self.assertEqual("1", response.headers["X-20-20-LT-Fallback"])

    def test_production_lt_cannot_use_localhost_without_explicit_test(self):
        self.assertFalse(
            bridge._is_local_test_lt({
                "profile": "lt",
                "tsa_url": "http://127.0.0.1:8094/test-tsa",
                "tsa_test_mode": False,
            })
        )


if __name__ == "__main__":
    unittest.main()
