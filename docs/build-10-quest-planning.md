# Build 10 — Quest Planning 0.11.0

Build 10 brings Rowan's common quest routines into the native app and adds a
safe planning layer around Kyndyn's existing recurrence engine.

## Templates

The parent-only template library contains eleven fictional starting points for
morning, school, bedroom, pet, kitchen, reading, weekly-cleaning, aquarium, and
shared-family routines. Choosing a template opens the ordinary quest editor
with title, notes, XP, recurrence, weekdays, and completion mode prefilled.
Nothing is created until the parent chooses active assignees and saves.

Templates are static app content. They contain no household information, do not
sync independently, and do not introduce a second quest model.

## Two-week schedule

The schedule overview projects active quests using the household time zone and
the same `ProgressionEngine` used by Home and Quests. It respects start dates,
daily recurrence, selected weekdays, and weekly/every-other-week anchors. Each
projected quest opens the existing history-safe editor.

## Schedule health and repair

Diagnostics identify missing or invalid weekdays, unsupported repeat intervals,
weekly intervals attached to non-weekly quests, and deadlines before start
dates. Safe repair is explicit and parent-confirmed:

- missing weekdays use the weekday containing the quest's existing start date;
- unknown weekday values are removed;
- unsupported repeat intervals return to every week;
- unused weekly intervals are cleared from non-weekly quests.

Deadlines are never changed automatically. Repairs update only schedule source
fields, enqueue the established CloudKit quest/schedule mutation, and rebuild
device-local reminders. Completion UUIDs, event history, reversal state, and
awarded XP remain untouched.

## Privacy and access

Planning remains inside the locally authenticated Parent area. Template and
diagnostic operations do not log names, quest titles, household payloads, or
CloudKit identifiers. No production CloudKit schema change is required.
