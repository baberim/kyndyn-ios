# Daily Family Use 0.8

## Everyday workflow

The Home tab remembers both the selected family member and whether this device
last showed **My day** or **Everyone**. Person mode shows that profile's XP,
level, streak, reward progress, grouped quest states, and recent completions.
Everyone mode provides compact daily summaries for every active person without
treating the household as another profile.

Quest cards are complete tap targets. A successful check-in is visible in
SwiftData immediately, displays the exact effective XP, and queues CloudKit work
without blocking interaction. Completion identity is deterministic for the
quest, person, and occurrence day, so rapid taps, retries, reordered delivery,
and two-device completion converge on one event. Undo updates that exact event.

## Family rewards

The protected Parent area can change the current family reward name and XP
target without resetting progress, or start the entered reward as a new goal at
0 XP. A reset creates a new active `RewardGoal` whose creation date is the
progress boundary. It never edits or deletes `QuestCompletion` history, so
profile XP, levels, streaks, and completed-quest history remain unchanged.

Reward progress is derived from active completion events on or after the active
goal's boundary. Archived goals remain available in backups and CloudKit, and
the existing `RewardGoal` record shape is unchanged; no production schema
deployment is required for this behavior.
Individual and shared-all quests continue to maintain one event per participant.

Parent quest management edits title, notes, XP, assignees, completion mode,
schedule, selected weekdays, weekly/every-other-week interval, anchor date,
deadline, local reminder, and archive state. Archiving never removes completion
history. An every-other-week schedule uses the week containing its selected
start date as the first active week.

## Reminder privacy and behavior

Notification authorization, the selected device profile, quiet hours, lock
screen privacy, scheduled identifiers, and `LocalQuestReminder` remain local to
the device. They are excluded from CloudKit, household backup, and Rowan import.
The shared quest and schedule remain the cross-device truth; each device chooses
whether and when to notify its user.

Reminders are rebuilt after relevant local or remote person, quest, schedule, or
completion changes. Completed and archived occurrences produce no alert. Undo,
restore, timing edits, and household-time-zone changes rebuild the eligible
request using stable identifiers, replacing stale requests rather than adding
duplicates. Quiet hours move an alert to the configured quiet-hours end.

## CloudKit and migration impact

0.8 adds no CloudKit record type or field. The existing Production schema does
not require another deployment for this milestone. `LocalQuestReminder` and the
whole-household display flag are additive SwiftData, device-only state. Existing
households, 0.7 backups, and Rowan transfers remain readable. Backup format and
CloudKit payloads are unchanged.

Release remains configured for `iCloud.com.kyndynfamily.kyndyn` in Production;
Debug remains in Development. Production and Development data do not mix.

## TestFlight — What to Test

- Switch between **My day** and **Everyone**, relaunch, and confirm the view
  persists. Use the profile selector to change people and confirm it returns to
  that person's Home view.
- Confirm Overdue, Due today, Completed today, and Upcoming sections read
  correctly for one-time, daily, weekly, and every-other-week quests.
- Tap anywhere on a quest card, verify immediate XP feedback, then undo it.
- Rapidly tap a quest and confirm XP is awarded only once.
- Edit all quest fields, archive and restore it, then confirm its history stays.
- In Parent → Family reward, change the reward and XP target, save without a
  reset, then start a new reward and confirm only the family reward counter
  returns to 0 XP.
- Enable a device reminder, choose a quest time, change quiet hours, complete
  and undo the quest, and confirm stale alerts are replaced or canceled.
- With two Production TestFlight devices, edit and complete offline, reconnect,
  and confirm both devices converge without manual refresh during foreground use.

Use fictional household data until this build completes the Production
CloudKit pilot.
