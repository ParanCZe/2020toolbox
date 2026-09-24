"""
20-20 TOOLBOX · AuthorizationBridge v1.0
Local-only PAdES signing service for the Toolbox PDF authorization module.

Security model:
- binds exclusively to 127.0.0.1
- never persists PFX/P12 files or passphrases
- certificate material is kept only for the lifetime of a request
- signed documents are returned as an in-memory ZIP
"""

from __future__ import annotations

import io
import json
import os
import re
import tempfile
import traceback
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from flask import Flask, jsonify, request, send_file
import pyhanko
from pyhanko import stamp
from pyhanko.pdf_utils import images
from pyhanko.pdf_utils.incremental_writer import IncrementalPdfFileWriter
from pyhanko.sign import fields, signers, timestamps


APP_VERSION = "1.1.0"
HOST = "127.0.0.1"
PORT = 8094
MAX_BYTES = 600 * 1024 * 1024

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = MAX_BYTES


@app.after_request
def cors(response):
    # The service stores no credentials and only signs data explicitly supplied
    # in the same request, so wildcard CORS is acceptable for this localhost-only
    # bridge. Private Network Access is explicitly enabled for Chromium.
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type"
    response.headers["Access-Control-Allow-Private-Network"] = "true"
    response.headers["Cache-Control"] = "no-store"
    return response


@app.route("/<path:_path>", methods=["OPTIONS"])
@app.route("/", methods=["OPTIONS"])
def options(_path: str = ""):
    return ("", 204)


def _fmt_dt(value: Any) -> str:
    try:
        if value is None:
            return ""
        if hasattr(value, "astimezone"):
            value = value.astimezone()
        return value.strftime("%d.%m.%Y %H:%M:%S %Z").strip()
    except Exception:
        return str(value)


def _load_signer(pfx_bytes: bytes, password: str) -> signers.SimpleSigner:
    path = None
    try:
        with tempfile.NamedTemporaryFile(prefix="2020-auth-", suffix=".pfx", delete=False) as tmp:
            tmp.write(pfx_bytes)
            path = tmp.name
        signer = signers.SimpleSigner.load_pkcs12(
            path,
            passphrase=password.encode("utf-8") if password else None,
        )
        if signer is None:
            raise ValueError("Certifikát se nepodařilo načíst. Zkontroluj heslo a obsah PFX/P12.")
        return signer
    finally:
        if path:
            try:
                os.remove(path)
            except OSError:
                pass


def _cert_payload(signer: signers.SimpleSigner) -> dict[str, Any]:
    cert = signer.signing_cert
    validity = cert["tbs_certificate"]["validity"]
    return {
        "subject": cert.subject.human_friendly,
        "issuer": cert.issuer.human_friendly,
        "serial": str(cert.serial_number),
        "valid_from": _fmt_dt(validity["not_before"].native),
        "valid_to": _fmt_dt(validity["not_after"].native),
    }


def _safe_name(name: str, fallback: str = "document.pdf") -> str:
    name = os.path.basename(name or fallback)
    name = re.sub(r"[\\/:*?\"<>|\x00-\x1f]", "_", name).strip(" .")
    if not name:
        name = fallback
    if not name.lower().endswith(".pdf"):
        name += ".pdf"
    return name


def _ear_name(name: str) -> str:
    base = _safe_name(name)
    stem, _ext = os.path.splitext(base)
    if not stem.lower().endswith("_ear"):
        stem += "_EAR"
    return stem + ".pdf"


def _unique_name(name: str, used: set[str]) -> str:
    base = _safe_name(name)
    stem, ext = os.path.splitext(base)
    candidate = base
    n = 2
    while candidate.lower() in used:
        if stem.lower().endswith("_ear"):
            candidate = f"{stem[:-4]}_{n}_EAR{ext}"
        else:
            candidate = f"{stem}_{n}{ext}"
        n += 1
    used.add(candidate.lower())
    return candidate


