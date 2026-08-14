# Build 21 — App Store Readiness and Data Controls

Build 21 gives parents a single protected **Data and privacy** area for backup
status, recovery status, privacy boundaries, and local household removal.

## Verified private backups

Before the Files export sheet opens, kyndyn decodes and validates the generated
document, computes a SHA-256 fingerprint in memory, and shows verified record
counts. The fingerprint and household content are not logged. Backups include
the supported household, profiles, quests, completion and undo history, reward
goals, shared settings, collection identity, starting XP, badges, and family
announcements. Device-only authentication, notification, calendar, weather,
selection, CloudKit, and token data remain excluded.

Earlier version-1 backup documents that do not contain announcements remain
valid; their announcement collection is treated as empty.

## Remove from this device

Local removal is available only after this device records a successful private
backup export within the last 24 hours. The parent must then type the household
name exactly. The operation removes household-scoped SwiftData, reminders,
import receipts, queued mutations, record metadata, conflicts, and local device
selection in one transaction.

This action intentionally does **not** enqueue tombstones, delete CloudKit
records, stop sharing, remove participants, or deploy/change a CloudKit schema.
A cloud-backed household can therefore be recovered later from iCloud. A
local-only household depends on the exported file.

## Accessibility and release boundary

Backup verification, typed confirmation, and the destructive action have
explicit accessibility identifiers and plain-language labels. The screens use
native Form/List semantics and Dynamic Type rather than fixed text sizes.

Code and deterministic tests can validate serialization and deletion policy.
App Store privacy labels, public privacy/support URLs, external accessibility
testing, and any decision to stop sharing or delete cloud data remain explicit
release-owner actions outside this build.
