# Privacy and security

Rowan contains family and child data. The default posture is local-first, data-minimizing, and free of advertising or third-party tracking.

- No production household data, credentials, calendar URLs, push endpoints, or PWA runtime files are present in this repository.
- Sample people are fictional.
- Future CloudKit data belongs in the household owner's private/shared Apple databases.
- Device notification preferences remain device-local.
- Parent-only screens and mutations require device-owner authentication or an optional Rowan PIN.
- The Rowan PIN is salted, deliberately slow-hashed, and stored in the device-only Keychain. Plaintext PINs never enter SwiftData, UserDefaults, logs, fixtures, or source.
- Parent authentication protects against casual access on an already unlocked/shared device; it does not create a verified online parental identity or an account-recovery system.
- Parent access re-locks after two minutes in the background and whenever profiles change.
- Notification settings, permission state, device profile, and scheduled requests are device-local. Lock-screen quest titles are off by default.
- Imports are explicit, previewed, size-limited, additive, and validated.
- Logs must not contain names, quest text, tokens, or import payloads.
- Secrets and signing files are ignored and must be supplied through Xcode/Apple systems.

If a parent forgets the Rowan PIN, device-owner authentication can still open Parent security to replace it. If both methods are unavailable, Rowan cannot honestly verify parental identity; there is no email or server reset.

Before release: complete privacy labels, retention/deletion behavior, child-safety review, account/share removal flows, encrypted export policy, independent threat modeling, and an external accessibility audit.