def _validate_box(box: Any) -> tuple[int, int, int, int]:
    if not isinstance(box, list) or len(box) != 4:
        raise ValueError("Neplatný obdélník viditelného podpisu.")
    vals = [float(x) for x in box]
    x1, y1, x2, y2 = vals
    if x2 <= x1 or y2 <= y1:
        raise ValueError("Obdélník podpisu má nulovou nebo zápornou velikost.")
    if max(abs(x) for x in vals) > 100000:
        raise ValueError("Souřadnice podpisu jsou mimo očekávaný rozsah.")
    return tuple(int(round(x)) for x in vals)  # type: ignore[return-value]


def _stamp_style(stamp_path: str | None):
    if stamp_path:
        # Static image appearance: the image itself is the signature appearance.
        return stamp.StaticStampStyle(
            background=images.PdfImage(stamp_path),
            background_opacity=1.0,
            border_width=0,
        )
    # Text fallback uses only ASCII to stay compatible with the default font.
    return stamp.TextStampStyle(
        stamp_text="Podepsal: %(signer)s\nCas: %(ts)s",
        border_width=1,
        background_opacity=0.0,
    )


def _sign_one(
    pdf_bytes: bytes,
    signer: signers.SimpleSigner,
    document_meta: dict[str, Any],
    common_meta: dict[str, Any],
    timestamper,
    stamp_path: str | None,
) -> bytes:
    field_name = "Signature_2020_" + os.urandom(8).hex()
    placement = document_meta.get("placement")

    new_field = None
    appearance = None
    if placement:
        page = int(placement.get("page", 0))
        if page < 0:
            raise ValueError("Číslo stránky podpisu je neplatné.")
        box = _validate_box(placement.get("box"))
        new_field = fields.SigFieldSpec(
            sig_field_name=field_name,
            on_page=page,
            box=box,
        )
        appearance = _stamp_style(stamp_path)
    else:
        # box=None => invisible signature field.
        new_field = fields.SigFieldSpec(sig_field_name=field_name)

    sig_meta = signers.PdfSignatureMetadata(
        field_name=field_name,
        md_algorithm="sha256",
        subfilter=fields.SigSeedSubFilter.PADES,
        reason=common_meta.get("reason") or None,
        location=common_meta.get("location") or None,
        contact_info=common_meta.get("contact") or None,
        certify=False,
    )

    input_stream = io.BytesIO(pdf_bytes)
    output_stream = io.BytesIO()
    writer = IncrementalPdfFileWriter(input_stream)
    pdf_signer = signers.PdfSigner(
        sig_meta,
        signer=signer,
        timestamper=timestamper,
        stamp_style=appearance,
        new_field_spec=new_field,
    )
    pdf_signer.sign_pdf(writer, output=output_stream)
    return output_stream.getvalue()


@app.get("/status")
def status():
    return jsonify(
        ok=True,
        service="20-20 AuthorizationBridge",
        version=APP_VERSION,
        pyhanko=getattr(pyhanko, "__version__", "unknown"),
        host=HOST,
        port=PORT,
    )


@app.post("/certificate-info")
def certificate_info():
    try:
        cert = request.files.get("certificate")
        if cert is None:
            return jsonify(ok=False, error="Chybí PFX/P12 certifikát."), 400
        password = request.form.get("password", "")
        raw = cert.read()
        if not raw:
            return jsonify(ok=False, error="Certifikát je prázdný."), 400
        signer = _load_signer(raw, password)
        return jsonify(ok=True, **_cert_payload(signer))
    except Exception as exc:
        return jsonify(ok=False, error=str(exc)), 400


