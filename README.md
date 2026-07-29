# Rowan for iOS

Rowan is a calm, local-first family app for turning everyday responsibilities into quests, visible progress, and shared celebration.

This repository is a new native SwiftUI implementation. It is independent from the Rowan PWA and contains no household runtime data.

## Current milestone — Cloud Sync 0.3 foundation

The app provides a locally usable vertical slice:

- first-launch sample-household onboarding using fictional profiles;
- family and personal dashboards;
- today's individual and shared quests;
- completion and undo backed by append-friendly completion records;
- derived XP, levels, streaks, and family-goal progress;
- LocalAuthentication-protected parent tools with an optional device-only Rowan PIN;
- complete create/edit/archive/restore flows for people and quests;
- one-time, daily, and selected-weekday schedules with household-local deadlines;
- private, device-local quest reminders with quiet hours and profile targeting;
- local SwiftData persistence and offline operation;
- protocol boundaries for sync, notifications, entitlements, and import.
- optional local-only or CloudKit household modes;
- additive offline mutation queues and conflict-safe merge rules;
- resumable owner provisioning and CloudKit share invitation routing;
- deterministic in-memory multi-device tests that do not require Apple credentials.

## Open and run

Requirements: Xcode 26 or later and iOS 18 or later.

1. Open `Rowan.xcodeproj`.
2. Select the `Rowan` scheme and an iPhone or iPad simulator.
3. Build and run.

No Apple Developer account, CloudKit container, server, or secret is needed for local development.
Live CloudKit is deliberately disabled until the project owner completes
[`docs/cloudkit-configuration.md`](docs/cloudkit-configuration.md).

## Tests

Run the `RowanTests` and `RowanUITests` targets with Product → Test, or:

```sh
xcodebuild test -project Rowan.xcodeproj -scheme Rowan -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The simulator can approve or reject notification permission. For LocalAuthentication, use **Features → Face ID** in Simulator to toggle enrollment and matching. A device passcode prompt may appear instead depending on simulator state.

See `docs/` for architecture, lifecycle and schedule semantics, privacy, migration, accessibility, asset provenance, and App Store work.
