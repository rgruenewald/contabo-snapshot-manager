# Security Policy

## Reporting Security Issues

We take the security of this project seriously. If you discover a security vulnerability or potential credential leak mechanism, please **do NOT open a public GitHub issue**.

Instead, please report security vulnerabilities responsibly:

1. **Email:** Contact the maintainer directly at `rg@lothar-medtec.de`.
2. **GitHub Security Advisories:** Use the "Report a vulnerability" button on the GitHub repository's Security tab (if available).

Please include:
- A description of the vulnerability.
- Steps to reproduce the issue or a proof-of-concept.
- Potential impact and affected configurations.

We will acknowledge your report promptly and work on a timely fix.

## Credential Safety Guidelines
- Never commit `.env` files or hardcode API secrets into Dockerfiles or scripts.
- Contabo Snapshot Manager is designed to run in memory without persisting API secrets to disk or transmitting them to third parties.
