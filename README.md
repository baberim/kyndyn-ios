# Rowan for iOS

Rowan is a calm, local-first family app for turning everyday responsibilities into quests, visible progress, and shared celebration.

This repository is a new native SwiftUI implementation. It is independent from the Rowan PWA and contains no household runtime data.

## Current milestone — Local Core 0.2

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

## Open and run

Requirements: Xcode 26 or later and iOS 18 or later.

1. Open `Rowan.xcodeproj`.
2. Select the `Rowan` scheme and an iPhone or iPad simulator.
3. Build and run.

No Apple Developer account, CloudKit container, server, or secret is needed for local development.

## Tests

Run the `RowanTests` and `RowanUITests` targets with Product → Test, or:

```sh
xcodebuild test -project Rowan.xcodeproj -scheme Rowan -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The simulator can approve or reject notification permission. For LocalAuthentication, use **Features → Face ID** in Simulator to toggle enrollment and matching. A device passcode prompt may appear instead depending on simulator state.

See `docs/` for architecture, lifecycle and schedule semantics, privacy, migration, accessibility, asset provenance, and App Store work.
