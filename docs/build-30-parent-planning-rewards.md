# Build 30 — Parent planning and reward expansion

Build 30 makes routine planning faster without changing kyndyn's offline-first
or completion-history foundations.

## Weekly planner

- Parent → Quest planning → Weekly planner presents seven household-local days
  in an adaptive iPhone/iPad grid.
- **Plan quests** creates several one-time assignments in one review flow.
- Every row is validated before any quest is inserted. Invalid titles,
  assignees, XP, dates, or relationships leave the household unchanged.
- **Copy day** creates new one-time occurrences without changing the source
  quests or their recurring schedules.
- Created quests use stable UUIDs and the normal offline mutation queue, so
  they remain immediately usable offline and converge through CloudKit.

## Prepared rewards

- The family retains one active reward and may prepare up to five future
  rewards with a title, target, optional parent note, and explicit order.
- Reordering, editing the active goal, preparing, removing, and activating all
  use the existing CloudKit-safe RewardGoal identity.
- Activating a prepared reward concludes the previous cycle and records its end
  time and ending counter. The parent explicitly chooses whether the new goal
  carries that counter or starts at zero.
- Neither choice changes profile XP, levels, streaks, completion events, badges,
  companions, or backgrounds.

## Persistence and privacy

The SwiftData change is additive. Existing RewardGoal records default to the
active state. New queue and cycle fields are included in CloudKit snapshots and
native backups. Reward notes are household data and may be visible to members
of the CloudKit share; device secrets and settings remain excluded.

## Validation

- Generic iOS Simulator app build passes with signing disabled.
- Deterministic tests cover all-or-nothing planner validation, multi-row
  creation, copy semantics, and carried reward progress.
- Live CloudKit and physical multi-device behavior must be exercised by the
  owner after installing the development build; automated tests do not claim
  live Apple-service validation.
