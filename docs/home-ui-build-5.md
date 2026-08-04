# Build 5 Home UI pass

Build 5 begins another loose visual-consistency pass without changing the
underlying family, quest, progression, or synchronization rules.

## Home changes

- XP, level, and streak now share one profile-colored progress surface.
- The entire progress surface opens details, replacing the small standalone
  progress button.
- Empty recent activity no longer adds a low-value card below an empty quest
  state.
- When recent completions exist, they appear as a lightweight list with one
  heading instead of another large card.
- Family reward progress and the existing My day/Everyone control remain
  available and unchanged in behavior.
- Profile customization and parent editing share one improved color selector
  with named presets, a visible selection state, and an optional custom color.
- Existing and synchronized hexadecimal profile colors remain compatible.
- Onboarding now presents one primary setup action and one grouped recovery
  action; sample data is a quiet secondary option instead of a competing card.

The result intentionally gives the greeting, current quests, and family reward
more room while preserving Dynamic Type, VoiceOver, dark mode, and iPad layout.

## Recognition and collections

- Badges are derived from active completion history using deterministic
  thresholds. They do not add XP and are safe to recalculate.
- The five starter companions remain available to every profile. Penguin, Bee,
  Cactus, Cloud, and Dino unlock from completion, streak, and badge milestones.
- Meadow is the default background; Bedroom is also included. Cloud, Aquarium,
  and Arcade unlock from deterministic completion or badge milestones.
- Earned and parent-granted collection IDs are durable. Undoing a completion
  recalculates XP and badges but does not confiscate an item already unlocked.
- Unlock introductions are calm, one at a time, and direct the person to My
  profile. There are no random rewards, loot mechanics, trading, or behavioral
  profiling.
- Protected parent tools can grant collection access directly. This changes
  access only and does not fabricate completions, badges, streaks, or XP.
- Collection ownership and current selections are included in native backups,
  Rowan imports where supported, and the existing conflict-safe Person sync
  record. Device-local authentication and notification settings remain excluded.
