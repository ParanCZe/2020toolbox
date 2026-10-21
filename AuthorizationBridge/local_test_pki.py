"""Disposable, in-memory PKI for explicit local TEST B-LT only.

No OS trust changes, files containing keys, remote services or paid timestamps.
The public root is exported only as a scoped validation hint, never QES trust.
"""
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import io

from asn1crypto import x509 as ax509, keys, ocsp as aocsp, crl as acrl
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509 import ocsp
from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID, AuthorityInformationAccessOID
from pyhanko.sign import signers
from pyhanko.sign.timestamps.dummy_client import DummyTimeStamper
from pyhanko_certvalidator import ValidationContext
from pyhanko_certvalidator.registry import SimpleCertificateStore


@dataclass(frozen=True)
class LocalTestPKI:
    root: ax509.Certificate
    issuers: tuple
    signer: signers.SimpleSigner
    timestamper: DummyTimeStamper
    ocsps: tuple
    crls: tuple
    refresh_after: datetime

    @property
    def issuer_der(self):
        return tuple(cert.dump() for cert in self.issuers)

    @property
    def root_pem(self):
        return x509.load_der_x509_certificate(self.root.dump()).public_bytes(serialization.Encoding.PEM)

    def validation_context(self):
        return ValidationContext(
            trust_roots=[self.root], other_certs=self.issuers,
            ocsps=self.ocsps, crls=self.crls,
            allow_fetching=False, revocation_mode="hard-fail",
        )

    def verify_lt_pdf(self, pdf_bytes):
        """Validate solely from final DSS plus this explicit PRIVATE test root."""
        from pyhanko.pdf_utils.reader import PdfFileReader
        from pyhanko.sign.validation import validate_pdf_signature
        from pyhanko.sign.validation.dss import DocumentSecurityStore
        reader = PdfFileReader(io.BytesIO(pdf_bytes), strict=True)
        if len(reader.embedded_signatures) != 1:
            raise ValueError("TEST B-LT očekává jediný podpis.")
        dss = DocumentSecurityStore.read_dss(reader)
        context = dss.as_validation_context(dict(
            trust_roots=[self.root], allow_fetching=False, revocation_mode="hard-fail",
        ))
        status = validate_pdf_signature(
            reader.embedded_signatures[0], signer_validation_context=context,
            ts_validation_context=context,
        )
        ts = status.timestamp_validity
        if not (status.intact and status.valid and status.trusted and ts is not None
                and ts.intact and ts.valid and ts.trusted and status.docmdp_ok is not False):
            raise ValueError("Nezávislé ověření lokální TEST B-LT evidence neprošlo.")


