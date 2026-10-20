"""Hosted TEST-only PAdES bridge.

Deploy behind HTTPS and an identity-aware reverse proxy. NEVER expose the
Windows/production AuthorizationBridge app as a public web service.
No PFX, Windows store, paid TSA, or persistent signer keys are accepted.
"""
import io
import os
import secrets
from flask import Flask, jsonify, request, send_file
from pyhanko.pdf_utils.reader import PdfFileReader

from authorization_bridge import _make_test_signer, _sign_one

MAX_PDF = 20 * 1024 * 1024


def create_app():
    app = Flask(__name__)
    app.config["MAX_CONTENT_LENGTH"] = MAX_PDF + 1024 * 1024
    allowed_origin = os.environ.get("TOOLBOX_WEB_ORIGIN", "").rstrip("/")
    api_token = os.environ.get("TOOLBOX_WEB_TEST_TOKEN", "")

    @app.after_request
    def security_headers(response):
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        if allowed_origin and request.headers.get("Origin") == allowed_origin:
            response.headers["Access-Control-Allow-Origin"] = allowed_origin
            response.headers["Vary"] = "Origin"
            response.headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type"
            response.headers["Access-Control-Allow-Methods"] = "POST, OPTIONS, GET"
        return response

    def authorised():
        if not allowed_origin or not api_token or len(api_token) < 32:
            return False
        origin = request.headers.get("Origin")
        if origin and origin != allowed_origin:
            return False
        supplied = request.headers.get("Authorization", "")
        return supplied.startswith("Bearer ") and secrets.compare_digest(
            supplied[7:], api_token
        )

    @app.get("/api/health")
    def health():
        return jsonify(ok=True, service="2020Toolbox Web TEST Bridge",
                       test_only=True, production_signing=False)

    @app.route("/api/test-sign", methods=["POST", "OPTIONS"])
    def test_sign():
        if request.method == "OPTIONS":
            # Browser preflight never authorises an actual signing request.
            if request.headers.get("Origin") != allowed_origin or not allowed_origin:
                return jsonify(ok=False), 403
            return "", 204
        if not authorised():
            return jsonify(ok=False, error="TEST signing not authorised."), 403
        f = request.files.get("pdf")
        if not f or not f.filename.lower().endswith(".pdf"):
            return jsonify(ok=False, error="Upload one PDF."), 400
        source = f.read(MAX_PDF + 1)
        if len(source) > MAX_PDF:
            return jsonify(ok=False, error="PDF too large."), 413
        if not source.startswith(b"%PDF-"):
            return jsonify(ok=False, error="Not a PDF."), 400
        try:
            reader = PdfFileReader(io.BytesIO(source), strict=True)
            if reader.embedded_signatures:
                return jsonify(ok=False, error="Already signed PDF."), 400
            if reader.security_handler is not None:
                return jsonify(ok=False, error="Encrypted PDF unsupported."), 400
            # Ephemeral anonymous self-signed signer; NO production identities.
            signed = _sign_one(source, _make_test_signer(), {}, {}, None, None)
        except Exception:
            app.logger.exception("TEST signing error")
            return jsonify(ok=False, error="Invalid or unsupported PDF."), 422
        response = send_file(io.BytesIO(signed), mimetype="application/pdf",
                             as_attachment=True, download_name="TEST_only_signed.pdf")
        response.headers["X-Toolbox-Signature"] = "SELF-SIGNED-TEST-NOT-QUALIFIED"
        return response

    return app


app = create_app()

if __name__ == "__main__":
    raise SystemExit("Run behind a production WSGI server and HTTPS reverse proxy.")
