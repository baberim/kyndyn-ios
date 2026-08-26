# Builds 24–25 — Personalization and Multi-device Confidence

The combined release is version `0.24.0 (25)`. It separates everyday visual choices so
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

The expanded weather sheet includes an **Hourly / 10-day** switch. Hourly rows
show the next 24 hours and meaningful precipitation chances. Weather accents
now communicate conditions—warm for sun, slate for clouds, blue for rain, cyan
for snow, and indigo for storms or nighttime—instead of always appearing blue.

## Delivery boundary

This milestone updates source, tests, documentation, and Git only. It does not
archive, upload, deploy a CloudKit schema, or modify App Store Connect.

## Multi-device confidence

**Parent → Family sync** now includes a recent sync-health summary. It clearly
distinguishes local-only storage, safely queued changes, ordinary reconnecting,
a recent successful sync, and account/access problems requiring attention. The
summary is derived from local sync metadata and deliberately excludes family
names, quest titles, CloudKit identifiers, and Apple's raw error text.

Deterministic tests cover healthy, pending, and access-removed summaries. The
existing multi-device engine remains unchanged: mutations stay offline-first,
idempotent, and routed to the correct owner-private or participant-shared zone.

Physical validation still requires the owner's iPhone and participant iPad.
Before release, verify automatic foreground sync, offline catch-up, invitation
acceptance, revocation, relaunch with pending changes, and empty-install
recovery. The synchronized schedule-pause fields must also be reviewed in the
Development CloudKit schema and promoted through Apple's console before a
Production build relies on them. No Production schema is changed by this code.
