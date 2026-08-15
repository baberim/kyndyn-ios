# Build 22 — Release Candidate Hardening

Build 22 is version `0.22.0 (22)`. It turns release readiness into a visible,
protected check rather than an undocumented assumption.

## Household safety check

Parents can open **Parent → Data and privacy → Run safety check**. The check is
read-only and reports only aggregate state. It verifies:

- at least one active parent profile exists;
- active quests reference active profiles;
- completion events still reference known profiles and quests;
- unresolved sync conflicts are visible;
- repeatedly failing queued mutations are surfaced;
- account-changed, unavailable-iCloud, and needs-attention states are not
  presented as healthy;
- a private backup has been exported on this device within seven days.

The report never includes names, quest or announcement text, record IDs,
account fingerprints, tokens, invitation data, or CloudKit payloads. Running it
does not modify records, trigger synchronization, or contact Apple services.

## Automated coverage

- A malformed fictional household produces actionable, content-free findings.
- A healthy fictional local household with a fresh backup reports ready.
- The protected Parent UI can run and display the aggregate check.
- Existing deterministic account-change, revoked-access, offline retry,
  recovery-integrity, and notification-rescheduling coverage remains in place.

## Physical release checklist

The following still requires signed TestFlight builds and real Apple devices:

1. Owner and participant automatic foreground synchronization.
2. Offline edits followed by network restoration.
3. Termination with queued work followed by relaunch.
4. Invitation launch, participant removal, and share revocation.
5. Empty-install iCloud recovery with XP and level convergence.
6. Reminder and announcement privacy on locked devices.
7. VoiceOver, larger Dynamic Type, light/dark mode, iPhone, iPad, and Mac
   presentation.

No Production CloudKit data or schema is changed by this build.
