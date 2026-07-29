# CloudKit development configuration

No Apple resource was created by Cloud Sync 0.3. Complete these steps with the
authorized Apple Developer account before live testing:

The app bundle identifier is consistently set to
`com.kyndynfamily.kyndyn`. Confirm that identifier is owned and available in the
authorized Apple Developer account before changing any project value.

The Xcode project centralizes three build settings:

- `KYNDYN_CLOUD_SYNC_CONFIGURED` — defaults to `NO`;
- `KYNDYN_CLOUDKIT_CONTAINER_IDENTIFIER` — intentionally blank;
- `KyndynCloudKitEnvironment` — generated as `development` for Debug and
  `production` for Release, for diagnostics and configuration review.

`KyndynCloudConfiguration` validates these settings and refuses to instantiate
CloudKit when the switch or identifier is missing. This produces a specific
readiness message in **Parent → Family sync** instead of an ambiguous network
failure.

1. In Apple Developer Certificates, Identifiers & Profiles, confirm the final
   kyndyn App ID and create or select an iCloud container chosen by the project
   owner.
2. Open `kyndyn.xcodeproj`, select the kyndyn target, and choose the authorized
   development team. Do not change the bundle identifier unless that is the
   project's intended App ID.
3. In **Signing & Capabilities**, add **iCloud**, enable **CloudKit**, and select
   the authorized container. Xcode may add an entitlements file; review it and
   commit only the container entitlement—not profiles or credentials.
4. Set `KYNDYN_CLOUDKIT_CONTAINER_IDENTIFIER` on the app target to the exact
   selected value beginning with `iCloud.`. Set
   `KYNDYN_CLOUD_SYNC_CONFIGURED` to `YES` for Debug only during initial
   development validation. The app creates that exact named container; it does
   not guess or use another app’s default container.
5. Confirm the generated entitlements contain the same container identifier.
   Development builds must use Apple’s Development environment. Do not manually
   enable a production environment or deploy a production schema.
6. Build to two physical devices signed into different permitted iCloud test
   accounts. Use the CloudKit **Development** environment.
7. On device A, authenticate as a kyndyn parent, open **Parent → Family sync**,
   review the counts, and enable sync. Confirm the round-trip status before
   opening the system share sheet.
8. Invite device B through the system CloudKit sharing interface. Test
   acceptance while kyndyn is running, backgrounded, and terminated, and on a
   fresh install before creating a sample household.
9. Exercise offline edits, concurrent completion/undo, archive/edit conflicts,
   participant removal, owner stop-sharing, and Apple-account changes.
10. Inspect Development records in CloudKit Dashboard for the documented types
   and verify that no device settings, PIN material, notification configuration,
   invitation URLs, or derived counters were uploaded.

Do not deploy the schema to Production until physical multi-device validation,
privacy review, and explicit project-owner approval are complete.
