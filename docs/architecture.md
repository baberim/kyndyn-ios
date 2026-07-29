# Architecture

## Platform

Swift 6, SwiftUI, Swift concurrency, SwiftData, iOS/iPadOS 18+. The app is iPhone-first and uses adaptive navigation and grids on iPad.

## Boundaries

- `DomainModels.swift`: persisted source entities and explicit schema version.
- `ProgressionEngine.swift`: pure recurrence, due-date, completion, XP, level, streak, and family progress projections.
- `AppModel.swift`: main-actor application orchestration and SwiftData writes.
- `Services.swift`: LocalAuthentication, Keychain PIN storage, UserNotifications, and protocols/test substitutes for device and future services.
- `Views.swift`: presentation only.

## Data principles

Every entity uses a UUID. Household-owned entities retain their household UUID. Deletable records use `deletedAt` rather than immediate destruction. A completion is an append-friendly event whose `reversedAt` records undo. Derived XP, levels, streaks, and family progress are recalculated from active events.

The schema version is currently `2`. Household time zones are stored as IANA identifiers. Version 2 adds defaulted, device-local reminder settings so SwiftData can perform additive lightweight migration. Rowan never silently deletes a store after initialization or migration failure; it shows a recovery screen that asks the family to preserve the installation and seek help.

## CloudKit direction

SwiftData is the local source for the current milestone. `HouseholdSyncing` isolates future CloudKit sharing. Production CloudKit should use a private database plus shared zones, stable record names derived from UUIDs, tombstones/soft deletion, and idempotent merge rules. No generic Rowan-hosted family database is introduced.

## Entitlements and notifications

`EntitlementProviding` defaults to a free local entitlement. `NotificationScheduling` is implemented with `UNUserNotificationCenter`; candidates are produced by pure `ReminderRules`. StoreKit 2 can replace the development entitlement without changing domain rules.

## Authentication

Every Parent tab entry is gated by `ParentAccessController`. LocalAuthentication uses device-owner authentication, allowing Face ID, Touch ID, or the device passcode. The optional Rowan PIN is salted with 128 random bits, iteratively SHA-256 hashed, and stored as a `WhenUnlockedThisDeviceOnly` Keychain item. Secrets and unlock state never enter SwiftData and never sync.

## Lifecycle and schedules

People and quests retain stable UUIDs and completion relationships when archived. The last active parent cannot be archived. Archived people cannot receive new assignments. `ProgressionEngine` owns occurrence keys and today/upcoming/completed/overdue classification. Edits do not recalculate historical event XP.
