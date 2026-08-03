# UI Polish 0.8 — Pass One

This pass keeps the 0.8 family workflow and data model unchanged while creating
a reusable native Kyndyn visual foundation.

## Visual direction

- Kyndyn's pink, purple, and blue family from the PWA is translated into native
  semantic surfaces rather than copying web layouts.
- Light and dark appearances use subtle adaptive background gradients and
  translucent cards with restrained status-color edges.
- Profile colors remain identity accents. Blue, green, and amber communicate
  due, completed, and overdue states consistently.
- Typography remains Dynamic Type driven and controls remain standard SwiftUI
  controls for accessibility and expected iOS behavior.

## Screens included

- Home: balanced three-column progress cards, profile-accented hero, reward card,
  compact Everyone summaries, and persistent My day / Everyone control.
- Quests: equal-height cards, readable state pills, concise shared-check-in icon,
  section counts, and consistent overdue/due/completed/upcoming accents.
- Shared card styling is reusable by later Parent, onboarding, profile, and data
  management polish passes.

## Behavior and data impact

There are no SwiftData, CloudKit, synchronization, progression, reminder, or
authentication behavior changes in this UI pass. No CloudKit schema deployment
is required.

The TestFlight build number advances from 3 to 4 while the marketing version
remains 0.8.0.

## Validation focus

- iPhone and iPad sizing
- light and dark appearance
- larger Dynamic Type and landscape
- long quest titles and notes
- VoiceOver status and shared-check-in descriptions
- completion, undo, Home mode switching, and profile selection behavior
