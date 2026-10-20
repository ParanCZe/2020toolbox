# Private web Bridge – deployment scaffold

This is a TEST-only API deployment scaffold, **not** a deployed instance and
**not** the entire 2020Toolbox application.

## Access boundary

- Docker binds to **127.0.0.1:18094**, not the public network.
- The API requires an exact allowed Origin and server-side bearer secret.
- **Never place TOOLBOX_WEB_TEST_TOKEN inside browser JavaScript.** Origin is
  not authentication. Put a private identity-aware gateway (e.g. access proxy
  with MFA) in front of any public HTTPS access. Backend auth must validate
  an actual authenticated user session or signed per-user access token.
- The current API is intended for a trusted server-to-server caller or
  development smoke tests only. A browser-facing authentication integration
  is not complete; do not publicly expose the container.
- Use private GitHub repository permissions to protect source code.
  GitHub repository visibility does not protect a deployed website.

## Initial launch on a privately administered server

1. Copy the repo to your own server with Docker Compose.
2. Create an **untracked** `.env` with `TOOLBOX_WEB_ORIGIN` and
   `TOOLBOX_WEB_TEST_TOKEN` (long random secret).
3. From this directory run `docker compose up --build -d`.
4. Health endpoint on the server: `http://127.0.0.1:18094/api/health`.
5. Only after adding an authentication gateway and TLS should any browser
   be granted access.

## Architecture still to complete

- Hosted frontend and session-backed login with MFA.
- Authenticated end-user PDF uploading, quotas and audit logging.
- Isolated PDF/A / veraPDF / EU DSS services.
- Signature job queue **from** the designated Windows signer PC. Never put
  Windows Certificate Store private keys, PINs, or PFX in this container.
- CI/CD deployment secrets and rollback mechanism.

Development TEST signatures must never be represented as real, trusted
or qualified signatures.
