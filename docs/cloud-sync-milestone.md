# Cloud Sync 0.3 validation

## Genuinely implemented

- Local-only households remain the default and do not create queue entries.
- Schema 3 adds separate cloud state, record metadata, pending mutations,
  conflicts, and pending invitations without changing progression truth.
- People, quests, schedules, completions, rewards, and household settings have
  stable CloudKit identities and privacy-filtered envelopes.
- Local cloud-enabled edits save first and queue idempotent uploads.
- Owner provisioning persists each step and safely resumes.
- The transport boundary includes account checks, custom zones, incremental
  changes, record upload, `CKShare`, acceptance, and participant summaries.
- System share acceptance routes through the app delegate before onboarding.
- Incremental sync pushes pending writes, recovers stale tokens with a full zone
  fetch, applies remote core records, and refreshes local reminders.
- Duplicate completion UUIDs do not duplicate XP; reversal converges by the same
  event identity.
- Account changes and revoked/permanent errors pause instead of uploading.

## Automated validation

On July 29, 2026, Xcode 26.5 and the iOS 26.5 simulator completed:

- clean simulator build;
- 36 unit tests;
- 5 UI tests;
- 41 total tests with zero failures.

The sync tests use deterministic substitutes for account state, zones, uploads,
downloads, shares, invitations, failures, and reordered delivery. They cover
additive migration, local-only behavior, provisioning and interruption,
duplicate provisioning, offline queue/backoff, permanent errors, account
change, stale tokens, invitation validation, conflict rules, archive precedence,
duplicate events, cross-device undo convergence, privacy exclusions, and
notification rescheduling.

The additional upgrade regression verifies that a household missing its
device-local settings row receives safe default reminder settings instead of a
dead-end “Settings unavailable” screen.

Targeted Family Sync UI journeys also passed on:

- iPhone 17e, iOS 26.5, dark mode, Accessibility Extra Extra Large text;
- iPad Pro 11-inch (M5), iOS 26.5, light mode, default text.

## Not validated as live CloudKit

No Apple Developer team, iCloud container entitlement, or
`kyndynCloudSyncConfigured` flag was configured. Therefore no live CloudKit
record, zone, share, invitation, account-change, or multi-device operation was
claimed or performed. No physical-device validation occurred. The production
adapter compiled, but the deterministic in-memory transport supplied behavioral
validation.

A human VoiceOver listening/order audit was not performed. Critical sync status
and invitation controls have explicit labels, hints, status text, and stable
automation identifiers, and the UI tests verified their reachability.

Follow [`cloudkit-configuration.md`](cloudkit-configuration.md) for the exact
credential-dependent physical-device checklist. Production schema deployment
remains explicitly out of scope.
