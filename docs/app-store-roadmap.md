# App Store roadmap

## Before beta

- Add parent authentication and recovery.
- Implement CloudKit private/shared zones, invitations, conflict tests, and deletion.
- Add local notification permission education and scheduling.
- Finish badges, collections, backgrounds, and robust parent editors.
- Complete migration importer and sanitized fixture tests.
- Add accessibility identifiers and broaden UI coverage.

## Apple setup

Create an App ID and unique bundle identifier, enable iCloud/CloudKit and push notifications as needed, create development/production CloudKit containers, configure signing and capabilities, create an App Store Connect record, supply privacy details/screenshots, and later configure a StoreKit 2 subscription group if monetization is approved.

None of those credentials or portal changes are required for this local milestone.

## Release gates

Privacy/security review, VoiceOver and Dynamic Type audit, reduced-motion and contrast review, localization readiness, real-device offline/relaunch testing, CloudKit sharing failure tests, StoreKit sandbox tests, deletion/export flows, support URL, privacy policy, and TestFlight family testing.