@app.post("/sign-batch")
def sign_batch():
    stamp_path = None
    try:
        cert = request.files.get("certificate")
        pdfs = request.files.getlist("pdfs")
        metadata_raw = request.form.get("metadata", "")
        password = request.form.get("password", "")

        if cert is None:
            return jsonify(ok=False, error="Chybí PFX/P12 certifikát."), 400
        if not pdfs:
            return jsonify(ok=False, error="Nebyla odeslána žádná PDF."), 400
        try:
            meta = json.loads(metadata_raw)
        except Exception:
            return jsonify(ok=False, error="Metadata požadavku nejsou platný JSON."), 400

        docs_meta = meta.get("documents")
        if not isinstance(docs_meta, list) or len(docs_meta) != len(pdfs):
            return jsonify(ok=False, error="Počet dokumentů neodpovídá metadatům."), 400

        profile = str(meta.get("profile") or "bt").lower()
        if profile not in {"bb", "bt"}:
            return jsonify(ok=False, error="Podporované profily jsou PAdES B-B a B-T."), 400

        tsa_url = str(meta.get("tsa_url") or "").strip()
        if profile == "bt":
            if not re.match(r"^https?://", tsa_url, re.I):
                return jsonify(ok=False, error="Pro PAdES B-T je nutná platná HTTP(S) adresa RFC 3161 TSA serveru."), 400
            timestamper = timestamps.HTTPTimeStamper(tsa_url)
        else:
            timestamper = None

        signer = _load_signer(cert.read(), password)
        cert_info = _cert_payload(signer)

        stamp_file = request.files.get("stamp")
        if stamp_file and stamp_file.filename:
            ext = Path(stamp_file.filename).suffix.lower()
            if ext not in {".png", ".jpg", ".jpeg"}:
                return jsonify(ok=False, error="Obrázek razítka musí být PNG nebo JPG."), 400
            with tempfile.NamedTemporaryFile(prefix="2020-stamp-", suffix=ext, delete=False) as tmp:
                tmp.write(stamp_file.read())
                stamp_path = tmp.name

        out_zip = io.BytesIO()
        used_names: set[str] = set()
        manifest_files = []

        with zipfile.ZipFile(out_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
            for idx, uploaded in enumerate(pdfs):
                original_name = uploaded.filename or f"document_{idx+1}.pdf"
                raw_pdf = uploaded.read()
                if not raw_pdf.startswith(b"%PDF-"):
                    raise ValueError(f"{original_name}: soubor nevypadá jako PDF.")

                doc_meta = docs_meta[idx] if isinstance(docs_meta[idx], dict) else {}
                signed = _sign_one(
                    raw_pdf,
                    signer=signer,
                    document_meta=doc_meta,
                    common_meta=meta,
                    timestamper=timestamper,
                    stamp_path=stamp_path,
                )
                requested_output = str(doc_meta.get("output_name") or original_name)
                out_name = _unique_name(_ear_name(requested_output), used_names)
                zf.writestr(out_name, signed)
                manifest_files.append(
                    {
                        "source": str(doc_meta.get("name") or original_name),
                        "output": out_name,
                        "standard": str(meta.get("output_standard") or "PDF/A-3b"),
                        "profile": "PAdES B-T" if profile == "bt" else "PAdES B-B",
                        "visible": bool(doc_meta.get("placement")),
                    }
                )

            manifest = {
                "tool": "20-20 TOOLBOX · Autorizace PDF",
                "bridge_version": APP_VERSION,
                "created_utc": datetime.now(timezone.utc).isoformat(),
                "profile": "PAdES B-T" if profile == "bt" else "PAdES B-B",
                "output_standard": str(meta.get("output_standard") or "PDF/A-3b"),
                "tsa_url": tsa_url if profile == "bt" else None,
                "certificate": cert_info,
                "files": manifest_files,
            }
            zf.writestr("20-20_autorizace_manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))

        out_zip.seek(0)
        name = "autorizovane_pdf_" + datetime.now().strftime("%Y-%m-%d_%H%M") + ".zip"
        return send_file(
            out_zip,
            mimetype="application/zip",
            as_attachment=True,
            download_name=name,
            max_age=0,
        )

    except Exception as exc:
        print("[AuthorizationBridge] signing error:", traceback.format_exc(), flush=True)
        return jsonify(ok=False, error=str(exc)), 400
    finally:
        if stamp_path:
            try:
                os.remove(stamp_path)
            except OSError:
                pass


if __name__ == "__main__":
    print(f"20-20 AuthorizationBridge v{APP_VERSION} · http://{HOST}:{PORT}", flush=True)
    app.run(host=HOST, port=PORT, threaded=True, debug=False, use_reloader=False)
