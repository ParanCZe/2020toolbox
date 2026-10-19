"""PAdES LT opt-in safety tests without network, Windows keys or paid TSA."""
import asyncio
import io
import unittest
from unittest.mock import patch

from asn1crypto import cms
from pypdf import PdfWriter
from pyhanko.pdf_utils.reader import PdfFileReader

import authorization_bridge as bridge
import pdf_ltv


def blank_pdf():
    doc = PdfWriter()
    doc.add_blank_page(width=400, height=600)
    stream = io.BytesIO()
    doc.write(stream)
    return stream.getvalue()


class PostSignLtTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = blank_pdf()
        cls.signer = bridge._make_test_signer()

    def test_missing_revocation_data_fails_not_mislabeled_lt(self):
        stamp = bridge._get_test_tsa()
        before = bridge._TEST_TSA_ISSUED
        signed = bridge._sign_one(self.source, self.signer, {}, {}, stamp, None)
        self.assertEqual(1, bridge._TEST_TSA_ISSUED - before)
        with self.assertRaisesRegex(ValueError, "/DSS"):
            pdf_ltv.inspect_lt_evidence(signed)

    def test_ltv_does_not_request_another_timestamp(self):
        stamp = bridge._get_test_tsa()
        before = bridge._TEST_TSA_ISSUED
        signed = bridge._sign_one(self.source, self.signer, {}, {}, stamp, None)
        self.assertEqual(1, bridge._TEST_TSA_ISSUED - before)
        with patch.object(pdf_ltv, "async_add_validation_info", return_value=io.BytesIO(signed)) as add:
            with self.assertRaisesRegex(ValueError, "/DSS"):
                pdf_ltv.append_validated_dss(
                    signed, [], validation_context=object(),
                )
        self.assertEqual(1, bridge._TEST_TSA_ISSUED - before)
        self.assertEqual(1, add.call_count)
        self.assertIs(add.call_args.kwargs["skip_timestamp"], False)

    def test_signature_token_extraction_is_read_only(self):
        stamp = bridge._get_test_tsa()
        signed = bridge._sign_one(self.source, self.signer, {}, {}, stamp, None)
        signature = PdfFileReader(io.BytesIO(signed)).embedded_signatures[0]
        token = pdf_ltv._signature_timestamp_bytes(signature)
        self.assertGreater(len(token), 300)
        asn = cms.ContentInfo.load(token)
        self.assertEqual("signed_data", asn["content_type"].native)

    def test_dss_with_only_signer_ocsp_must_not_be_labeled_lt(self):
        with patch.object(pdf_ltv, "_target_certificates", return_value=(object(), object())), \
             patch.object(pdf_ltv, "_matching_good_ocsp", side_effect=[True, False]), \
             patch.object(pdf_ltv, "_matching_crl", return_value=False):
            with self.assertRaisesRegex(ValueError, "certifikát časové autority"):
                pdf_ltv._ensure_two_revocation_paths({}, object())

    def test_both_signer_and_tsa_evidence_are_required(self):
        with patch.object(pdf_ltv, "_target_certificates", return_value=(object(), object())), \
             patch.object(pdf_ltv, "_matching_good_ocsp", side_effect=[True, True]), \
             patch.object(pdf_ltv, "_matching_crl", return_value=False):
            self.assertIsNone(pdf_ltv._ensure_two_revocation_paths({}, object()))

    def test_plain_pades_b_b_cannot_be_upgraded_to_b_lt(self):
        signed = bridge._sign_one(self.source, self.signer, {}, {}, None, None)
        with self.assertRaisesRegex(ValueError, "RFC 3161"):
            pdf_ltv.inspect_lt_evidence(signed)

    def test_missing_ca_chain_rejected_before_ltv(self):
        with self.assertRaisesRegex(ValueError, "řetězec"):
            pdf_ltv.append_validated_dss(b"%PDF-1.7\n", [])


if __name__ == "__main__":
    unittest.main()
