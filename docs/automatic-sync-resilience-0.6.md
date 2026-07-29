# Automatic Sync and Resilience 0.6

## Behavior

SwiftData remains the immediate presentation source. A successful local family
mutation saves locally, persists an idempotent queue item, and emits a
content-free synchronization hint. A main-actor coordinator debounces rapid
mutations for 650 milliseconds, coalesces redundant triggers, and prevents
overlapping CloudKit operations.

Synchronization is requested after:

- persistence-ready launch and every transition to active;
- a 15-second catch-up pulse while the app is visibly active;
- a successful queued local mutation;
- network connectivity returning;
- a CloudKit remote-change notification;
- CloudKit share receipt and successful acceptance;
- explicit recovery after provisioning;
- best-effort `BGAppRefreshTask` execution;
- the parent-only **Refresh now** recovery action.

The existing conflict-safe upload/download engine remains authoritative.
Completion UUIDs still prevent duplicate XP, exact-occurrence undo retains the
same event identity, and owner-private versus participant-shared routing uses
the household’s persisted database scope and shared-zone owner.

## CloudKit notification strategy

Every eligible owner household repairs one deterministic
`CKRecordZoneSubscription` in its private database. Participants repair one
`CKDatabaseSubscription` for the shared database, as required by CloudKit.
Creating the same subscription repeatedly is harmless. Both request content-
available delivery and include no names, quest titles, record fields, or
invitation data. Notifications are hints only; kyndyn always fetches changes
using its persisted zone token.

Subscription creation failure never rolls back local work or disables manual,
foreground, or relaunch synchronization.

## Retry and interruption

The durable mutation queue survives termination. The existing per-mutation
retry count and next-attempt timestamp remain the source of upload eligibility.
The coordinator adds bounded exponential scheduling for transient errors and
does not create an offline retry storm. Connectivity restoration, foreground,
and relaunch provide additional safe recovery opportunities.

When iOS expires background execution, in-memory coordination is cancelled
cleanly; the local queue and change token remain intact for the next trigger.
The app never deletes a local store or CloudKit records as recovery.

## Honest background limits

Apple does not guarantee when—or whether—a silent CloudKit notification or
background refresh will run. kyndyn therefore does not describe sync as
real-time. Ordinary foreground use automatically catches up at a bounded
interval when a notification is missed. The pulse stops entirely when the app
leaves the foreground; background delivery remains a battery-conscious
promptness improvement controlled by iOS.

The Parent status distinguishes synchronizing, up to date, offline, waiting for
Apple/network, and needs-attention states. Children do not see CloudKit
technical language.

## Privacy and environments

No device PIN, authentication state, notification permission, quiet hours,
device targeting, credentials, tokens, or notification identifiers are
uploaded. Diagnostic signals contain only trigger categories. Debug remains
configured for the authorized Development container. Release remains
fail-safe-disabled; no Production schema or data is changed by this milestone.

## Validation boundary

Coordinator coalescing, overlap prevention, subscription idempotency/failure,
queue persistence, retry behavior, stale tokens, exact-occurrence convergence,
account change, and conflict rules are deterministic automated-test subjects.
Silent notification timing and true background execution require signed
physical-device testing and must be reported separately from simulator results.
