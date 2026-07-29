# Rowan for iOS

Rowan is a calm, local-first family app for turning everyday responsibilities into quests, visible progress, and shared celebration.

This repository is a new native SwiftUI implementation. It is independent from the Rowan PWA and contains no household runtime data.

## Current milestone

The app provides a locally usable vertical slice:

- first-launch sample-household onboarding using fictional profiles;
- family and personal dashboards;
- today's individual and shared quests;
- completion and undo backed by append-friendly completion records;
- derived XP, levels, streaks, and family-goal progress;
- a parent area for adding people and basic quests;
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
xcodebuild test -project Rowan.xcodeproj -scheme Rowan -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

See `docs/` for product scope, architecture, parity, migration, privacy, asset provenance, and App Store work.

