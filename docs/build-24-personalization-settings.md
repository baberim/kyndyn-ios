# Build 24 — Focused Personalization Settings

Build 24 is version `0.23.0 (24)`. It separates everyday visual choices so
people no longer need to navigate one oversized profile editor.

## Settings organization

The active profile now has four focused rows in **Settings → Personalization**:

- **App color** changes the active profile's accent and synchronized color.
- **Companion** chooses from that profile's earned companion collection.
- **Background** chooses from that profile's earned background collection.
- **App icon** changes only the current installation where Apple permits it.

Each profile choice retains the existing preview, earned-item rules, offline
SwiftData write, and CloudKit mutation queue. Names, roles, family permissions,
and parent-managed collection grants remain in the protected Parent area.

## iPad and Mac icon behavior

The iPad-specific icon declaration now mirrors every alternate icon from the
universal declaration. This fixes missing alternate choices on physical iPad.

At runtime, kyndyn checks `UIApplication.supportsAlternateIcons`. When Apple
allows icon changes, selection uses the system API and reports any returned
error. When an iPad app is running on Apple-silicon Mac and macOS reports that
icon changes are unavailable, the gallery remains visible but disabled and
explains the platform limitation instead of silently ignoring taps.

App-icon selection remains device-local and never enters CloudKit or a private
household backup.

## Local weather context

The compact Home weather card and expanded forecast now show the city or town
returned by Apple's geocoder. Kyndyn does not persist coordinates: only the
resulting locality label is cached on the device alongside the weather summary,
and both remain excluded from CloudKit and household backups.

## Delivery boundary

This milestone updates source, tests, documentation, and Git only. It does not
archive, upload, deploy a CloudKit schema, or modify App Store Connect.
