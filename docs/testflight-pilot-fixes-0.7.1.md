# TestFlight pilot fixes 0.7.1

This update resumes the unfinished Real Family Pilot 0.7 branch and addresses
three issues found during hands-on testing.

## Every-other-week quests

Selected-weekday quests can repeat every week or every other week. The week
containing the selected start date is the first active week, so choosing a
Monday start and Monday weekday produces that Monday, skips the following week,
and returns on the next Monday. The interval is persisted in SwiftData,
CloudKit schedule records, and household backups. Its CloudKit representation
uses the existing schedule field so no new production record field is needed.
Existing quests and older backups default to every week.

## TestFlight family sync

Release builds previously shipped with family sync explicitly disabled and an
empty container setting. Release now uses the authorized
`iCloud.com.kyndynfamily.kyndyn` container and the Production CloudKit
environment. The Development schema must be reviewed and deployed to Production
in CloudKit Dashboard before uploading the next TestFlight build. Schema
deployment does not copy Development records.

## Profile colors

Color choices now use independent button behavior inside the SwiftUI form.
Selecting one color no longer triggers the other choices and ends on orange.
Accessibility identifiers and a UI regression test cover the selection state.

## Release checklist

1. Review Development record types and indexes in CloudKit Dashboard.
2. Deploy the reviewed schema to Production; do not copy test records.
3. Archive build 2 with the authorized Apple Development Team.
4. Confirm the archive contains the CloudKit container and production push
   entitlements.
5. Upload to TestFlight and test Family Sync first with fictional data on two
   iCloud accounts.
6. Test an every-other-week quest and profile color editing on the TestFlight
   build.
7. Export a household backup before beginning or expanding a real-data pilot.
