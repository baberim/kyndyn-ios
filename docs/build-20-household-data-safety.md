# Build 20 — Household Data Safety

Build 20 makes iCloud recovery a deliberate, verifiable operation instead of
an opaque restore button. It does not delete an existing local household and it
does not change Production CloudKit data.

## Recovery behavior

- Recovery is offered only on an empty installation.
- Every page of the household's CloudKit history is fetched before a candidate
  is presented.
- Repeated revisions of the same CloudKit record are collapsed
  deterministically, with the newest fetched revision winning.
- Before insertion, Kyndyn validates the household root, supported schema,
  active parent, record limits, quest assignments, schedules, completion
  relationships, starting XP, awarded XP, and undone history.
- The parent sees a preview of profiles, quests, completion history, starting
  XP, and active completion XP before confirming.
- An unsafe or incomplete candidate cannot be recovered.
- Recovery is transactional: validation or insertion failure rolls the empty
  local store back rather than leaving a partial family.
- A privacy-safe receipt records the recovered household identifier,
  fingerprint, counts, and recovery time. It contains no names or quest titles.
- The final CloudKit change token is retained so normal incremental sync resumes
  from the completed recovery rather than beginning from an ambiguous page.

## Private backup visibility

The Backup & transfer screen now shows when this device last completed a private
backup export. It also shows the last successful iCloud recovery receipt. The
timestamp is device-local and is updated only after the system confirms a file
was exported successfully.

## Privacy boundary

Recovery diagnostics never log household names, person names, quest titles,
record payloads, invitation URLs, credentials, tokens, PINs, or authentication
state. Device-local security, notification, calendar, weather, and presentation
settings remain outside shared household records.

## Validation boundary

Automated tests use fictional records and an in-memory CloudKit substitute.
Debug builds use Development CloudKit; TestFlight Release builds use Production
CloudKit. A real Production recovery must therefore be validated through
TestFlight on an empty installation, with a private backup retained first.
