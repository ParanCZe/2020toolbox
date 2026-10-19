"""Unit tests for public CA-chain packaging. No QSCD or paid TSA is accessed.

Run in the AuthorizationBridge venv:
    python -m unittest test_cert_chain
"""
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
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
        self.assertEqual(2, len(list(store.iter_certs())))

    def test_unrelated_issuer_is_rejected(self):
        with self.assertRaises(ValueError):
            bridge._certificate_registry_for_chain(self.leaf, [self.unrelated])

    def test_external_signer_carries_issuer_certificates(self):
        with patch.object(bridge, "_windows_cert_der", return_value=self.leaf), patch.object(
            bridge, "_windows_certificate_chain_der", return_value=[self.ca, self.root]
        ):
            signer = bridge.WindowsStoreSigner("0123456789ABCDEF0123456789ABCDEF01234567")
        self.assertEqual(2, signer.ca_certificate_count)
        self.assertEqual(2, len(list(signer.cert_registry.iter_certs())))
        self.assertEqual(256, signer.signature_size)

    def test_unavailable_chain_preserves_old_signing_mode(self):
        with patch.object(bridge, "_windows_cert_der", return_value=self.leaf), patch.object(
            bridge, "_windows_certificate_chain_der", side_effect=OSError("Windows store unavailable")
        ):
            signer = bridge.WindowsStoreSigner("0123456789ABCDEF0123456789ABCDEF01234567")
        self.assertEqual(0, signer.ca_certificate_count)
        self.assertEqual(0, len(list(signer.cert_registry.iter_certs())))


if __name__ == "__main__":
    unittest.main()
