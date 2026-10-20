"""Offline end-to-end Adobe CMS OCSP test; no QSCD or paid TSA required."""
import io
import unittest
from unittest.mock import patch
from datetime import datetime, timedelta, timezone

from asn1crypto import x509 as ax509, keys as akeys, ocsp as aocsp
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509 import ocsp
from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID, AuthorityInformationAccessOID
from pypdf import PdfWriter
from pyhanko.sign import signers
from pyhanko.sign.validation import validate_pdf_signature
from pyhanko.pdf_utils.reader import PdfFileReader
from pyhanko_certvalidator import ValidationContext

import authorization_bridge as bridge
import pdf_ltv


class AdobeCmsIntegrationTest(unittest.TestCase):
    def test_adobe_local_test_tsa_is_free_and_available(self):
        before = bridge._TEST_TSA_ISSUED
        metadata = {
            "profile": "adobe",
            "tsa_url": "http://127.0.0.1:8094/test-tsa",
            "tsa_test_mode": True,
            "tsa_user": "TEST",
            "tsa_password": "TEST-ONLY",
        }
        stamp = bridge._build_timestamper(metadata)
        self.assertIs(stamp, bridge._get_test_tsa())
        # Building or preflighting the free TSA must not issue a timestamp.
        self.assertEqual(before, bridge._TEST_TSA_ISSUED)

    def test_adobe_signed_attribute_with_ocsp_and_one_rfc3161_stamp(self):
        now = datetime.now(timezone.utc)
        root_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        intermediate_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        signer_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        tsa_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        root_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Local integration CA")])
        root = (x509.CertificateBuilder().subject_name(root_name).issuer_name(root_name)
                .public_key(root_key.public_key()).serial_number(x509.random_serial_number())
                .not_valid_before(now - timedelta(days=1))
                .not_valid_after(now + timedelta(days=30))
                .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
                .add_extension(x509.KeyUsage(
                    digital_signature=True, content_commitment=False, key_encipherment=False,
                    data_encipherment=False, key_agreement=False, key_cert_sign=True,
                    crl_sign=True, encipher_only=False, decipher_only=False,
                ), critical=True).sign(root_key, hashes.SHA256()))
        intermediate_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Local integration intermediate CA")])
        intermediate = (x509.CertificateBuilder().subject_name(intermediate_name)
                        .issuer_name(root_name).public_key(intermediate_key.public_key())
                        .serial_number(x509.random_serial_number())
                        .not_valid_before(now - timedelta(days=1))
                        .not_valid_after(now + timedelta(days=30))
                        .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
                        .add_extension(x509.KeyUsage(
                            digital_signature=True, content_commitment=False,
                            key_encipherment=False, data_encipherment=False,
                            key_agreement=False, key_cert_sign=True, crl_sign=True,
                            encipher_only=False, decipher_only=False,
                        ), critical=True).sign(root_key, hashes.SHA256()))
        def issue(cn, pubkey, tsa=False):
            issuing_name = root_name if tsa else intermediate_name
            issuing_key = root_key if tsa else intermediate_key
            cert = (x509.CertificateBuilder().subject_name(
                x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, cn)])
            ).issuer_name(issuing_name).public_key(pubkey).serial_number(x509.random_serial_number())
              .not_valid_before(now - timedelta(days=1))
              .not_valid_after(now + timedelta(days=30))
              .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
              .add_extension(x509.KeyUsage(
                  digital_signature=True, content_commitment=not tsa, key_encipherment=False,
                  data_encipherment=False, key_agreement=False, key_cert_sign=False,
                  crl_sign=False, encipher_only=False, decipher_only=False
              ), critical=True)
              .add_extension(x509.AuthorityInformationAccess([
                  x509.AccessDescription(
                      AuthorityInformationAccessOID.OCSP,
                      x509.UniformResourceIdentifier("http://ocsp.example.invalid/"),
                  )
              ]), critical=False))
            if tsa:
                cert = cert.add_extension(
                    x509.ExtendedKeyUsage([ExtendedKeyUsageOID.TIME_STAMPING]), critical=True,
                )
            return cert.sign(issuing_key, hashes.SHA256())
        signer_cert = issue("Signer", signer_key.public_key())
        tsa_cert = issue("Timestamping authority", tsa_key.public_key(), tsa=True)

        def public_der(cert):
            return cert.public_bytes(serialization.Encoding.DER)
        def private_der(key):
            return key.private_bytes(
                serialization.Encoding.DER, serialization.PrivateFormat.PKCS8,
                serialization.NoEncryption(),
            )
        def ocsp_der(cert, issuer, issuer_key):
            return (ocsp.OCSPResponseBuilder()
                    .add_response(
                        cert=cert, issuer=issuer, algorithm=hashes.SHA1(),
                        cert_status=ocsp.OCSPCertStatus.GOOD,
                        this_update=now - timedelta(hours=1),
                        next_update=now + timedelta(days=7),
                        revocation_time=None, revocation_reason=None,
                    ).responder_id(ocsp.OCSPResponderEncoding.HASH, issuer)
                    .sign(issuer_key, hashes.SHA256())
                    .public_bytes(serialization.Encoding.DER))

        root_asn = ax509.Certificate.load(public_der(root))
        registry = bridge.SimpleCertificateStore()
        registry.register(root_asn)
        registry.register(ax509.Certificate.load(public_der(intermediate)))
        signer = signers.SimpleSigner(
            signing_cert=ax509.Certificate.load(public_der(signer_cert)),
            signing_key=akeys.PrivateKeyInfo.load(private_der(signer_key)),
            cert_registry=registry,
        )
        signer.issuer_certificates_der = (public_der(intermediate), public_der(root))
        timestamp = bridge.CountingDummyTimeStamper(
            tsa_cert=ax509.Certificate.load(public_der(tsa_cert)),
            tsa_key=akeys.PrivateKeyInfo.load(private_der(tsa_key)),
            certs_to_embed=[root_asn],
            include_nonce=True,
        )
        context = ValidationContext(
            trust_roots=[root_asn], other_certs=[root_asn],
            ocsps=[aocsp.OCSPResponse.load(ocsp_der(signer_cert, intermediate, intermediate_key)),
                   aocsp.OCSPResponse.load(ocsp_der(intermediate, root, root_key)),
                   aocsp.OCSPResponse.load(ocsp_der(tsa_cert, root, root_key))],
            allow_fetching=False, revocation_mode="hard-fail",
        )
        src = PdfWriter()
        src.add_blank_page(width=420, height=590)
        document = io.BytesIO()
        src.write(document)

        before = bridge._TEST_TSA_ISSUED
        with patch.object(bridge, "ValidationContext", return_value=context):
            signed = bridge._sign_one(document.getvalue(), signer, {}, {"profile": "adobe"}, timestamp, None)
        self.assertEqual(1, bridge._TEST_TSA_ISSUED - before)
        # Adobe's signed attribute must contain OCSP already at the time of
        # signing, rather than in a post-sign PDF /DSS revision.
        from asn1crypto import cms
        from asn1crypto.pdf import RevocationInfoArchival
        reader = PdfFileReader(io.BytesIO(signed), strict=True)
        self.assertNotIn('/DSS', reader.root)
        signature = reader.embedded_signatures[0]
        self.assertEqual('/adbe.pkcs7.detached', str(signature.sig_object['/SubFilter']))
        attrs = cms.ContentInfo.load(signature.pkcs7_content)['content']['signer_infos'][0]['signed_attrs']
        revocations = [attr for attr in attrs
                       if attr['type'].dotted == '1.2.840.113583.1.1.8']
        self.assertEqual(1, len(revocations))
        revocation = RevocationInfoArchival.load(revocations[0]['values'][0].dump())
        self.assertGreaterEqual(len(revocation['ocsp']), 2)
        self.assertEqual(1, bridge._TEST_TSA_ISSUED - before)
        status = validate_pdf_signature(
            signature,
            signer_validation_context=context,
            ts_validation_context=context,
        )
        self.assertTrue(status.intact, status.pretty_print_details())
        self.assertTrue(status.valid, status.pretty_print_details())


if __name__ == "__main__":
    unittest.main()
