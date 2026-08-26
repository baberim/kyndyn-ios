# Privacy and security

kyndyn contains family and child data. The default posture is local-first, data-minimizing, and free of advertising or third-party tracking.

- No production household data, credentials, calendar URLs, push endpoints, or PWA runtime files are present in this repository.
- Sample people are fictional.
- Future CloudKit data belongs in the household owner's private/shared Apple databases.
- Device notification preferences remain device-local.
- Parent-only screens and mutations require device-owner authentication or an optional kyndyn PIN.
- The kyndyn PIN is salted, deliberately slow-hashed, and stored in the device-only Keychain. Plaintext PINs never enter SwiftData, UserDefaults, logs, fixtures, or source.
- Parent authentication protects against casual access on an already unlocked/shared device; it does not create a verified online parental identity or an account-recovery system.
- Parent access re-locks after two minutes in the background and whenever profiles change.
- Notification settings, permission state, device profile, and scheduled requests are device-local. Lock-screen quest titles are off by default.
- Imports are explicit, previewed, size-limited, additive, and validated.
- Prepared exports are decoded and validated before the Files sheet opens.
- Removing a household from one device requires a recent successful private
  backup and exact household-name confirmation. It removes local household and
  sync metadata without enqueuing cloud deletions or stopping an Apple share.
- Logs must not contain names, quest text, tokens, or import payloads.
- Secrets and signing files are ignored and must be supplied through Xcode/Apple systems.

## Cloud Sync

When explicitly enabled, CloudKit may contain the household, people, quests,
schedules, completion events, rewards, and shared household policy. The owner
owns the private-zone records and invited participants access the shared zone
under Apple's CloudKit permissions.

kyndyn PIN material, biometric/authentication state, notification authorization,
device-profile selection, quiet-hour overrides, scheduled identifiers, view
preferences, onboarding state, caches, Apple credentials, and change tokens
remain device-local. Share membership identifies CloudKit access; it does not
prove kyndyn parent authority. Local parent authentication therefore remains
required.

Privacy-safe diagnostics are limited to operation type, database scope, retry
count, and redacted error category. They exclude household content, person
names, quest titles, record payloads, invitation URLs, tokens, and PIN data.

If a parent forgets the kyndyn PIN, device-owner authentication can still open Parent security to replace it. If both methods are unavailable, kyndyn cannot honestly verify parental identity; there is no email or server reset.

Before release: complete App Store privacy labels and policy/support URLs,
child-safety review, owner/participant share-removal policy, encrypted-export
policy, independent threat modeling, and an external accessibility audit.
