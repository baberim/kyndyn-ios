# Local Core 0.2 behavior

## Launch and persistence

The OS launch storyboard uses Rowan colors in light and dark mode, then transitions immediately to an in-app preparation state. Rowan does not delay launch. SwiftData uses an additive schema change for device reminder preferences. If store creation or migration fails, Rowan does not erase data; a calm recovery screen advises preserving the installation.

iOS controls the time before the process can draw and may still show a cached launch snapshot during simulator boot or app installation.

## Parent protection

- Parent profiles may use ordinary dashboards without authentication.
- Opening the Parent tab requires Face ID, Touch ID, device passcode, or an already configured Rowan PIN.
- Every parent mutation is reachable only below that gate.
- Parent access locks when profiles change and after two minutes in the background.
- The optional 6–12 digit PIN is salted, slow-hashed, and stored only in this device's Keychain.
- Device-owner authentication is the only recovery path. Rowan has no email/server identity and makes no stronger recovery claim.

## People lifecycle

Names are trimmed, required, and limited to 40 characters. Duplicate names are allowed because UUIDs—not names—identify people. Parents can edit role, color, and current starter companion. Archive is a soft deletion; history remains connected to the original UUID. The final active parent cannot be archived. Archiving removes the person from future assignments; a quest left with no participants is archived. Restore keeps the original identity.

## Quest lifecycle and time

Titles are required and limited to 80 characters; notes are limited to 300; XP is 1–500. At least one active assignee is required. Multi-person quests choose independent completion or shared check-in. Both produce one event per participant.

- One time: occurrence is the start date; incomplete past occurrences are overdue.
- Daily: occurrence is the current household-local day.
- Selected weekdays: occurrence is the latest selected day on or before today; a missed occurrence remains overdue until completed.
- Due date without time means 11:59 PM in the household time zone.
- Due date with time uses the chosen household-local wall time.
- Completion events store occurrence keys and awarded XP. Later edits never rewrite them.
- Undo reverses the active event for the current occurrence and participant, then projections recalculate.

## Local reminders

Permission is requested only after a parent taps **Turn on reminders** and reads the explanation. Denial does not affect other features. Each device chooses an active profile, default reminder time, quiet hours, parent-summary eligibility, and lock-screen privacy.

Reminder identifiers contain quest UUID, profile UUID, and occurrence day, preventing duplicates. Rowan replaces its own pending requests after relevant local changes and removes obsolete Rowan requests. Child-profile devices never receive parent summaries. Quest names are hidden on the lock screen by default. There is no remote push or server.

## Accessibility

Core screens use Dynamic Type, semantic headings, native Form/List controls, adaptive grids, minimum 44-point completion controls, VoiceOver labels/hints/values, light/dark colors, and no required animation. Reduce Motion remains respected because launch and navigation do not depend on custom motion.

## Simulator checks

- Face ID: Simulator **Features → Face ID → Enrolled**, then choose matching or non-matching face.
- Notifications: reset authorization from the simulator Settings app or erase that simulator's content.
- Dark mode and text size: simulator Settings **Display & Brightness** and **Accessibility → Display & Text Size → Larger Text**.

## Validation performed

On July 29, 2026, Xcode 26.5 completed a clean build and the full suite on an
iPhone 17 Pro simulator running iOS 26.5: 20 unit tests and 4 UI tests passed.
The UI suite exercises onboarding, child quest completion and undo, parent
gating, authenticated people creation, and persistence after termination.

Targeted UI journeys also passed on:

- iPhone 17e, iOS 26.5, dark appearance, Accessibility Extra Extra Large text;
- iPad Pro 11-inch (M5), iOS 26.5, light appearance, default text.

The critical controls have explicit VoiceOver labels, values, hints, headings,
and minimum hit targets. XCTest verified those accessibility identifiers were
reachable, but a full human VoiceOver order/listening audit and physical-device
biometric and notification delivery tests remain release-readiness work.
