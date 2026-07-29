# CloudKit development configuration

The project owner authorized Development CloudKit validation in 0.5. The app
uses:

- app bundle identifier `com.kyndynfamily.kyndyn`;
- iCloud container `iCloud.com.kyndynfamily.kyndyn`;
- CloudKit Development environment only.

No Apple Developer Team identifier, profile, certificate, or credential is
committed. Select the authorized team locally in Xcode when signing a physical
device build.

The Xcode project centralizes three build settings:

- `KYNDYN_CLOUD_SYNC_CONFIGURED` — `YES` for Debug and `NO` for Release;
- `KYNDYN_CLOUDKIT_CONTAINER_IDENTIFIER` — the authorized container for Debug
  and blank for Release;
- `KyndynCloudKitEnvironment` — generated as `development` for Debug and
  `production` for Release, for diagnostics and configuration review.

`KyndynCloudConfiguration` validates these settings and refuses to instantiate
CloudKit when the switch or identifier is missing. This produces a specific
readiness message in **Parent → Family sync** instead of an ambiguous network
failure.

1. Open `kyndyn.xcodeproj`, select the kyndyn target, and choose the authorized
   development team. Do not change the bundle identifier unless that is the
   project's intended App ID.
2. Confirm **Signing & Capabilities → iCloud → CloudKit** selects the documented
   container.
3. Confirm **Push Notifications** and **Background Modes → Background fetch /
   Remote notifications** are enabled for the app identifier and local target.
   The repository contains the project-safe Development APNs entitlement and
   background declarations, but Xcode must refresh the signed development
   profile for the locally selected team.
4. Confirm the generated entitlements contain the same container identifier.
   Development builds must use Apple’s Development environment. Do not manually
   enable a production environment or deploy a production schema.
5. Build to two physical devices signed into different permitted iCloud test
   accounts. Use the CloudKit **Development** environment.
6. On device A, authenticate as a kyndyn parent, open **Parent → Family sync**,
   review the counts, and enable sync. Confirm the round-trip status before
   opening the system share sheet.
7. Invite device B through the system CloudKit sharing interface. Test
   acceptance while kyndyn is running, backgrounded, and terminated, and on a
   fresh install before creating a sample household.
8. Exercise offline edits, concurrent completion/undo, archive/edit conflicts,
   participant removal, owner stop-sharing, and Apple-account changes.
9. Inspect Development records in CloudKit Dashboard for the documented types
   and verify that no device settings, PIN material, notification configuration,
   invitation URLs, or derived counters were uploaded.

Development schema records were initialized by live fictional-data validation.
No production schema was deployed. Do not deploy to Production without a
separate explicit project-owner approval and privacy/release review.
