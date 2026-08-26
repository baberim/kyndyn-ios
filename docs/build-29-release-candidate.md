# Build 29 release candidate

Version `0.27.2 (29)` consolidates the currently validated feature line for the
next TestFlight upload. It intentionally adds no new household-data model or
CloudKit schema requirement.

## Included

- Household recovery and safety checks, schedule pause, focused Settings, and
  synchronized profile appearance.
- Calendar identity colors, weather/calendar detail sheets, and device-local
  privacy controls.
- Hosted family-announcement notifications with one-time pairing, token
  rotation/revocation, rate limiting, Sandbox/Production routing, and
  CloudKit fallback without duplicate presentation.
- Consistent pull-to-refresh behavior and feedback on refreshable app surfaces,
  including weather and calendar refresh.
- The complete current iPhone/iPad visual and navigation polish line.

## Automated validation

- 97 native unit tests passed with zero failures.
- 18 native UI tests passed with zero failures.
- iPad Pro 13-inch simulator Debug build passed.
- Generic-device unsigned Release build passed.
- Notification Worker TypeScript check passed.
- 23 notification-service tests passed across validation, cryptography,
  privacy, pairing, APNs routing, and request handling.

One combined Xcode test invocation experienced a test-runner process exit in a
CloudKit pagination test. The affected test passed when isolated, and the full
97-test unit target then passed independently. This was treated as runner
instability rather than a reproducible product failure.

## Physical validation already completed

- Hosted announcements delivered between paired household devices, including
  an iPad and a Mac installation.
- Duplicate delivery was corrected and retested.
- Focused personalization settings were restored and retested.
- Pull-to-refresh behavior, weather/calendar refresh, and current navigation
  were confirmed by the household owner.

## TestFlight handoff

The owner can merge the Build 29 pull request, update local `main`, select the
authorized Apple team in Xcode, then use Product → Archive and distribute the
archive through App Store Connect. Release continues to use Production
CloudKit and Production APNs; Debug uses Development CloudKit and Sandbox APNs.
No production schema change is required by this build.
