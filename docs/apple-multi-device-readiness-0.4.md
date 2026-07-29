# Apple Multi-Device Readiness 0.4

## Scope

This milestone integrates Local Core 0.2, Cloud Sync 0.3, and the complete
kyndyn identity. It strengthens the native app for variable Apple-device
containers without creating a speculative device target.

## Configuration readiness

The bundle identifier remains `com.kyndynfamily.kyndyn`; ownership must be
confirmed by the project owner’s Apple Developer account. Live CloudKit remains
off by default. A named container identifier and explicit build switch are both
required before the production transport can be constructed.

Debug identifies the intended environment as Development. Release identifies
Production for review, but a production schema must not be deployed without
explicit authorization. No team identifier, credential, profile, entitlement,
or Apple account detail is committed.

## Adaptive foundation

Primary content has readable maximum widths, adaptive grids, and compact
fallbacks. The same views support narrow iPhone and Split View widths, large
iPad widths, landscape, large text, and a compact square-like container.
Layouts use available width and SwiftUI fitting behavior rather than device
names.

Profile colors now appear as named card, ring, and dashboard accents. Names,
roles, and companions remain visible, so color is not the only identity cue.

## Synchronization validation

Deterministic tests cover owner and participant edits, reordered and duplicate
completion delivery, exact-event undo, offline retry, deterministic conflicting
edits, archive/edit precedence, later explicit restore, invitation states,
revocation, account change, stale tokens, notification refresh, and XP
convergence.

No live Apple CloudKit service or physical multi-device journey is claimed by
this milestone unless separately recorded after authorized configuration.

## Validation record

- Clean generic iOS Simulator build: passed with signing disabled.
- iPhone 17 Pro / iOS 26.5: 42 unit tests and 6 UI tests passed.
- iPhone 17e / iOS 26.5: primary onboarding, profile, completion, and undo
  journey passed in the default light appearance.
- iPhone 17 Pro / iOS 26.5: dashboard and quest action journey passed in
  landscape, dark appearance, and Accessibility XXXL text.
- iPad Pro 11-inch (M5) / iOS 26.5: adaptive dashboard and protected Parent
  Family Sync readiness journeys passed.
- Narrow Split View and a 520-by-520 square-like container are covered by
  deterministic breakpoint tests and a compile-checked SwiftUI preview. The
  simulator environment did not provide automated Split View window resizing,
  so these are not claimed as manual multitasking interaction tests.
- Pointer and keyboard input use SwiftUI’s native button, picker, list,
  navigation, and focus behavior; no device-specific pointer code was added.
- Live Development CloudKit and physical two-device sharing were not exercised
  because no authorized team or container was configured.
