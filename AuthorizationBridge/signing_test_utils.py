"""Real offline PAdES LT test with signed synthetic signer & TSA OCSP replies."""
import io
from datetime import datetime, timedelta, timezone

from asn1crypto import x509 as ax509, keys as akeys, ocsp as aocsp
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509 import ocsp
from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID, AuthorityInformationAccessOID
from pypdf import PdfWriter
from pyhanko.sign import signers
from pyhanko_certvalidator import ValidationContext

import authorization_bridge as bridge


def signing_fixture(revoked_signer=False):
    now = datetime.now(timezone.utc)
    root_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
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
    def issue(cn, pubkey, tsa=False):
        cert = (x509.CertificateBuilder().subject_name(
            x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, cn)])
        ).issuer_name(root_name).public_key(pubkey).serial_number(x509.random_serial_number())
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
        return cert.sign(root_key, hashes.SHA256())
    signer_cert = issue("Signer", signer_key.public_key())
    tsa_cert = issue("Timestamping authority", tsa_key.public_key(), tsa=True)

    def public_der(cert):
        return cert.public_bytes(serialization.Encoding.DER)
    def private_der(key):
        return key.private_bytes(
            serialization.Encoding.DER, serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
    def ocsp_der(cert):
        return (ocsp.OCSPResponseBuilder()
                .add_response(
                    cert=cert, issuer=root, algorithm=hashes.SHA1(),
                    cert_status=(ocsp.OCSPCertStatus.REVOKED if revoked_signer and cert == signer_cert else ocsp.OCSPCertStatus.GOOD),
                    this_update=now - timedelta(hours=1),
                    next_update=now + timedelta(days=7),
                    revocation_time=(now - timedelta(hours=2) if revoked_signer and cert == signer_cert else None), revocation_reason=None,
                ).responder_id(ocsp.OCSPResponderEncoding.HASH, root)
                .sign(root_key, hashes.SHA256())
                .public_bytes(serialization.Encoding.DER))

    root_asn = ax509.Certificate.load(public_der(root))
    registry = bridge.SimpleCertificateStore()
    registry.register(root_asn)
    signer = signers.SimpleSigner(
        signing_cert=ax509.Certificate.load(public_der(signer_cert)),
        signing_key=akeys.PrivateKeyInfo.load(private_der(signer_key)),
        cert_registry=registry,
    )
    timestamp = bridge.CountingDummyTimeStamper(
        tsa_cert=ax509.Certificate.load(public_der(tsa_cert)),
        tsa_key=akeys.PrivateKeyInfo.load(private_der(tsa_key)),
        certs_to_embed=[root_asn],
        include_nonce=True,
    )
    context = ValidationContext(
        trust_roots=[root_asn], other_certs=[root_asn],
        ocsps=[aocsp.OCSPResponse.load(ocsp_der(signer_cert)),
               aocsp.OCSPResponse.load(ocsp_der(tsa_cert))],
        allow_fetching=False, revocation_mode="hard-fail",
    )
    src = PdfWriter()
    src.add_blank_page(width=420, height=590)
    document = io.BytesIO()
    src.write(document)

    return signer, timestamp, context, document.getvalue()
