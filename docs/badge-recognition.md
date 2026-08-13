# Build 16 — Badge recognition

kyndyn calls these milestones **Badges** in the family experience. The internal
recognition engine treats them as deterministic achievements, but the shorter
name is clearer and friendlier for children.

## Experience

- Each profile has a dedicated badge gallery reached from Progress details.
- Earned and locked badges appear together so progress is understandable.
- Locked badges show the exact quest, streak, quest-XP, or family-reward goal.
- The home progress card shows the number of earned badges.
- A newly earned badge uses the existing calm, one-at-a-time unlock message.
- VoiceOver identifies the badge, earned state, description, and progress.

## Rules

- Badges are based only on completion-event history and family reward milestones.
- Parent-entered starting XP changes level, but never fabricates badges.
- Quest-completion, streak, and quest-XP thresholds are deterministic.
- A badge remains earned after a later undo, streak reset, or reward reset.
- Badges do not grant XP, affect progression math, or rank family members.

## Persistence and synchronization

Earned badge IDs are stored additively on each `Person`. They are included in
the existing Person sync payload and native household backup, while unknown IDs
are rejected during normalization. The sync merger unions earned IDs so an
older device cannot revoke recognition earned elsewhere. This changes no
CloudKit record types and requires no schema deployment.

The initial catalog contains quest-count, best-streak, quest-XP, and shared
family-reward milestones. Future catalogs can add deterministic badge
definitions while preserving the stable IDs already awarded.
