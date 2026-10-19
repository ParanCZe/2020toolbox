"""Smoke tests for read-only PDF evidence inventory. No paid TSA/network."""
import io
import unittest

from pypdf import PdfWriter
from asn1crypto import x509 as asn1_x509, keys as asn1_keys
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID
from datetime import datetime, timedelta, timezone

import authorization_bridge as bridge
import pdf_signature_inspector as inspector
from pyhanko.sign.signers import SimpleSigner


def make_pdf():
    writer = PdfWriter()
    writer.add_blank_page(width=350, height=600)
    stream = io.BytesIO()
    writer.write(stream)
    return stream.getvalue()


def make_cert(common, issuer_cert, issuer_key, key, ca=False):
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common)])
    issuer = issuer_cert.subject if issuer_cert is not None else subject
    now = datetime.now(timezone.utc)
    return x509.CertificateBuilder().subject_name(subject).issuer_name(issuer).public_key(
        key.public_key()
    ).serial_number(x509.random_serial_number()).not_valid_before(
        now - timedelta(days=1)
    ).not_valid_after(now + timedelta(days=90)).add_extension(
        x509.BasicConstraints(ca=ca, path_length=None), critical=True
    ).sign(issuer_key, hashes.SHA256())


class PdfSignatureInspectorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pdf = make_pdf()
        cls.signer = bridge._make_test_signer()

    def test_unsigned_pdf(self):
        result = inspector.inspect_bytes(self.pdf)
        self.assertEqual("inspected", result["status"])
        self.assertEqual([], result["signatures"])
        self.assertFalse(result["pdf_dss"]["present"])

    def test_signed_pdf_has_cms_cert_and_full_coverage(self):
        pdf = bridge._sign_one(self.pdf, self.signer, {}, {}, None, None)
        structure = inspector.inspect_bytes(pdf)
        self.assertEqual("inspected", structure["status"], structure["messages"])
        self.assertEqual(1, len(structure["signatures"]))
        sig = structure["signatures"][0]
        self.assertTrue(sig["cms_readable"], structure["messages"])
        self.assertTrue(sig["covers_whole_file"])
        self.assertEqual("ETSI.CAdES.detached", sig["subfilter"])
        self.assertEqual(1, sig["certificates_in_cms"])
        self.assertEqual(0, sig["timestamp_tokens_in_cms"])

    def test_timestamp_token_is_present_not_automatically_qualified(self):
        pdf = bridge._sign_one(
            self.pdf, self.signer, {}, {}, bridge._get_test_tsa(), None
        )
        structure = inspector.inspect_bytes(pdf)
        self.assertEqual("inspected", structure["status"])
        self.assertEqual(1, structure["signatures"][0]["timestamp_tokens_in_cms"])
        comparison = inspector.compare_evidence({
            "structure": structure,
            "signature": "unverified",
            "timestamp": "unverified",
            "crypto": "unverified",
        })
        self.assertNotEqual("consistent", comparison["status"])
        self.assertIn("kvalifikovan", " ".join(comparison["messages"]).lower())

    def test_three_certificates_are_physically_present_in_cms(self):
        root_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        ca_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        leaf_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        root = make_cert("Root", None, root_key, root_key, ca=True)
        ca = make_cert("CA", root, root_key, ca_key, ca=True)
        leaf = make_cert("Leaf", ca, ca_key, leaf_key, ca=False)
        registry = bridge._certificate_registry_for_chain(
            leaf.public_bytes(serialization.Encoding.DER),
            [ca.public_bytes(serialization.Encoding.DER),
             root.public_bytes(serialization.Encoding.DER)],
        )
        private = leaf_key.private_bytes(
            serialization.Encoding.DER,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
        signer = SimpleSigner(
            signing_cert=asn1_x509.Certificate.load(leaf.public_bytes(serialization.Encoding.DER)),
            signing_key=asn1_keys.PrivateKeyInfo.load(private),
            cert_registry=registry,
        )
        signed = bridge._sign_one(self.pdf, signer, {}, {}, None, None)
        struct = inspector.inspect_bytes(signed)
        self.assertTrue(struct["signatures"][0]["cms_readable"], struct["messages"])
        self.assertEqual(3, struct["signatures"][0]["certificates_in_cms"])

    def test_unreadable_input_never_reports_pass(self):
        result = inspector.inspect_bytes(b"%PDF-not a pdf")
        self.assertEqual("unverified", result["status"])
        outcome = inspector.compare_evidence({
            "structure": result, "signature": "valid", "crypto": "valid",
        })
        self.assertEqual("unverified", outcome["status"])

    def test_structural_disagreement_is_not_green(self):
        result = inspector.compare_evidence({
            "structure": {"status": "inspected", "signatures": [],
                          "pdf_dss": {"present": False}},
            "signature": "valid", "crypto": "valid",
        })
        self.assertEqual("conflict", result["status"])

    def test_absent_ocsp_crl_is_warning_not_invalid(self):
        result = inspector.compare_evidence({
            "structure": {"status": "inspected", "signatures": [{
                "cms_readable": True, "covers_whole_file": True,
                "certificates_in_cms": 3,
                "revocation_values_in_cms": False,
                "timestamp_tokens_in_cms": 1,
            }], "pdf_dss": {"present": False, "ocsp": 0, "crl": 0}},
            "signature": "valid", "crypto": "valid", "timestamp": "valid",
        })
        self.assertEqual("warning", result["status"])
        self.assertNotIn("neplatný", " ".join(result["messages"]).lower())


if __name__ == "__main__":
    unittest.main()
