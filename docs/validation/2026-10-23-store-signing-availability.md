# Current Store signing identity availability

Date: 2026-10-23. Issue #52 / release gate #14.

The current read-only login-keychain checks found no `Apple Distribution` or `Mac Installer Distribution` certificate and `security find-identity -v -p codesigning` reported zero valid signing identities. No keychain setting, certificate, trust, profile, or signing credential was changed or exported.

The successful signed archive/export recorded in [the September rehearsal](2026-09-08-local-signed-export.md) remains valid evidence for that exact earlier source and artifact. It does not establish signing availability in the current environment or validate a reviewed `main` candidate. A new local signed archive cannot be reproduced until the publisher's identities are again available. No archive, upload, or TestFlight operation was attempted.
