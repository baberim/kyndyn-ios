# Feature parity and status

This is the current Build 15 capability map. It compares product capabilities,
not implementation technology; kyndyn intentionally uses native Apple services
instead of reproducing the previous web stack.

| Capability | Status | Notes |
|---|---|---|
| Profile selection and roles | Implemented | Circular companion selector, parent/family roles, protected Parent area |
| Personal and family Home | Implemented | Immersive profile scene, personal/everyone modes, day context, progress, reward, quests |
| People management | Implemented | Create, edit, archive, restore, colors, role integrity, starting-XP adjustment |
| Individual/shared quests | Implemented | Stable assignments and participant completion events |
| Recurrence and planning | Implemented | One-time, daily, selected weekdays, weekly/every-other-week, templates, two-week overview, validation/repair |
| Due/overdue/deadline behavior | Implemented | Deterministic household-time-zone rules |
| Completion history and exact undo | Implemented | Append-friendly events and reversal without duplicate XP |
| XP, levels, streaks | Implemented | Derived from active history plus an explicitly separate starting-XP adjustment |
| Badges | Foundation implemented | Deterministic badges appear in progress details; full gallery/celebrations remain planned |
| Family reward | Implemented | Editable goal/target and history-safe start-new-reward reset |
| Weekly insights | Implemented | Protected week summaries, daily chart, per-person four-week trends, no rankings/profiling |
| Durable reward history/reports | Planned | Reward-cycle records and parent-previewed exports are Build 17B |
| Companions/backgrounds | Implemented | Full approved collection, deterministic unlocks, profile scenes, parent grants |
| Alternate app icons | Implemented | Device-local Settings choice |
| Local quest reminders | Implemented | Device profile, quiet hours, privacy controls, permission, rescheduling |
| Family broadcasts | Implemented with limitation | CloudKit sync and local alerts; guaranteed closed-app delivery needs hosted APNs |
| CloudKit household sharing | Implemented | Owner private zone, CKShare participants, automatic sync, offline queue, conflict-safe convergence |
| Backup, restore, legacy import | Implemented | Versioned validation, dry run, empty-install import, idempotent receipts, private native backup |
| Guided setup/help | Implemented | Owner/participant onboarding, family sync and backup explanations |
| Calendar | Implemented | Optional read-only EventKit context; selected calendars remain local |
| Weather | Implemented | Optional WeatherKit conditions from one-shot location and local cache |
| Siri and Shortcuts | Foundation implemented | App Intents/Shortcuts work; spoken Siri invocation remains OS-dependent |
| StoreKit premium access | Not implemented | Business rules documented; core family loop must remain free |
| Dedicated AI assistant | Intentionally deferred | No child profiling or remote AI service |
| Web push/server datastore | Intentionally replaced | Native local notifications, CloudKit, SwiftData, and future hosted APNs if approved |

Historical milestone documents may describe an earlier capability as planned.
This table and the root README are the current source of truth.
