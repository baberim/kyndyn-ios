# PWA migration plan

## Format

`kyndyn-export-v1.json` is a user-initiated, UTF-8 JSON document with `formatVersion`, `exportedAt`, `source`, `household`, `people`, `quests`, and `completionEvents`. It must exclude secrets, calendar feed URLs, push subscriptions, weather caches, backups, PIN hashes, and device identifiers.

## Workflow

1. Select an export through the system file importer.
2. Decode into untrusted transfer objects.
3. Validate version, sizes, UUIDs, dates, time zone, XP bounds, relationships, and safe text lengths.
4. Produce a dry-run report: accepted, normalized, skipped duplicate, and invalid records.
5. Require explicit parent confirmation.
6. Insert in one transaction without altering the export or existing records.

Stable source IDs map deterministically to native UUIDs and are recorded in import receipts, making retries idempotent. Name/title matching is never used as the sole duplicate key. Invalid records do not block unrelated valid records. Import is additive and never deletes native data.

Sanitized fixtures must cover legacy numeric IDs, unknown participants, malformed dates, duplicate events, unsupported claim-once quests, and daylight-saving boundaries.

