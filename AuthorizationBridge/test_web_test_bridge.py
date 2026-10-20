"""Security and offline PDF signing smoke tests for the hosted TEST bridge."""
import io
import os
import unittest
from unittest.mock import patch
from pypdf import PdfWriter
from pyhanko.pdf_utils.reader import PdfFileReader


class WebTestBridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.env = patch.dict(os.environ, {
            "TOOLBOX_WEB_ORIGIN": "https://example.test",
            "TOOLBOX_WEB_TEST_TOKEN": "T" * 48,
        })
        cls.env.start()
        from web_test_bridge import create_app
        cls.app = create_app()
        cls.app.testing = True
        cls.client = cls.app.test_client()

    @classmethod
    def tearDownClass(cls):
        cls.env.stop()

    def auth(self):
        return {"Authorization": "Bearer " + "T" * 48,
                "Origin": "https://example.test"}

    def pdf(self):
        output = io.BytesIO()
        doc = PdfWriter()
        doc.add_blank_page(width=400, height=500)
        doc.write(output)
        return output.getvalue()

    def test_no_auth_is_denied(self):
        result = self.client.post("/api/test-sign", data={})
        self.assertEqual(403, result.status_code)

    def test_cross_origin_is_denied(self):
        response = self.client.post("/api/test-sign", headers={
            **self.auth(), "Origin": "https://evil.example"})
        self.assertEqual(403, response.status_code)

    def test_invalid_upload_rejected(self):
        response = self.client.post("/api/test-sign",
            headers=self.auth(), data={"pdf": (io.BytesIO(b"invalid"), "a.pdf")})
        self.assertEqual(400, response.status_code)

    def test_successful_ephemeral_pdf_signature(self):
        response = self.client.post("/api/test-sign", headers=self.auth(),
            data={"pdf": (io.BytesIO(self.pdf()), "test.pdf")})
        self.assertEqual(200, response.status_code, response.get_json(silent=True))
        self.assertEqual("SELF-SIGNED-TEST-NOT-QUALIFIED",
                         response.headers["X-Toolbox-Signature"])
        self.assertEqual(1, len(PdfFileReader(io.BytesIO(response.data)).embedded_signatures))
        self.assertEqual("no-store", response.headers["Cache-Control"])


if __name__ == "__main__":
    unittest.main()
