"""Unit tests for public CA-chain packaging. No QSCD or paid TSA is accessed.

Run in the AuthorizationBridge venv:
    python -m unittest test_cert_chain
"""
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch
from unittest.mock import MagicMock

from cryptography import x509
from asn1crypto import x509 as asn1_x509, keys as asn1_keys, cms
from pypdf import PdfWriter
from pyhanko.pdf_utils.reader import PdfFileReader
from pyhanko.sign.signers import SimpleSigner
import io
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.x509.oid import NameOID

import authorization_bridge as bridge


def _make_cert(subject, issuer, issuer_key, public_key, is_ca):
    now = datetime.now(timezone.utc)
    return (
        x509.CertificateBuilder()
        .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, subject)]))
        .issuer_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, issuer)]))
        .public_key(public_key)
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - timedelta(days=1))
        .not_valid_after(now + timedelta(days=30))
        .add_extension(x509.BasicConstraints(ca=is_ca, path_length=None), critical=True)
        .sign(issuer_key, hashes.SHA256())
        .public_bytes(serialization.Encoding.DER)
    )


class WindowsCertificateChainTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        cls.ca_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        cls.signer_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        cls.unrelated_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        cls.root = _make_cert("Test root", "Test root", cls.root_key, cls.root_key.public_key(), True)
        cls.ca = _make_cert("Test CA", "Test root", cls.root_key, cls.ca_key.public_key(), True)
        cls.leaf = _make_cert("Test signer", "Test CA", cls.ca_key, cls.signer_key.public_key(), False)
        cls.unrelated = _make_cert(
            "Unrelated CA", "Unrelated CA", cls.unrelated_key, cls.unrelated_key.public_key(), True
        )

    def test_verified_issuer_chain_is_registered(self):
        store = bridge._certificate_registry_for_chain(self.leaf, [self.ca, self.root])
        self.assertEqual(1, len(store.retrieve_by_name(asn1_x509.Certificate.load(self.ca).subject)))

    def test_unrelated_issuer_is_rejected(self):
        with self.assertRaises(ValueError):
            bridge._certificate_registry_for_chain(self.leaf, [self.unrelated])

    def test_external_signer_carries_issuer_certificates(self):
        with patch.object(bridge, "_windows_cert_der", return_value=self.leaf), patch.object(
            bridge, "_windows_certificate_chain_der", return_value=[self.ca, self.root]
        ):
            signer = bridge.WindowsStoreSigner("0123456789ABCDEF0123456789ABCDEF01234567")
        self.assertEqual(2, signer.ca_certificate_count)
        self.assertEqual(1, len(signer.cert_registry.retrieve_by_name(asn1_x509.Certificate.load(self.ca).subject)))
        self.assertEqual(256, signer.signature_size)

    def test_cms_signature_embeds_full_public_chain(self):
        """Check actual PDF/CMS output, not only signer registry contents."""
        ca_store = bridge._certificate_registry_for_chain(self.leaf, [self.ca, self.root])
        key_der = self.signer_key.private_bytes(
            serialization.Encoding.DER,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
        signer = SimpleSigner(
            signing_cert=asn1_x509.Certificate.load(self.leaf),
            signing_key=asn1_keys.PrivateKeyInfo.load(key_der),
            cert_registry=ca_store,
        )
        writer = PdfWriter()
        writer.add_blank_page(width=420, height=600)
        input_pdf = io.BytesIO()
        writer.write(input_pdf)
        signed = bridge._sign_one(input_pdf.getvalue(), signer, {}, {}, None, None)
        reader = PdfFileReader(io.BytesIO(signed))
        self.assertEqual(1, len(reader.embedded_signatures))
        self.assertEqual(
            "ENTIRE_FILE",
            reader.embedded_signatures[0].evaluate_signature_coverage().name,
        )
        data = cms.ContentInfo.load(reader.embedded_signatures[0].pkcs7_content)
        certs = {
            item.chosen.dump() for item in data["content"]["certificates"]
            if item.name == "certificate"
        }
        self.assertIn(self.leaf, certs)
        self.assertIn(self.ca, certs)
        self.assertIn(self.root, certs)


    def test_postsignum_fallback_embeds_real_chain_in_signed_pdf(self):
        """Full fallback signer path: three CMS certs, valid PDF, one local TSA."""
        with patch.object(bridge, "_windows_cert_der", return_value=self.leaf), patch.object(
            bridge, "_windows_certificate_chain_der", return_value=[]
        ), patch.object(
            bridge, "_uses_postsignum_qca4", return_value=True
        ), patch.object(
            bridge, "_postsignum_qca4_chain", return_value=[self.ca, self.root]
        ), patch.object(
            bridge, "_windows_sign_data",
            side_effect=lambda thumb, payload: self.signer_key.sign(
                payload, padding.PKCS1v15(), hashes.SHA256()
            ),
        ):
            signer = bridge.WindowsStoreSigner("0123456789ABCDEF0123456789ABCDEF01234567")
            self.assertEqual(2, signer.ca_certificate_count)
            writer = PdfWriter()
            writer.add_blank_page(width=420, height=600)
            input_pdf = io.BytesIO()
            writer.write(input_pdf)
            before = bridge._TEST_TSA_ISSUED
            signed = bridge._sign_one(
                input_pdf.getvalue(), signer, {}, {}, bridge._get_test_tsa(), None
            )
        self.assertEqual(1, bridge._TEST_TSA_ISSUED - before)
        signature = PdfFileReader(io.BytesIO(signed)).embedded_signatures[0]
        self.assertEqual("ENTIRE_FILE", signature.evaluate_signature_coverage().name)
        data = cms.ContentInfo.load(signature.pkcs7_content)
        certs = {item.chosen.dump() for item in data["content"]["certificates"]
                 if item.name == "certificate"}
        self.assertEqual({self.leaf, self.ca, self.root}, certs)

    def test_postsignum_failure_aborts_batch_before_any_tsa(self):
        before = bridge._TEST_TSA_ISSUED
        with patch.object(bridge, "_windows_cert_der", return_value=self.leaf), patch.object(
            bridge, "_windows_certificate_chain_der", return_value=[]
        ), patch.object(
            bridge, "_uses_postsignum_qca4", return_value=True
        ), patch.object(
            bridge, "_postsignum_qca4_chain",
            side_effect=OSError("CA download unavailable")
        ):
            with self.assertRaisesRegex(RuntimeError, "zastaveno před použitím TSA"):
                bridge.WindowsStoreSigner("0123456789ABCDEF0123456789ABCDEF01234567")
        self.assertEqual(before, bridge._TEST_TSA_ISSUED)

    def test_downloaded_public_certificates_are_sha256_pinned(self):
        url = "https://www.postsignum.cz/files/ca/postsignum_qca4_sub.cer"
        from hashlib import sha256
        digest = sha256(self.ca).hexdigest()
        response = MagicMock()
        response.__enter__.return_value.read.return_value = self.ca
        bridge._download_pinned_issuer.cache_clear()
        with patch.object(bridge, "_POSTSIGNUM_QCA4_ISSUERS", ((url, digest),)), patch.object(
            bridge.urllib.request, "urlopen", return_value=response
        ):
            self.assertEqual(self.ca, bridge._download_pinned_issuer(url, digest))
            self.assertEqual(self.ca, bridge._download_pinned_issuer(url, digest))
            with self.assertRaisesRegex(ValueError, "Nepovolený"):
                bridge._download_pinned_issuer(url, "0" * 64)
            bridge._download_pinned_issuer.cache_clear()
            response.__enter__.return_value.read.return_value = self.unrelated
            with self.assertRaisesRegex(ValueError, "Otisk"):
                bridge._download_pinned_issuer(url, digest)
        bridge._download_pinned_issuer.cache_clear()

    def test_unavailable_chain_preserves_old_signing_mode(self):
        with patch.object(bridge, "_windows_cert_der", return_value=self.leaf), patch.object(
            bridge, "_windows_certificate_chain_der", side_effect=OSError("Windows store unavailable")
        ):
            signer = bridge.WindowsStoreSigner("0123456789ABCDEF0123456789ABCDEF01234567")
        self.assertEqual(0, signer.ca_certificate_count)
        self.assertEqual(0, len(signer.cert_registry.retrieve_by_name(asn1_x509.Certificate.load(self.ca).subject)))


if __name__ == "__main__":
    unittest.main()
