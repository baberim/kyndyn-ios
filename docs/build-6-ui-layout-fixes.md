# Build 6 UI layout fixes

Build 6 is a focused visual correction release based on TestFlight feedback.
It does not change household data, progression, collections, or sync behavior.

- Dark screens now share the same purple-black Kyndyn background, including
  profile switching, Parent authentication, Parent lists, and person editing.
- Profile customization uses smaller, bounded previews on compact iPhones.
- Companion artwork is constrained inside profile and collection selectors.
- Companion and background grids adapt separately for iPhone and iPad widths.
- The iPad person editor uses a compact companion control instead of allowing
  selected artwork to expand the form row.
- iPad keeps the app in a single full-width tab surface instead of introducing
  an empty split-view column, and centers quest filtering controls.
- Profile scene artwork is clipped to its actual grid cell so backgrounds and
  labels cannot overlap neighboring choices.
- Quest cards can expand across more of an iPad while still forming multiple
  columns when enough quests are present.

Release metadata advances to version 0.8.3, build 6.
