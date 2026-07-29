# CloudKit development configuration

No Apple resource was created by Cloud Sync 0.3. Complete these steps with the
authorized Apple Developer account before live testing:

1. In Apple Developer Certificates, Identifiers & Profiles, confirm the final
   Rowan App ID and create an iCloud container chosen by the project owner.
2. Open `Rowan.xcodeproj`, select the Rowan target, and choose the authorized
   development team. Do not change the bundle identifier unless that is the
   project's intended App ID.
3. In **Signing & Capabilities**, add **iCloud**, enable **CloudKit**, and select
   the authorized container. Xcode may add an entitlements file; review it and
   commit only the container entitlement—not profiles or credentials.
4. Add the Boolean Info property `RowanCloudSyncConfigured` with value `YES`.
   This is the deliberate switch that allows Rowan to instantiate
   `CKContainer.default()`. Without it, all Cloud Sync UI remains safely local.
5. Build to two physical devices signed into different permitted iCloud test
   accounts. Use the CloudKit **Development** environment.
6. On device A, authenticate as a Rowan parent, open **Parent → Family sync**,
   review the counts, and enable sync. Confirm the round-trip status before
   opening the system share sheet.
7. Invite device B through the system CloudKit sharing interface. Test
   acceptance while Rowan is running, backgrounded, and terminated, and on a
   fresh install before creating a sample household.
8. Exercise offline edits, concurrent completion/undo, archive/edit conflicts,
   participant removal, owner stop-sharing, and Apple-account changes.
9. Inspect Development records in CloudKit Dashboard for the documented types
   and verify that no device settings, PIN material, notification configuration,
   invitation URLs, or derived counters were uploaded.

Do not deploy the schema to Production until physical multi-device validation,
privacy review, and explicit project-owner approval are complete.
