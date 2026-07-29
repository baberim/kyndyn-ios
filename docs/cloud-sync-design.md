# kyndyn Cloud Sync 0.3 design

## Scope and Apple configuration boundary

Cloud Sync is optional. A Local Core household stays fully usable until an
authenticated parent explicitly enables family sync. Production use requires an
Apple Developer team and an iCloud container selected by the project owner.
kyndyn does not contain a guessed container identifier and this milestone does
not deploy a development or production schema.

The app target will require the iCloud/CloudKit capability before live testing.
In Xcode, select **kyndyn → Signing & Capabilities**, choose the authorized team,
add **iCloud**, enable **CloudKit**, and select an owner-created container such
as the final value of `iCloud.<authorized bundle identifier>`. Do not select a
container belonging to another app. Test in the Development environment first.
Only the project owner should later deploy the schema in CloudKit Dashboard.

## Ownership and record layout

The household owner creates one custom zone in the private database. A
`Household` root record anchors a `CKShare`; participants read and write the
shared zone through their shared database. kyndyn never treats share membership
as proof of parent status. Device-local kyndyn authentication still gates every
parent mutation.

Stable record names are `<type>-<lowercase UUID>`. Relationships use record
references where CloudKit supports them and the same stable UUID values in the
portable sync envelope.

| kyndyn data | Cloud record | Notes |
| --- | --- | --- |
| Household | `kyndynHousehold` | Root; name, time zone, schema version, archive date |
| Person | `kyndynPerson` | Household reference, role, color, companion, archive date |
| Quest | `kyndynQuest` | Text, XP, assignees, completion mode, archive date |
| Quest schedule | `kyndynQuestSchedule` | One-to-one with quest; recurrence, weekdays, start/deadline |
| QuestCompletion | `kyndynQuestCompletion` | Append-friendly UUID event; reversal is an explicit update |
| RewardGoal | `kyndynRewardGoal` | Goal text/target and archive date |
| HouseholdSettings | `kyndynHouseholdSettings` | Shared household policy only |

Companion selection may sync as part of `Person`; companion assets do not.
`FamilyBroadcast`, weather, calendar, StoreKit, and assistant data are outside
this milestone.

## Device-local boundary

These values never enter shared records: kyndyn PIN or hash, authentication and
biometric state, notification authorization, device/profile targeting, quiet
hour overrides, scheduled notification identifiers, view preferences,
onboarding presentation, caches, CloudKit credentials, and change tokens.

## Local metadata and queue

Schema 3 adds separate `HouseholdCloudState`, `SyncRecordMetadata`,
`PendingSyncMutation`, `SyncConflict`, and `PendingShareInvitation` models.
Keeping metadata separate prevents sync state from affecting progression rules
and permits an additive migration from schema 2.

Local mutations commit to SwiftData first and then enqueue an idempotent
operation identified by a mutation UUID. A queue item contains only entity
identity, operation, timestamps, retry/error metadata, and a privacy-safe
payload. Confirmed uploads update metadata and remove the queue item. A failed
upload never rolls back or deletes the local edit.

## Incremental synchronization

Each household stores its private or shared database scope, zone name, opaque
server change token, last successful sync time, and account fingerprint.
Foreground and manual refresh run the same structured `SyncCoordinator`:

1. verify account identity and household mode;
2. push pending mutations in deterministic order;
3. fetch changes after the saved token;
4. merge records in one local transaction;
5. save the new token only after the merge succeeds;
6. refresh local notification schedules when people or quests changed.

A stale token clears only the token and performs a full zone fetch. It never
clears household data. Retryable errors use capped exponential backoff with
deterministic jitter supplied by the coordinator; permanent errors become
user-attention states.

## Conflict policy

- Completion UUIDs are set-union events. Duplicate delivery has no effect.
- Reversal uses the same completion UUID and the earliest confirmed
  `reversedAt`; derived XP is always recalculated locally.
- Archives win over edits until a parent explicitly restores the entity.
- Different fields merge independently using per-field mutation stamps carried
  in the payload.
- For simultaneous writes to the same field, server sequence then lexical
  mutation UUID is the deterministic tie-breaker; device time is only advisory.
- Same-field destructive ambiguity creates a privacy-safe `SyncConflict` for
  parent review instead of discarding either value.
- Derived XP, levels, streaks, goal totals, and notification identifiers never
  sync.

## Provisioning and invitations

Provisioning is a resumable state machine: account check, zone, root, initial
upload, share, and round-trip verification. Each step is persisted. Repeating a
step adopts the same deterministic zone and record names rather than creating
duplicates.

Share acceptance is routed before onboarding. A pending invitation suppresses
sample-household creation until kyndyn validates the schema and imports the
shared root. States distinguish malformed, expired/revoked, unsupported,
already accepted, and successful invitations. `CKShare` and the system sharing
experience remain the transport; kyndyn does not send custom invitation email.

CloudKit sharing depends on each participant's Apple ID, iCloud availability,
parental controls, and account restrictions. A child's Apple family membership
does not automatically grant kyndyn access or Parent-area privileges.

## Account and access changes

kyndyn distinguishes offline, not signed in, restricted, account changed, access
revoked, and generic sync failure. It never merges households across account
fingerprints or uploads after an account change without confirmation. Local
readable data remains available where ownership permits, while uploads pause.
Recovery guidance prioritizes retry and future export; there is no destructive
reset shortcut.

## Privacy-safe diagnostics

Development diagnostics may include operation category, record type, retry
count, database scope, and redacted error category. Logs must never contain
names, quest titles, payloads, invitation URLs, change tokens, PIN material,
Apple credentials, or full CloudKit records.
