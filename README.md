# kyndyn for iPhone and iPad

kyndyn is a calm, privacy-minded family app that turns everyday responsibilities into quests, visible progress, and shared celebration. It is built natively with SwiftUI and SwiftData, works offline, and can optionally synchronize a household through the family owner's iCloud account.

## Current release

The current feature set is packaged as **kyndyn 0.15.0 (Build 15)** and includes:

- guided family setup, profile selection, and an in-app setup guide;
- personal and whole-family Home views with companions, backgrounds, weather,
  upcoming calendar events, progress, rewards, and daily quests;
- parent-managed people, quests, templates, schedule overview, recurrence
  validation, archive/restore, reminders, and family broadcasts;
- one-time, daily, weekly, selected-weekday, and every-other-week scheduling;
- exact-occurrence completion and undo, XP, levels, streaks, badges, starting-XP
  adjustments, and family reward goals;
- offline SwiftData persistence, encrypted local parent authentication, private
  backups, restore, and a validated legacy-household import path;
- optional owner-hosted CloudKit sharing with invitations, automatic foreground
  synchronization, offline mutation queues, conflict-safe convergence, and
  manual refresh/recovery controls;
- profile colors, a complete companion/background collection, parent grants,
  alternate app icons, adaptive light/dark UI, and iPhone/iPad layouts;
- App Shortcuts foundations, read-only device calendar access, device-local
  WeatherKit conditions, and local notifications;
- protected weekly family insights with past-week navigation, daily activity,
  per-person four-week trends, and factual observations without rankings or
  behavioral profiling.

SwiftData remains the immediate presentation source. CloudKit, calendar,
weather, notifications, and Siri integrations are optional enhancements; the
core family loop remains useful offline.

## Open and run

Requirements: **Xcode 26 or later** and **iOS/iPadOS 18 or later**.

1. Open `kyndyn.xcodeproj`.
2. Select the `kyndyn` scheme and an iPhone or iPad simulator.
3. Build and run.

Local-only use and deterministic tests require no Apple Developer account or
secret. Physical-device CloudKit and WeatherKit testing requires selecting your
authorized development team and capabilities in Xcode. Personal Team IDs,
profiles, certificates, credentials, and device identifiers must not be
committed.

Debug builds use the CloudKit **Development** environment. Release archives and
TestFlight builds use **Production**. Review and deploy additive Development
schema changes before expecting a new synchronized field or record type to work
in TestFlight. See [CloudKit configuration](docs/cloudkit-configuration.md).

## Test

Run the `kyndynTests` and `kyndynUITests` targets with **Product → Test**, or:

```sh
xcodebuild test -project kyndyn.xcodeproj -scheme kyndyn \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Live Apple-service behavior must also be checked on signed physical devices.
CloudKit test doubles validate synchronization logic but do not prove live
sharing, silent delivery, WeatherKit authorization, or background execution.

## Privacy boundaries

- No advertising or third-party behavioral analytics.
- PIN material, biometric state, notification preferences, selected device
  profile, calendar data, location, weather cache, app-icon choice, and Apple
  credentials remain device-local.
- Calendar access is read-only. Weather uses one-shot location and a replaceable
  local cache; neither becomes shared household truth.
- CloudKit contains only supported shared household records after a parent
  explicitly enables family sync.
- Parent authorization inside kyndyn remains separate from iCloud share access.
- Weekly insights are calculated locally from household records and do not rank
  children or send data to an AI/analytics service.
- Repository fixtures use fictional data. Never commit exports, real household
  content, invitation links, tokens, signing material, or generated builds.

Read [Privacy and security](docs/privacy-and-security.md) for the full boundary.

## Documentation

Start with these living documents:

- [Documentation index](docs/README.md) — current guides versus historical
  milestone records.
- [App Store roadmap](docs/app-store-roadmap.md) — completed work, next options,
  and release gates.
- [Product scope](docs/product-scope.md) — product promise and safety rules.
- [Architecture](docs/architecture.md) — persistence, sync, services, and UI
  boundaries.
- [Feature parity/status](docs/pwa-parity-matrix.md) — current capability map.
- [CloudKit configuration](docs/cloudkit-configuration.md) — Development versus
  Production setup and validation.
- [Privacy and security](docs/privacy-and-security.md) — local/shared data and
  diagnostic rules.
- [Asset provenance](docs/asset-provenance.md) — approved visual assets.

Files named for earlier builds or milestones are retained as historical design
and validation records. They describe what was true at that milestone; the
living documents above describe the current app.

## Current limitations

- Apple does not guarantee immediate background CloudKit or silent-notification
  delivery. Foreground/relaunch catch-up is the reliable path; manual refresh
  remains available for recovery.
- Family broadcasts synchronize through CloudKit and can schedule local alerts,
  but guaranteed prompt delivery while the app is closed requires a future
  hosted APNs service.
- App Shortcuts are implemented, while spoken Siri invocation remains dependent
  on Apple's current OS behavior and must not be described as guaranteed.
- Badges exist in progress details; a fuller gallery and recognition experience
  is still planned.
- Durable reward-cycle history and exported weekly/monthly reports are deferred
  to the next insights phase.
- StoreKit and premium entitlements are intentionally not implemented.
