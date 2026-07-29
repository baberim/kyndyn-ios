# Real Family Pilot Readiness 0.7

## What is ready

Fresh installs offer **Set up my family** as the primary path and a visibly
fictional sample as the alternative. Personal setup creates a household,
confirms its time zone, creates the first parent, optionally saves a device-only
fallback PIN, and adds no sample records.

The protected Parent area contains **Backup and migration**. It exports a
versioned, readable JSON backup through Apple’s file workflow. The backup
contains household metadata, profiles, quests and schedules, completion events,
reward goals, shared settings, stable IDs, archive state, format version, and
export time.

It excludes PINs and hashes, Keychain content, authentication state, Apple
identity, CloudKit tokens/system fields, device IDs, notification authorization,
quiet hours, device targeting, local diagnostics, and sync retry state.

## Restore and sample boundaries

0.7 validates the whole backup before writing and restores only into an empty
installation. It does not merge with or replace an existing household. Stable
IDs and completion events are preserved. Restored shared records enter the same
offline-safe CloudKit queue when cloud sync is enabled.

Sample households carry a device-local classification that is never uploaded.
The Parent area labels sample mode. A protected action can remove a local-only
sample before personal setup. kyndyn refuses if it is connected to family
sharing and never silently deletes CloudKit records.

## Starting a small personal pilot

1. Install 0.7 on the owner device.
2. On a fresh installation choose **Set up my family**.
3. Enter the household name, verify the time zone, and create the first parent.
4. Add other profiles and a small number of quests in the Parent area.
5. Open **Backup and migration** and save the first backup.
6. Enable Family sync and invite the participant device.
7. Confirm one quest and one completion converge before adding more data.
8. Export another backup after meaningful setup changes.

Do not use a personal household for revocation, Apple-account switching, or
other destructive validation.

## Development pilot and Production migration

This build uses Apple Development CloudKit. Development data may need
replacement before public release, and Production CloudKit has not been
deployed.

CloudKit schema deployment moves schema definitions, not Development records.
Before a Production/TestFlight switch:

1. Export and retain a current household backup.
2. Validate restoration in an isolated fictional store.
3. Freeze writes during the environment transition.
4. Deploy the reviewed schema only after automated and signed-device tests.
5. Start the Production build with an empty store and import the backup once.
6. Preserve exported UUIDs and completion events.
7. Let the idempotent queue create Production records with those identities.
8. Verify counts, active XP, undone history, assignments, sharing, and
   participant convergence before resuming normal use.

The local import receipt prevents the same transfer being applied twice in one
store. Cross-store duplicate prevention requires the one-time owner-controlled
freeze and migration procedure.
