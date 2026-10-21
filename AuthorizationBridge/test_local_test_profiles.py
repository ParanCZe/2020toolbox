"""Offline regression tests for TEST signer + local RFC 3161 TSA.

Only uses disposable keys, loopback in-process Flask calls and one-page PDFs.
Never contacts a qualified TSA, certificate store, or network service.
"""
import io
import json
import unittest
import zipfile

from pypdf import PdfWriter
from pyhanko.pdf_utils.reader import PdfFileReader
from asn1crypto import cms

import authorization_bridge as bridge


def blank_pdf():
    writer = PdfWriter()
    writer.add_blank_page(width=420, height=594)
    out = io.BytesIO()
    writer.write(out)
    return out.getvalue()


class LocalTestProfiles(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pdf = blank_pdf()
        cls.client = bridge.app.test_client()

    def sign(self, profile):
        meta = {
            "profile": profile,
            "test_mode": True,
            "tsa_url": "http://127.0.0.1:8094/test-tsa",
            "tsa_user": "TEST",
            "tsa_password": "TEST-ONLY",
            "tsa_test_mode": True,
            "append_ear": True,
            "documents": [{"name": "input.pdf", "output_name": "input_EAR.pdf"}],
        }
        response = self.client.post(
            "/sign-batch-test",
            headers={
                "Origin": "https://parancze.github.io",
                "X-20-20-Session": bridge._SESSION_TOKEN,
            },
            data={
                "metadata": json.dumps(meta),
                "pdfs": (io.BytesIO(self.pdf), "input_EAR.pdf"),
            },
            content_type="multipart/form-data",
        )
        self.assertEqual(200, response.status_code, response.get_data(as_text=False)[:1500].decode('utf-8', 'replace'))
        with zipfile.ZipFile(io.BytesIO(response.data)) as archive:
            names = archive.namelist()
            manifest = json.loads(archive.read("20-20_autorizace_manifest.json"))
            signed = archive.read("input_EAR.pdf")
            warning = ("POZOR_PAdES_LT_NEPROVEDENO.txt" in names)
            self.assertIn("TEST_NEPLATNE_PRO_URAD.txt", names)
        return response, manifest, signed, warning

    def test_test_signer_and_local_timestamp_generate_one_token(self):
        before = bridge._TEST_TSA_ISSUED
        response, manifest, signed, warning = self.sign("bt")
        self.assertEqual(1, bridge._TEST_TSA_ISSUED - before)
        self.assertFalse(warning)
        self.assertTrue(manifest["test_mode"])
        self.assertTrue(manifest["test_signer"])
        self.assertTrue(manifest["not_qualified_test_output"])
        self.assertIn("B-T", manifest["profile"])
        reader = PdfFileReader(io.BytesIO(signed))
        self.assertEqual(1, len(reader.embedded_signatures))
        token = cms.ContentInfo.load(reader.embedded_signatures[0].pkcs7_content)
        attrs = token["content"]["signer_infos"][0]["unsigned_attrs"]
        self.assertIn("signature_time_stamp_token", [attr["type"].native for attr in attrs])

    def test_complete_local_lt_embeds_evidence_without_qualification(self):
        before = bridge._TEST_TSA_ISSUED
        response, manifest, signed, warning = self.sign("lt")
        self.assertEqual(1, bridge._TEST_TSA_ISSUED - before)
        self.assertEqual("0", response.headers["X-20-20-LT-Fallback"])
        self.assertFalse(warning)
        self.assertIn("PAdES B-LT", manifest["profile"])
        self.assertNotEqual("PAdES B-LT", manifest["profile"])
        self.assertFalse(manifest["lt_fallback_warnings"])
        reader = PdfFileReader(io.BytesIO(signed))
        self.assertEqual(1, len(reader.embedded_signatures))

    def test_explicit_test_mode_is_required_for_local_lt(self):
        base = {
            "profile": "lt", "tsa_test_mode": True,
            "tsa_url": "http://127.0.0.1:8094/test-tsa",
        }
        self.assertTrue(bridge._is_local_test_lt(base))
        self.assertFalse(bridge._is_local_test_lt({**base, "tsa_test_mode": False}))
        self.assertFalse(bridge._is_local_test_lt({**base, "tsa_url": "https://www3.postsignum.cz/TSS/TSS_user/"}))
        self.assertFalse(bridge._is_local_test_lt({**base, "profile": "bt"}))


if __name__ == "__main__":
    unittest.main()
