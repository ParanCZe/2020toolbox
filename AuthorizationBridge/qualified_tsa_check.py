"""Independently validate the embedded RFC3161 signature timestamp(s).

This runs in the PDFValidator venv (pyHanko[etsi,async-http] + pyhanko-cli).
No private keys, PIN or PostSignum signing credentials are accessed. Public EU
LOTL/CZ TL and revocation data may be downloaded.

Crucially, do not derive timestamp validity from free-form CLI text:
AdES-LTA's pretty-print status may omit a timestamp if signature trust or
proof-of-existence processing terminated early.
"""
from __future__ import annotations

import asyncio
import json
import sys
from pathlib import Path

def assess_timestamp(status, ades_subindic, qtst_uri):
    """Fail closed: report 'valid' only with independent verified QTST proof."""
    indication = str(ades_subindic)
    if status is None:
        return "unverified", indication
    if not status.intact or not status.valid:
        return "invalid", indication + " – RFC3161 imprint nebo kryptografie neodpovídá."
    if not status.trusted or status.validation_path is None:
        return "unverified", indication + " – neověřený řetězec důvěry TSA."
    q = status.qualification_result
    if not q or not q.status.qualified or q.service_definition is None:
        return "unverified", indication + " – kvalifikace TSA nebyla prokázána."
    if q.service_definition.base_info.service_type != qtst_uri:
        return "unverified", indication + " – autorita nemá ověřený QTST typ služby."
    if "AdESPassed.OK" not in indication:
        return "unverified", indication + " – ověření AdES není úplné."
    return "valid", indication + " – kryptograficky platné kvalifikované RFC3161 razítko."


async def validate_file(pdf_path: Path):
    from pyhanko.pdf_utils.reader import PdfFileReader
    from pyhanko.sign.validation import generic_cms
    from pyhanko.sign.validation.ades import ades_timestamp_validation
    from pyhanko.sign.validation.policy_decl import SignatureValidationSpec, QualificationRequirements
    from pyhanko.sign.validation.qualified.tsp import QTST_URI
    from pyhanko.cli._trust import init_trust_manager, TrustManagerSettings
    from pyhanko_certvalidator.context import CertValidationPolicySpec
    from pyhanko_certvalidator.policy_decl import CertRevTrustPolicy, RevocationCheckingPolicy

    # Keep the *exact* signed national TL and revocation requirements used
    # by eIDAS validation. Do not invoke an asyncio.run() wrapper here:
    # this function already runs inside the event loop.
    trust_manager = await init_trust_manager(
        TrustManagerSettings(
            trust=None, trust_replace=False, eutl=True,
            eutl_force_redownload=False, territories="cz",
        ),
        cli_config=None,
    )
    policy = CertValidationPolicySpec(
        trust_manager=trust_manager,
        revinfo_policy=CertRevTrustPolicy(
            RevocationCheckingPolicy.from_legacy("require")
        ),
    )
    spec = SignatureValidationSpec(
        cert_validation_policy=policy,
        ts_qualification_requirements=QualificationRequirements(
            require_service_type=QTST_URI,
        ),
    )
    sigs=[]
    with pdf_path.open("rb") as doc:
        reader=PdfFileReader(doc)
        for signature in reader.embedded_regular_signatures:
            tokens=list(generic_cms.extract_tst_data_iter(signature.signer_info, signed=False))
            sigs.append((signature.field_name, signature.signer_info, tokens))
        # Extracted ASN.1 objects remain valid after closing file.

    if not sigs:
        return dict(status="unverified", total_tokens=0, details=["PDF nemá běžný elektronický podpis."])

    total=0
    results=[]
    for name, signer_info, tokens in sigs:
        if not tokens:
            results.append({"field":name,"status":"unverified",
                            "details":["V podpisu není RFC3161 podpisové časové razítko."]})
            continue
        individual=[]
        for ix, signed_data in enumerate(tokens):
            total+=1
            try:
                r=await ades_timestamp_validation(
                    signed_data, spec,
                    expected_tst_imprint=generic_cms.message_imprint_checker(signer_info),
                )
                value,description=assess_timestamp(r.api_status,r.ades_subindic,QTST_URI)
                individual.append({"token":ix+1,"status":value,"reason":description,
                                   "production_time":r.api_status.timestamp.isoformat() if r.api_status else None})
            except Exception as exc:
                individual.append({"token":ix+1,"status":"unverified",
                                   "reason":"Razítko nebylo možné ověřit: "+str(exc)[:400]})
        sig_status=("valid" if individual and all(i["status"]=="valid" for i in individual)
                    else "invalid" if any(i["status"]=="invalid" for i in individual)
                    else "unverified")
        results.append({"field":name,"status":sig_status,"tokens":individual})
    final=("valid" if results and all(r["status"]=="valid" for r in results)
           else "invalid" if any(r["status"]=="invalid" for r in results)
           else "unverified")
    return {"status":final,"total_tokens":total,"details":results}


def self_test():
    class Info:
        def __init__(self,good=True,trust=True,qualified=True,qtst=True):
            self.intact=good
            self.valid=good
            self.trusted=trust
            self.validation_path=object() if trust else None
            from types import SimpleNamespace as NS
            self.qualification_result=NS(status=NS(qualified=qualified),
                                         service_definition=NS(base_info=NS(service_type="QTST" if qtst else "OTHER")))
    assert assess_timestamp(Info(),"AdESPassed.OK","QTST")[0]=="valid"
    assert assess_timestamp(Info(good=False),"AdESFailure.HASH_FAILURE","QTST")[0]=="invalid"
    assert assess_timestamp(Info(trust=False),"AdESIndeterminate.NO_CERTIFICATE_CHAIN_FOUND","QTST")[0]=="unverified"
    assert assess_timestamp(Info(qualified=False),"AdESPassed.OK","QTST")[0]=="unverified"
    assert assess_timestamp(Info(qtst=False),"AdESPassed.OK","QTST")[0]=="unverified"
    assert assess_timestamp(Info(),"AdESIndeterminate.OTHER","QTST")[0]=="unverified"
    print("independent QTSA status tests passed")


if __name__=="__main__":
    if len(sys.argv)==2 and sys.argv[1]=="--self-test":
        self_test()
    elif len(sys.argv)==2:
        try:
            print(json.dumps(asyncio.run(validate_file(Path(sys.argv[1]))),ensure_ascii=False))
        except Exception as exc:
            print(json.dumps({"status":"unverified","total_tokens":0,
                              "details":[str(exc)[:1200]],"error":True},ensure_ascii=False))
            sys.exit(1)
    else:
        raise SystemExit("Usage: qualified_tsa_check.py input.pdf | --self-test")