def create_test_pki(timestamper_class=DummyTimeStamper):
    now = datetime.now(timezone.utc)
    root_key, issuer_key, signer_key, tsa_key = (
        rsa.generate_private_key(public_exponent=65537, key_size=2048) for _ in range(4)
    )

    def name(common_name):
        return x509.Name([
            x509.NameAttribute(NameOID.COUNTRY_NAME, "CZ"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "20-20 TEST PKI - NOT QUALIFIED"),
            x509.NameAttribute(NameOID.COMMON_NAME, common_name),
        ])

    root_name = name("20-20 LOCAL TEST ROOT CA - NOT QUALIFIED")
    issuer_name = name("20-20 LOCAL TEST ISSUING CA - NOT QUALIFIED")

    def certificate(subject, public_key, issuer_subject, issuer_private, ca=False, path_length=None, tsa=False):
        cert = (x509.CertificateBuilder().subject_name(subject).issuer_name(issuer_subject)
                .public_key(public_key).serial_number(x509.random_serial_number())
                .not_valid_before(now - timedelta(minutes=5)).not_valid_after(now + timedelta(days=2))
                .add_extension(x509.BasicConstraints(ca=ca, path_length=path_length), critical=True)
                .add_extension(x509.SubjectKeyIdentifier.from_public_key(public_key), critical=False)
                .add_extension(x509.AuthorityKeyIdentifier.from_issuer_public_key(issuer_private.public_key()), critical=False)
                .add_extension(x509.KeyUsage(
                    digital_signature=True, content_commitment=not ca and not tsa,
                    key_encipherment=False, data_encipherment=False, key_agreement=False,
                    key_cert_sign=ca, crl_sign=ca, encipher_only=False, decipher_only=False,
                ), critical=True))
        if subject != issuer_subject:
            # Identifiers only; TEST contexts are fully offline and never fetch.
            cert = cert.add_extension(x509.AuthorityInformationAccess([
                x509.AccessDescription(AuthorityInformationAccessOID.OCSP,
                                       x509.UniformResourceIdentifier("http://test-pki.invalid/ocsp"))
            ]), critical=False).add_extension(x509.CRLDistributionPoints([
                x509.DistributionPoint(full_name=[x509.UniformResourceIdentifier("http://test-pki.invalid/ca.crl")],
                                       relative_name=None, reasons=None, crl_issuer=None)
            ]), critical=False)
        if tsa:
            cert = cert.add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.TIME_STAMPING]), critical=True)
        return cert.sign(issuer_private, hashes.SHA256())

    root = certificate(root_name, root_key.public_key(), root_name, root_key, ca=True, path_length=1)
    issuer = certificate(issuer_name, issuer_key.public_key(), root_name, root_key, ca=True, path_length=0)
    signer_cert = certificate(name("20-20 TOOLBOX TEST SIGNATURE - NOT QUALIFIED"),
                              signer_key.public_key(), issuer_name, issuer_key)
    tsa_cert = certificate(name("TEST TEST TEST - 20-20 LOCAL TSA"),
                           tsa_key.public_key(), issuer_name, issuer_key, tsa=True)

    def asn_cert(cert):
        return ax509.Certificate.load(cert.public_bytes(serialization.Encoding.DER))

    def asn_key(key):
        return keys.PrivateKeyInfo.load(key.private_bytes(
            serialization.Encoding.DER, serialization.PrivateFormat.PKCS8, serialization.NoEncryption(),
        ))

    def ocsp_response(cert, issuing_cert, issuing_key):
        response = (ocsp.OCSPResponseBuilder().add_response(
            cert=cert, issuer=issuing_cert, algorithm=hashes.SHA256(),
            cert_status=ocsp.OCSPCertStatus.GOOD, this_update=now - timedelta(minutes=1),
            next_update=now + timedelta(days=1), revocation_time=None, revocation_reason=None,
        ).responder_id(ocsp.OCSPResponderEncoding.HASH, issuing_cert)
          .sign(issuing_key, hashes.SHA256()))
        return aocsp.OCSPResponse.load(response.public_bytes(serialization.Encoding.DER))

    def crl(issuing_cert, issuing_key):
        value = (x509.CertificateRevocationListBuilder().issuer_name(issuing_cert.subject)
                 .last_update(now - timedelta(minutes=1)).next_update(now + timedelta(days=1))
                 .add_extension(x509.AuthorityKeyIdentifier.from_issuer_public_key(issuing_key.public_key()), critical=False)
                 .sign(issuing_key, hashes.SHA256()))
        return acrl.CertificateList.load(value.public_bytes(serialization.Encoding.DER))

    aroot, aissuer = asn_cert(root), asn_cert(issuer)
    registry = SimpleCertificateStore()
    registry.register_multiple((aissuer, aroot))
    signer = signers.SimpleSigner(signing_cert=asn_cert(signer_cert), signing_key=asn_key(signer_key), cert_registry=registry)
    signer.issuer_certificates_der = (aissuer.dump(), aroot.dump())
    signer.ca_certificate_count = 2
    timestamper = timestamper_class(tsa_cert=asn_cert(tsa_cert), tsa_key=asn_key(tsa_key),
                                   certs_to_embed=(aissuer, aroot), include_nonce=True)
    return LocalTestPKI(
        root=aroot, issuers=(aissuer, aroot), signer=signer, timestamper=timestamper,
        ocsps=(ocsp_response(signer_cert, issuer, issuer_key), ocsp_response(tsa_cert, issuer, issuer_key),
               ocsp_response(issuer, root, root_key)),
        crls=(crl(issuer, issuer_key), crl(root, root_key)),
        refresh_after=now + timedelta(hours=12),
    )
