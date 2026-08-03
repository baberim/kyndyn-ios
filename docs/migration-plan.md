# PWA migration plan

## Implemented in 0.7

kyndyn accepts a single privacy-filtered `rowan-pwa-transfer` JSON document on
an empty installation. It dry-runs before writing, deterministically maps legacy
string or numeric IDs to UUIDs, preserves valid awarded XP and active/undone
completion history, records an import receipt, and queues imported shared
records through the established sync layer.

Supported core data includes household name/time zone, profiles, colors,
compatible companions, active/archived quests, assignments, individual/shared
completion mode, one-time/daily/weekday/weekly/scheduled recurrence, due dates,
completion history, and family reward/target.

Claim-once and unknown recurrence rules are reported as unsupported. Invalid
relationships, dates, XP, duplicate events, and text are itemized in the dry-run
report. Only `household_name` and `timezone` are decoded from legacy settings.
PINs, sessions, push subscriptions, calendars, weather, AI history, secrets,
credentials, device information, logs, and backups are excluded. Unsupported
product areas remain preserved in the untouched original export.

### Private Railway export procedure

Do not send runtime files to Codex or add them to either repository.

1. In Railway, privately download `family.json`, `people.json`, `quests.json`,
   `completion_history.json`, and `settings.json`.
2. Keep those originals unchanged in a private folder outside Git.
3. Create one `rowan-transfer.json` object with `format` set to
   `rowan-pwa-transfer`, `version` set to `1`, and parsed contents under
   `family`, `people`, `quests`, `completion_history`, and `settings`.
4. Remove every settings key except `household_name` and `timezone`.
5. AirDrop or save the file to a private Files location on the owner device. Do
   not email, commit, attach, log, or screenshot it.
6. On an empty kyndyn installation choose **Restore or migrate a household**,
   authenticate, select it, and review every dry-run count and note.
7. Import only after the report is understood. Immediately export a native
   kyndyn backup from **Backup and migration**.

No live Rowan runtime was accessed. The real download and conversion remain a
separate user-authorized migration operation.

From the private directory containing the five files, the conversion can be
performed locally with `jq`:

```sh
jq -n \
  --slurpfile family family.json \
  --slurpfile people people.json \
  --slurpfile quests quests.json \
  --slurpfile history completion_history.json \
  --slurpfile settings settings.json \
  '{
    format: "rowan-pwa-transfer",
    version: 1,
    family: $family[0],
    people: $people[0],
    quests: $quests[0],
    completion_history: $history[0],
    settings: {
      household_name: $settings[0].household_name,
      timezone: $settings[0].timezone
    }
  }' > rowan-transfer.json
```

Open the resulting file privately and confirm it contains no PIN, calendar,
weather, push, session, credential, device, log, backup, or assistant fields
before moving it to the device.

## Format

`rowan-transfer.json` is a user-initiated UTF-8 JSON document with `format`,
`version`, `family`, `people`, `quests`, `completion_history`, and the approved
settings subset. It excludes secrets, calendar feed URLs, push subscriptions,
weather caches, backups, PIN hashes, and device identifiers.

## Workflow

1. Select an export through the system file importer.
2. Decode into untrusted transfer objects.
3. Validate version, sizes, UUIDs, dates, time zone, XP bounds, relationships, and safe text lengths.
4. Produce a dry-run report: accepted, normalized, skipped duplicate, and invalid records.
5. Require explicit parent confirmation.
6. Insert the accepted result transactionally into an empty installation without
   altering the export.

Stable source IDs map deterministically to native UUIDs and are recorded in import receipts, making retries idempotent. Name/title matching is never used as the sole duplicate key. Invalid records do not block unrelated valid records. Import is additive and never deletes native data.

Sanitized fixtures cover numeric IDs, unknown participants, malformed dates,
duplicate events, undone events, unsupported claim-once/recurrence, archived
quests, and daylight-saving boundaries.
