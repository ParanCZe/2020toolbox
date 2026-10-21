"""Regression: TEST TSA metadata must survive local Windows approval unchanged.

Runs fully offline using a disposable in-memory signer in place of Windows.
The approval token and full intent digest are still verified by real routes.
"""
import hashlib
import io
import json
import secrets
import unittest
from datetime import datetime, timezone
from unittest.mock import patch
from zipfile import ZipFile

from pypdf import PdfWriter

import authorization_bridge as bridge


def blank_pdf():
    pdf = PdfWriter()
    pdf.add_blank_page(width=420, height=594)
    file = io.BytesIO()
    pdf.write(file)
    return file.getvalue()


class FakeWindowsSession:
    def __init__(self, *args, **kwargs):
        pass

    def open(self):
        return self

    def close(self):
        pass


class LocalApprovalIntentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pdf = blank_pdf()

    def _post(self, changed_reason=None, changed_location=None):
        approval_token = secrets.token_urlsafe(20)
        meta = {
            "profile": "bt",
            "test_mode": False,
            "tsa_test_mode": True,
            "tsa_url": "http://127.0.0.1:8094/test-tsa",
            "tsa_user": "TEST",
            "tsa_password": "TEST-ONLY",
            "certificate_thumbprint": "A" * 40,
            "approval_token": approval_token,
            "reason": "TEST – Autorizace dokumentace",
            "location": "Praha",
            "contact": "",
            "append_ear": False,
            "documents": [{
                "name": "test.pdf",
                "output_name": "test.pdf",
                "placement": None,
            }],
        }
        originally_approved = bridge._canonical_signing_intent(meta, b"")
        bridge._SIGN_APPROVALS[approval_token] = {
            "context": bridge._approval_context(meta, 1),
            "documents": [{
                "name": "test.pdf", "size": len(self.pdf),
                "sha256": hashlib.sha256(self.pdf).hexdigest(),
            }],
            "intent_digest": bridge._intent_digest(originally_approved),
            "expires": datetime.now(timezone.utc).timestamp() + 60,
            "used": False,
        }

        if changed_reason is not None:
            meta["reason"] = changed_reason
        if changed_location is not None:
            meta["location"] = changed_location

        signer = bridge._make_test_signer()
        signer.signature_size = 256
        signer.ca_certificate_count = 0
        signer.issuer_certificates_der = ()

        try:
            with patch.object(bridge, "WindowsStoreSigner", return_value=signer), \
                 patch.object(bridge, "WindowsRsaBatchSession", FakeWindowsSession):
                with bridge.app.test_client() as client:
                    response = client.post(
                        "/sign-batch",
                        data={
                            "metadata": json.dumps(meta),
                            "pdfs": (io.BytesIO(self.pdf), "test.pdf"),
                        },
                        headers={
                            "Origin": "https://parancze.github.io",
                            "X-20-20-Session": bridge._SESSION_TOKEN,
                        },
                        content_type="multipart/form-data",
                    )
            return response
        finally:
            bridge._SIGN_APPROVALS.pop(approval_token, None)

    def test_demo_windows_signer_with_local_tsa_matches_approved_intent(self):
        before = bridge._TEST_TSA_ISSUED
        response = self._post()
        self.assertEqual(200, response.status_code, response.get_data(as_text=False)[:1000].decode("utf-8", "replace"))
        self.assertEqual(1, bridge._TEST_TSA_ISSUED - before)
        with ZipFile(io.BytesIO(response.data)) as files:
            manifest = json.loads(files.read("20-20_autorizace_manifest.json"))
            self.assertTrue(manifest["tsa_test_mode"])
            self.assertIn("test.pdf", files.namelist())

    def test_missing_test_prefix_rejected_as_modified_reason(self):
        before = bridge._TEST_TSA_ISSUED
        response = self._post(changed_reason="Autorizace dokumentace")
        self.assertEqual(403, response.status_code)
        self.assertIn("metadata nebo grafika", response.get_json()["error"])
        self.assertEqual(before, bridge._TEST_TSA_ISSUED)

    def test_location_changed_after_approval_remains_rejected(self):
        response = self._post(changed_location="Brno")
        self.assertEqual(403, response.status_code)
        self.assertIn("metadata nebo grafika", response.get_json()["error"])


if __name__ == "__main__":
    unittest.main()
