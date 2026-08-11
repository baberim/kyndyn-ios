# Build 8 visual identity and personalization

Build 8 makes earned profile customization visible during normal family use
and introduces a device-local app icon choice.

## Personal Home

- The selected profile's background and companion form the lead Home scene.
- The greeting sits immediately beneath that scene and rotates through short,
  encouraging local messages when Home is entered or pulled to refresh.
- Messages use no household history, profiling, remote service, or AI.
- Existing quests, progression, family reward, and recent activity remain
  beneath the personalized introduction.

## Profile switching

- The large rectangular profile cards are replaced by adaptive circular
  companion portraits with names, roles, profile-color rings, and a clear
  current-profile treatment.
- Selecting a person still returns directly to that person's Home view.
- The layout remains usable on iPhone, iPad, Dynamic Type, and VoiceOver.

## App icons

- My Profile offers the original icon and the first alternate Pastel icon.
- iOS applies the selected icon to this installation as a whole. It is not a
  per-person setting and is not synchronized through CloudKit or backups.
- The icon catalog is intentionally structured so approved icons can be added
  in later releases without changing household data.

## Data and privacy impact

- Companion and background selections continue to use the existing synced
  Person fields and established unlock rules.
- No new household record type, SwiftData migration, CloudKit schema change,
  permission, secret, or personal-data collection is introduced.
- Release metadata advances to version 0.10.0, build 8.
