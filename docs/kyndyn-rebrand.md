# kyndyn identity migration

The native project now uses the kyndyn identity throughout:

- app display name, Xcode project, scheme, targets, products, and module;
- source and test directory names;
- bundle identifiers under `com.kyndynfamily`;
- Keychain service and local-notification namespaces;
- local persistence filenames and UI-test stores;
- CloudKit record types, zone names, payload keys, and configuration flag;
- documentation, user-facing copy, and accessibility labels.

The bundle identifier and secure-storage namespace changed intentionally. iOS
therefore treats this development build as a new app identity. Data installed
under the earlier development identity and its parent PIN are not silently
accessible to this app. No destructive migration or cross-container data copy
is attempted.

CloudKit has not been configured or deployed, so changing the development
record vocabulary does not mutate live or production cloud data.

Upgraded local stores that contain a household but no device-settings row now
create a default local settings record automatically. This keeps Reminders
available while leaving notification authorization off until the user chooses
to enable it.
