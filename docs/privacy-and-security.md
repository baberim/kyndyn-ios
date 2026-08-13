# Privacy and security

kyndyn handles family and child data. Its default posture is local-first,
data-minimizing, free of advertising, and free of third-party behavioral
analytics.

## Shared household data

Only after a parent explicitly enables family sync, CloudKit may contain the
household, supported people/profile fields, quests and schedules, completion
events, reward goal, family broadcasts, collection identity/grants, starting-XP
adjustments, and household policy. Records live in the owner's private custom
zone and invited participants access its shared zone under Apple's permissions.

CloudKit membership proves access to that Apple share. It does not prove parent
authority inside kyndyn; protected Parent actions still require local device
authentication or the optional kyndyn PIN.

## Device-local data

The following never enter shared household records:

- PIN material, biometric state, Parent unlock state, or authentication secrets;
- Apple credentials, CloudKit tokens, invitation URLs, or device identifiers;
- notification authorization, quiet-hour overrides, selected device profile,
  and scheduled notification identifiers;
- calendar authorization, selected calendars, and event data;
- location authorization, coordinates, and WeatherKit cache;
- app-icon choice, onboarding presentation, and view preferences;
- private transfer files and their security-scoped URLs.

The optional PIN is salted, iteratively hashed, and stored in a
`WhenUnlockedThisDeviceOnly` Keychain item. Plaintext PINs never enter SwiftData,
UserDefaults, logs, fixtures, or source. Parent access re-locks after two minutes
in the background and when profiles change.

## Insights and progression

Completion history remains source truth. Progress and weekly insights are
calculated locally and are not sent to an analytics or AI service. kyndyn does
not rank siblings, grade children, infer behavior, or use starting-XP adjustments
to fabricate completion history, streaks, badges, or weekly earned XP.

## Calendar, weather, and notifications

Calendar access is optional and read-only. Weather uses optional one-shot
location access and a replaceable local cache. Neither becomes synchronized
household truth. Lock-screen quest titles remain hidden by default.

Family broadcasts synchronize as household data, but user-facing alerts are
scheduled locally. CloudKit remote notifications contain no family content and
act only as hints to fetch changes. Without a hosted APNs sender, background
delivery is best effort and is not described as real-time.

## Imports, backups, and logs

Imports are explicit, previewed, size-limited, relationship-validated,
transactional, and initially restricted to an empty installation. Unsupported
fields are reported rather than silently imported. Actual household exports,
backups, logs, screenshots, and runtime files must never be committed.

Diagnostics may include operation category, database scope, retry count, and a
redacted error category. They must not contain names, quest titles, calendar
details, coordinates, record payloads, completion payloads, invitation URLs,
tokens, PIN data, or transfer contents.

## Release work

Before public release: finish App Privacy labels and policy, retention/deletion
behavior, child-safety review, account/share removal and recovery guidance,
encrypted-export policy, independent threat modeling, and an external
accessibility/security audit.
