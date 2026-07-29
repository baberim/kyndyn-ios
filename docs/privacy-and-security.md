# Privacy and security

Rowan contains family and child data. The default posture is local-first, data-minimizing, and free of advertising or third-party tracking.

- No production household data, credentials, calendar URLs, push endpoints, or PWA runtime files are present in this repository.
- Sample people are fictional.
- Future CloudKit data belongs in the household owner's private/shared Apple databases.
- Device notification preferences remain device-local.
- Parent-only mutation requires a production authentication design before App Store release; the current parent gate is a development boundary, not a security claim.
- Imports are explicit, previewed, size-limited, additive, and validated.
- Logs must not contain names, quest text, tokens, or import payloads.
- Secrets and signing files are ignored and must be supplied through Xcode/Apple systems.

Before release: complete privacy labels, retention/deletion behavior, child-safety review, account/share removal flows, encrypted export policy, threat modeling, and accessibility audit.

