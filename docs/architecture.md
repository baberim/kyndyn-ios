# Architecture

## Platform

Swift 6, SwiftUI, Swift concurrency, SwiftData, iOS/iPadOS 18+. The app is iPhone-first and uses adaptive navigation and grids on iPad.

## Boundaries

- `DomainModels.swift`: persisted source entities and explicit schema version.
- `ProgressionEngine.swift`: pure recurrence, due-date, completion, XP, level, streak, and family progress projections.
- `AppModel.swift`: main-actor application orchestration and SwiftData writes.
- `Services.swift`: protocols and local development substitutes for household sync, notifications, entitlements, and import.
- `Views.swift`: presentation only.

## Data principles

Every entity uses a UUID. Household-owned entities retain their household UUID. Deletable records use `deletedAt` rather than immediate destruction. A completion is an append-friendly event whose `reversedAt` records undo. Derived XP, levels, streaks, and family progress are recalculated from active events.

The schema version is currently `1`. Household time zones are stored as IANA identifiers. Device-only settings remain separate from shared household settings.

## CloudKit direction

SwiftData is the local source for the current milestone. `HouseholdSyncing` isolates future CloudKit sharing. Production CloudKit should use a private database plus shared zones, stable record names derived from UUIDs, tombstones/soft deletion, and idempotent merge rules. No generic Rowan-hosted family database is introduced.

## Entitlements and notifications

`EntitlementProviding` defaults to a free local entitlement. `NotificationScheduling` defaults to a no-op implementation. StoreKit 2 and `UNUserNotificationCenter` implementations can replace these without changing domain rules.

