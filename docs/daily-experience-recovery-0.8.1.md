# Daily Experience and Recovery 0.8.1

Build 4 closes the most visible daily-use and reinstall-recovery gaps between
native Kyndyn and the Rowan PWA while preserving the native offline-first and
CloudKit ownership model.

## Recovery contract

- Recovery is offered only on an empty native installation.
- Kyndyn queries the signed-in account's private and shared CloudKit databases
  for dedicated Kyndyn household zones.
- A candidate must contain a supported, active household root record.
- The user sees the household name and whether it is hosted by or shared with
  the current iCloud account before choosing it.
- Applying a candidate is transactional. Failure rolls back local insertion and
  never deletes or replaces CloudKit records.
- Kyndyn does not infer identity from a person's name, create a replacement
  household, or upload during discovery.

## Daily experience

- Full quest browsing adds status counts, search, details, assignment and
  schedule information, and event-based completion history.
- The Parent landing screen adds today's actionable counts, reward progress,
  quick actions, family-sync status, and exact app version/build information.
- The active profile may choose from the current starter colors and companions.
  Names, roles, permissions, and administrative fields remain parent-managed.
- Progress details explain that completion events are XP truth and show recent
  awarded XP without storing derived counters.

## Privacy

Cloud discovery returns only Kyndyn schema metadata and records already
available to the signed-in iCloud account. Ordinary UI never displays record
IDs, zone names, tokens, Apple errors, or private record payloads. Existing
device-local PIN, biometric, reminder, quiet-hours, and view-preference
boundaries remain unchanged.
