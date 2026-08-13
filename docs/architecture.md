# Architecture

## Platform

Swift 6, SwiftUI, structured concurrency, SwiftData, App Intents, CloudKit,
EventKit, Core Location, WeatherKit, UserNotifications, and LocalAuthentication.
The deployment target is iOS/iPadOS 18 or later. Layouts respond to available
container width rather than device names.

## Source boundaries

- `DomainModels.swift` — SwiftData source entities, device settings, sync
  metadata, mutation queue, conflicts, invitation state, and schema version.
- `ProgressionEngine.swift` — pure recurrence, occurrence identity, due state,
  XP, level, streak, family progress, and weekly-insight projections.
- `QuestPlanning.swift` — templates, two-week planning, recurrence validation,
  and safe repair proposals.
- `Collections.swift` — deterministic badges, companion/background catalogs,
  unlock rules, and profile scene composition.
- `AppModel.swift` — main-actor application orchestration and transactional
  local writes.
- `SyncEngine.swift` — CloudKit-independent records/transports, merge rules,
  provisioning, incremental sync, notification triggers, retry/backoff, and the
  automatic synchronization coordinator.
- `Services.swift` — authentication, Keychain, notifications, CloudKit sharing
  UI, read-only calendars, one-shot location, and WeatherKit.
- `SystemIntelligence.swift` — App Intents and Shortcuts adapters that reuse
  existing local domain operations.
- `HouseholdTransfer.swift` — validated import, backup, restore, dry-run reports,
  deterministic legacy IDs, and import receipts.
- `DesignSystem.swift` and `Views.swift` — reusable visual components and
  presentation. Views request actions; they do not own sync or progression
  policy.
- `AppConfiguration.swift` — validates centralized Apple capability/container
  settings before live services are created.
- `kyndynApp.swift` — model-container startup, recovery UI, app/scene lifecycle,
  share routing, and background-compatible sync entry points.

## Persistence and derived truth

Every shared entity has a stable UUID and household UUID. Archivable records use
soft deletion. A `QuestCompletion` is an append-friendly event; `reversedAt`
represents exact undo. Duplicate event UUIDs cannot award XP twice.

Completion history is truth. XP, levels, streaks, badges, weekly insights, and
reward progress are recalculated. Starting XP contributes only to current
XP/level. Device settings and caches do not contaminate progression.

The current SwiftData schema is additive and includes household, person, quest,
completion, reward, broadcast, companion/background, settings, CloudKit state,
record metadata, pending mutations, conflicts, invitations, and import receipts.
kyndyn never silently erases a store after initialization or migration failure;
startup presents a recovery surface instead.

## Synchronization

SwiftData is the immediate local source and does not use SwiftData's automatic
CloudKit store. `HouseholdCloudTransport` isolates Apple types from domain and
view code. The owner's records live in a private custom zone shared from the
root household through `CKShare`; participants route through the owner-qualified
shared zone.

`CloudSyncController`, merge/application services, and the automatic coordinator
provide resumable provisioning, persisted offline mutations, idempotent upload,
change-token fetches, deterministic conflict handling, single-flight execution,
trigger coalescing, debounce, bounded retry/backoff, foreground/relaunch catch-up,
and best-effort background refresh. Deterministic tests use an actor-backed
in-memory transport. Manual refresh remains a recovery and diagnostic action.

## Local Apple services

- Calendar is read-only through EventKit and never synchronized.
- Weather uses one-shot location, WeatherKit, and a replaceable local cache.
- Quest reminders and broadcast alerts are local notifications. CloudKit remote
  notifications are private sync hints, not user-facing payloads.
- App Intents read/write through the same SwiftData operations and sync queue as
  the app. They do not calculate progression or call CloudKit independently.
- App-icon choice, notification configuration, active device profile, calendar
  choices, location, weather cache, and view preferences remain local.

## Authentication

Every Parent entry is gated by `ParentAccessController`. LocalAuthentication
uses Face ID, Touch ID, or device passcode. The optional kyndyn PIN is salted,
iteratively hashed, and stored as a `WhenUnlockedThisDeviceOnly` Keychain item.
Secrets and unlock state never enter SwiftData or CloudKit.

## Adaptive UI

- Cap readable management content without turning iPad into a stretched phone.
- Use adaptive grids, `ViewThatFits`, wrapping text, and 44-point actions.
- Treat Split View, landscape, Dynamic Type, VoiceOver, dark mode, Reduce Motion,
  and compact windows as first-class constraints.
- Names and companions carry identity; profile color supplements them and is
  never the sole cue.
