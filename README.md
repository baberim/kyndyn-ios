# kyndyn for iOS

kyndyn is a calm, local-first family app for turning everyday responsibilities into quests, visible progress, and shared celebration.

This repository is a new native SwiftUI implementation. It is independent from the kyndyn PWA and contains no household runtime data.

## Current milestone — Build 16 Badge Recognition and UI polish

The app provides a locally usable vertical slice:

- first-launch sample-household onboarding using fictional profiles;
- family and personal dashboards;
- today's individual and shared quests;
- completion and undo backed by append-friendly completion records;
- derived XP, levels, streaks, and family-goal progress;
- LocalAuthentication-protected parent tools with an optional device-only kyndyn PIN;
- complete create/edit/archive/restore flows for people and quests;
- one-time, daily, and selected-weekday schedules with household-local deadlines;
- private, device-local quest reminders with quiet hours and profile targeting;
- local SwiftData persistence and offline operation;
- protocol boundaries for sync, notifications, entitlements, and import.
- optional local-only or CloudKit household modes;
- additive offline mutation queues and conflict-safe merge rules;
- resumable owner provisioning and CloudKit share invitation routing;
- deterministic in-memory multi-device tests that do not require Apple credentials.
- centralized, fail-safe Apple/CloudKit configuration readiness;
- live Development CloudKit owner provisioning and private sharing through
  Apple’s system interface;
- scene-aware invitation routing on fresh, running, and backgrounded installs;
- verified owner/participant completion and exact undo convergence on two
  physical devices;
- an Apple-compliant native app icon;
- responsive profile, dashboard, quest, and Parent-area presentation across
  compact and regular widths;
- visible, named profile-color accents that supplement names and companions.
- single-flight automatic synchronization after launch, foregrounding, local
  changes, connectivity recovery, CloudKit hints, and share acceptance;
- idempotent private/shared zone subscriptions and best-effort background
  refresh, with manual refresh retained as a recovery control.
- persistent person or whole-household daily views grouped into overdue, due
  today, completed today, and upcoming work;
- parent-managed family rewards with editable XP targets and a history-safe
  start-new-reward reset;
- a reusable native visual system with adaptive light/dark surfaces, consistent
  quest states, and balanced Home presentation;
- full-card completion and exact undo with deterministic occurrence identity,
  immediate XP feedback, and recent family activity;
- device-local per-quest reminder timing that respects completion state, quiet
  hours, archive state, and the household time zone.
- a durable, synchronized badge gallery with visible progress toward quest,
  streak, quest-XP, and family-reward milestones;
- a simplified Quests browser with one stable profile scope control and one
  compact status filter instead of competing rows of buttons;
- a centered Profiles experience, consistent Profiles terminology, and a
  portrait-first iPhone layout while iPad remains fully adaptive;
- a softer immersive Home header, clear pull-to-refresh feedback, and the
  approved K brand mark replacing remaining generic leaf symbols.

## Open and run

Requirements: Xcode 26 or later and iOS 18 or later.

1. Open `kyndyn.xcodeproj`.
2. Select the `kyndyn` scheme and an iPhone or iPad simulator.
3. Build and run.

No Apple Developer account, CloudKit container, server, or secret is needed for
local-only development and deterministic tests. Live Debug synchronization uses
the authorized Development container documented in
[`docs/cloudkit-configuration.md`](docs/cloudkit-configuration.md). Release
archives use the authorized Production CloudKit container while Debug builds
use Development.

The complete native identity was renamed for this milestone. Because the bundle
identifier changed, iOS treats this as a new development app; see
[`docs/kyndyn-rebrand.md`](docs/kyndyn-rebrand.md).

## Tests

Run the `kyndynTests` and `kyndynUITests` targets with Product → Test, or:

```sh
xcodebuild test -project kyndyn.xcodeproj -scheme kyndyn -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The simulator can approve or reject notification permission. For LocalAuthentication, use **Features → Face ID** in Simulator to toggle enrollment and matching. A device passcode prompt may appear instead depending on simulator state.

See [`docs/daily-family-use-0.8.md`](docs/daily-family-use-0.8.md) for the daily
workflow, local reminder boundary, TestFlight notes, and validation checklist.
See [`docs/badge-recognition.md`](docs/badge-recognition.md) for Build 16’s
recognition rules and persistence behavior.
