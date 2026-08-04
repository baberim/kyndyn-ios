# App Store roadmap

## Build 4 — Daily Experience and Recovery 0.8.1

- Recover an existing owner-hosted or shared household from iCloud after an
  empty reinstall without creating a duplicate household.
- Add honest startup/recovery states and privacy-safe diagnostics.
- Improve quest browsing with status counts, search, details, and completion
  history.
- Turn the Parent landing screen into a useful daily snapshot with quick
  actions, reward progress, sync status, and visible version/build metadata.
- Let the active person safely choose their profile color and starter companion
  while parent-only identity and permission controls remain protected.
- Improve personal XP, level, streak, and recent-completion explanations.
- Keep launch presentation, iPad layout, dark mode, Dynamic Type, VoiceOver,
  automatic sync, and pull-to-refresh consistent.

## Build 5 — Recognition and Collections

- Native badges derived from deterministic progression.
- Durable companion collection and unlock rules.
- Background collection and profile scenes.
- Calm unlock introductions and parent-managed grants.
- No random rewards, trading, or child-directed behavioral profiling.

## Build 6 — Quest Planning Tools

- Native quest templates for common family routines.
- Schedule overview and diagnostics for recurring quests.
- Safer bulk planning and recurrence repair tools.
- Preserve completion history when schedules are edited.

## Build 7 — Family Communication

- Family broadcasts and announcements with parent controls.
- Richer parent and family summaries.
- Privacy-conscious delivery and expiration behavior.
- Keep announcements separate from synchronization notifications and quest
  reminders.

## Later

- Read-only calendar integration with explicit permission and privacy design.
- Weather as derived, replaceable cache data rather than shared source truth.
- A constrained Kyndyn Assistant only after a dedicated privacy, child-safety,
  and parent-approval review.
- StoreKit only after product entitlement and family-purchase behavior are
  intentionally designed.

## Before beta

- Complete independent security review of local parent authentication and recovery limitations.
- Configure the authorized CloudKit container, validate private/shared zones and
  invitations on physical devices, review participant permissions, and deploy
  the schema only after explicit production approval.
- Validate notification scheduling and privacy on physical devices.
- Complete the staged build 4–7 roadmap above and robust parent editors.
- Complete migration importer and sanitized fixture tests.
- Add accessibility identifiers and broaden UI coverage.

## Apple setup

Create an App ID and unique bundle identifier, enable iCloud/CloudKit and push notifications as needed, create development/production CloudKit containers, configure signing and capabilities, create an App Store Connect record, supply privacy details/screenshots, and later configure a StoreKit 2 subscription group if monetization is approved.

None of those credentials or portal changes are required for this local milestone.

## Release gates

Privacy/security review, VoiceOver and Dynamic Type audit, reduced-motion and contrast review, localization readiness, real-device offline/relaunch testing, CloudKit sharing failure tests, StoreKit sandbox tests, deletion/export flows, support URL, privacy policy, and TestFlight family testing.
