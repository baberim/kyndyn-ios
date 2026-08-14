# Version 0.18.1 (Build 19)

This is a small reliability iteration on the Build 18 feature set.

## What’s new

- Added protected Weekly Family Insights with completion, unfinished quest,
  XP, streak, and four-week progress trends.
- Fixed parent-added starting XP so levels remain synchronized across devices.
- Added 12 earnable Badges with clear goals, progress tracking, unlock
  celebrations, and collection rewards.
- Added badge counts to Home and Profiles without rankings or family
  comparisons.
- Refined Home with a smoother scene fade, clearer progress presentation,
  consistent spacing, and visible pull-to-refresh feedback.
- Simplified quest filtering and improved navigation across iPhone and iPad.
- Improved Calendar and Weather with clearer timing, freshness information, a
  ten-day forecast, and two weeks of upcoming events.
- Improved dark-mode startup presentation and reduced delays during launch,
  refreshing, artwork loading, and navigation.
- Redesigned the app icon selector as a compact, polished gallery.
- Added ten new alternate icons: Retro Game, Japandi, Prismatic, Atomic Age,
  LCD, Cosmic Outrun, Arcade, Translucent, Outrun, and CRT.
- Added further accessibility, layout, stability, and synchronization polish.
- Fixed fresh iCloud recovery for larger households so every available change
  page is downloaded before XP and levels are recalculated.
- Made full recovery deterministic when CloudKit returns several historical
  revisions of the same person, keeping the newest revision rather than an
  arbitrary one.
- Recovery now preserves its final CloudKit change token and verifies that all
  supported records were actually inserted before reporting success.
- Replaced the startup screen’s repetitive loading copy with rotating playful
  messages.

## Validation

- iPhone 17 Pro on iOS 26.5: 99 automated tests passed, including 82 unit and
  17 UI tests.
- iPad Pro 13-inch (M5) on iOS 26.5: 17 UI tests passed.
- Release configuration compiled successfully with all alternate icons
  embedded.
