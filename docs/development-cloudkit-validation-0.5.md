# Development CloudKit Validation 0.5

## Outcome

Development CloudKit was exercised with fictional sample data on two physical
devices using different iCloud accounts. The owner created a household in the
owner’s private custom zone, uploaded the local household, created a private
`CKShare`, invited a participant through Apple’s system sharing interface, and
verified two-way completion and exact-undo convergence.

The tested configuration was:

- bundle identifier `com.kyndynfamily.kyndyn`;
- container `iCloud.com.kyndynfamily.kyndyn`;
- Debug / CloudKit Development environment;
- one owner iPhone and one participant iPad;
- no production schema or production data.

## Live physical-device results

Passed:

- existing local-only onboarding and sample household creation;
- additive SwiftData opening after iCloud capability activation;
- owner account check, custom-zone provisioning, initial upload, share creation,
  and direct round-trip root verification;
- incremental owner refresh, including filtering Apple’s `CKShare` system
  record from kyndyn payload decoding;
- offline quest edit queued locally, uploaded after connectivity returned, and
  removed from the queue only after confirmation;
- Apple private participant sheet and invitation delivery through Messages;
- invitation routing while the app was already installed and backgrounded;
- fresh participant install suppressed sample-household creation after the
  invitation was reviewed;
- owner-qualified shared-zone download of the root and all child records;
- participant completion upload, owner download, and one-time XP award;
- owner exact undo upload, participant download, and one-time XP removal;
- owner and participant manual refresh reported `Up to date`.

The app icon was installed through the asset catalog and generated successfully
for iPhone and iPad.

## Defects found and hardened

- SwiftData’s `.automatic` CloudKit selection conflicted with kyndyn’s explicit
  sync engine after adding entitlements. All app/test configurations now set
  `cloudKitDatabase: .none`.
- The generated Info.plist omitted custom CloudKit readiness keys. The target
  now uses an explicit Info.plist with build-setting substitution.
- `CKSharingSupported` was missing, causing iOS to request a newer app version
  for valid invitations.
- Scene-based SwiftUI apps require both active-scene and cold-launch invitation
  callbacks. kyndyn now configures an application and window-scene delegate.
- Provisioning retries repeated completed stages. The persisted state machine
  now resumes after its last confirmed stage.
- Initial change fetch attempted to decode Apple’s `CKShare` system record as a
  kyndyn payload. System records are now ignored.
- Shared-database zone IDs require the owner name from invitation metadata.
  Participant state now stores and reuses that owner-qualified zone ID.
- Root-record sharing requires shared records to be descendants. Non-root
  records now receive a CloudKit parent reference to the household root, with a
  one-time repair marker for already-provisioned Development households.
- A recoverable refresh incorrectly exposed **Enable and upload** again.
  Completed provisioning now retains a refresh/retry action.

## Automated results

The complete Xcode suite passed on an iPhone 17 Pro simulator running iOS 26.5:

- 49 passed;
- 0 failed;
- 0 skipped.

The suite includes deterministic in-memory CloudKit behavior, additive
migration, interruption/resume, duplicate delivery, stale tokens, account and
revocation states, offline queue/backoff, conflict rules, notification
replacement, multi-replica convergence, and UI/local persistence coverage.

Live CloudKit is not used by automated tests.

## Privacy and signing

Only fictional household content was used. kyndyn does not upload its local
PIN/authentication state, biometric state, notification authorization, device
targeting, quiet hours, scheduled notification identifiers, onboarding state,
view preferences, credentials, or tokens.

Development logs contain only operation labels and numeric CloudKit error
codes. They do not contain names, quest titles, payloads, invitation URLs,
CloudKit tokens, or Apple credentials.

The Apple Developer Team selection and generated provisioning profiles remain
local to the developer Mac. No team identifier, certificate, profile, device
identifier, or credential is committed.

## Known limitations and next milestone

0.5 synchronization is manually triggered from **Parent → Family sync →
Refresh now**. Both physical devices required manual refresh during validation.

The recommended next milestone is Automatic Sync 0.6:

- foreground refresh with single-flight/cancellation behavior;
- connectivity-restored queue retry;
- safe background-compatible CloudKit change delivery;
- calm, nontechnical freshness/status UI;
- live revoked-share, account-change, and extended-offline validation;
- additional iPad accessibility and multitasking exercise.

No production CloudKit schema was deployed, no release was created, and no
App Store Connect resource was changed.
