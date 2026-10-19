"""Real PDF signing smoke tests using only local, disposable TEST credentials.

Never uses Windows private keys, the user's certificate, or paid timestamps.
"""
import io
import unittest

from pypdf import PdfWriter
from pyhanko.pdf_utils.reader import PdfFileReader
from asn1crypto import cms

import authorization_bridge as bridge


def _source_pdf():
    writer = PdfWriter()
    writer.add_blank_page(width=450, height=600)
    stream = io.BytesIO()
    writer.write(stream)
    return stream.getvalue()


class SignatureRoundtripTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = _source_pdf()
        cls.signer = bridge._make_test_signer()

    def _assert_single_full_signature(self, signed_bytes):
        reader = PdfFileReader(io.BytesIO(signed_bytes))
        signatures = reader.embedded_signatures
        self.assertEqual(1, len(signatures))
        self.assertEqual(
            "ENTIRE_FILE", signatures[0].evaluate_signature_coverage().name
        )
        self.assertEqual(
            "signed_data", cms.ContentInfo.load(signatures[0].pkcs7_content)["content_type"].native
        )

    def test_baseline_without_timestamp(self):
        signed = bridge._sign_one(
            self.source, self.signer, {}, {"reason": "test"}, None, None
        )
        self._assert_single_full_signature(signed)

    def test_baseline_with_one_local_test_timestamp(self):
        before = bridge._TEST_TSA_ISSUED
        stamp = bridge._get_test_tsa()
        signed = bridge._sign_one(
            self.source, self.signer, {}, {"reason": "test"}, stamp, None
        )
        self._assert_single_full_signature(signed)
        self.assertEqual(1, bridge._TEST_TSA_ISSUED - before)
        reader = PdfFileReader(io.BytesIO(signed))
        signature_cms = cms.ContentInfo.load(reader.embedded_signatures[0].pkcs7_content)
        self.assertIn(
            "signature_time_stamp_token",
            [entry["type"].native for entry in
             signature_cms["content"]["signer_infos"][0]["unsigned_attrs"]],
        )


if __name__ == "__main__":
    unittest.main()
