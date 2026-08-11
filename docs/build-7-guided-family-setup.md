# Build 7 guided family setup

Build 7 makes first-time setup understandable without requiring a separate
walkthrough from a tester or household owner.

## First run

- Four short, skippable lessons explain the quest and reward loop, the
  difference between profiles and device invitations, local-only versus iCloud
  family sync, and private backups.
- Setup, iCloud recovery, backup import, Rowan migration, and fictional sample
  mode remain separate choices.
- A pending Apple family invitation still takes precedence over first-run and
  sample setup, preventing accidental duplicate households.

## After creating a family

- A setup checklist appears after a real household is created.
- It explains where to add profiles, how the owner enables sharing, what the
  invited device should confirm, and how to export a private backup.
- The checklist remains available from the protected Parent area. Opening that
  area still requires the device-local parent authorization flow.

## Privacy and reliability

- Local-only use remains supported.
- Copy does not promise real-time background delivery; Kyndyn catches up when
  opened if Apple delayed background work.
- Backups are described as private files separate from iCloud sync and recovery.
- Existing households are not forced through first-run onboarding.
- No household records, CloudKit schema, credentials, or device-local secrets
  are changed by this release.

Release metadata advances to version 0.9.0, build 7.
