# kyndyn for iOS

kyndyn is a calm, local-first family app for turning everyday responsibilities into quests, visible progress, and shared celebration.

This repository is a new native SwiftUI implementation. It is independent from the kyndyn PWA and contains no household runtime data.

## Release status — November 10, 2026

**Kyndyn 1.0 (build 39)** is on internal TestFlight and selected in App Store
Connect. It is prepared for submission, but has not been sent to App Review.
Manual release remains selected. The store description and reviewer notes have
been updated for build 39.

Latest recorded validation: 117 unit tests passed on iOS 27.2, all 22 iPhone
and 22 iPad UI cases passed across separate runs, and all 23 notification tests
and typechecking passed. Full-display captures confirmed the iPad Premium
landscape layout. Still pending: physical-device TestFlight purchase, cancellation,
restore and entitlement persistence; Production CloudKit sharing and sync;
spoken Siri and lock-screen privacy; and final store media/privacy verification.

Build 39 uses native StoreKit product controls. The annual plan offers a two-week
trial to eligible subscribers; monthly has no trial. Premium expands planning,
insights, personalization, weather and calendar views. Core quests, progress,
rewards, security, household sync and recovery stay free.

See the [roadmap](docs/app-store-roadmap.md). These release notes describe the
TestFlight candidate; the public source branch is not yet synchronized to build 39.

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
- an Apple-compliant native app icon and 11 device-local alternate choices;
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
- a weekly parent planner with transactional bulk quest creation and safe day
  copying through the same validated schedule and sync paths as single quests;
- a synchronized queue of up to five prepared rewards with explicit ordering,
  parent notes, and carry-or-reset activation that preserves profile progress;
- a reusable native visual system with adaptive light/dark surfaces, consistent
  quest states, and balanced Home presentation;
- full-card completion and exact undo with deterministic occurrence identity,
  immediate XP feedback, and recent family activity;
- device-local per-quest reminder timing that respects completion state, quiet
  hours, archive state, and the household time zone.
- a durable, synchronized badge gallery with visible progress toward quest,
  streak, quest-XP, and family-reward milestones;
- named badge celebrations, visible collection milestones, and quiet badge
  counts on Profiles without rankings or behavioral scoring;
- optional device-local calendar and Apple Weather context with two-week event
  and ten-day forecast sheets, plus separate permission controls in Settings;
- a simplified Quests browser with one stable profile scope control and one
  compact status filter instead of competing rows of buttons;
- a centered Profiles experience, consistent Profiles terminology, and a
  portrait-first iPhone layout while iPad remains fully adaptive;
- a softer immersive Home header, clear pull-to-refresh feedback, and the
  approved K brand mark replacing remaining generic leaf symbols.
- a dark-mode-aware startup surface, consistent Home spacing, cached collection
  artwork, and event-driven sync waiting that keeps navigation responsive.

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
See [`docs/badge-recognition.md`](docs/badge-recognition.md) for Builds 16–17
recognition rules and persistence behavior.
See [`docs/build-15-weekly-insights.md`](docs/build-15-weekly-insights.md) for
the protected weekly overview and deterministic trend rules.
See [`docs/calendar-weather.md`](docs/calendar-weather.md) for Build 18’s
device-local calendar and weather privacy boundary.
See
[`docs/build-27-hosted-notifications.md`](docs/build-27-hosted-notifications.md)
for secure owner enrollment, one-time device pairing, APNs family-announcement
delivery, opt-out behavior, and the service privacy boundary.
See [`docs/build-29-release-candidate.md`](docs/build-29-release-candidate.md)
for the consolidated validation results and TestFlight handoff.
See [`docs/build-32-premium-foundation.md`](docs/build-32-premium-foundation.md)
for pricing, free and premium boundaries, and entitlement lifecycle rules.
See [`docs/build-33-storekit.md`](docs/build-33-storekit.md) for StoreKit 2
behavior and the local/App Store Connect configuration boundary.
See [`docs/build-34-premium-discovery.md`](docs/build-34-premium-discovery.md)
for Premium placement and customer-language rules.
See [`docs/build-35-premium-access.md`](docs/build-35-premium-access.md) for
the first enforced feature boundaries and expiration-safe access rules.
See [`docs/build-24-personalization-settings.md`](docs/build-24-personalization-settings.md)
for the separated App color, Companion, Background, and App icon settings.
See [`docs/build-20-household-data-safety.md`](docs/build-20-household-data-safety.md),
[`docs/build-21-app-store-readiness.md`](docs/build-21-app-store-readiness.md),
and [`docs/build-22-release-candidate.md`](docs/build-22-release-candidate.md)
for the current household-data and release-safety gates.
