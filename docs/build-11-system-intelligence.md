# Build 11 — Siri and System Intelligence 0.12.0

Build 11 adds a privacy-limited App Intents foundation for Siri, Shortcuts,
Spotlight shortcut discovery, and supported Apple Intelligence experiences.
It does not add a Kyndyn AI service and sends no household content to a new
Kyndyn backend.

## Available actions

- show today's remaining quests for the selected or requested profile;
- show the current family reward and deterministic XP progress;
- open Kyndyn on a selected profile's Home dashboard;
- complete an exact quest occurrence;
- undo that exact occurrence.

The five actions are registered as App Shortcuts with suggested Siri phrases
and are explained under Settings → Siri & Shortcuts.

The iOS 27 compatibility follow-up adds exact spoken variants for Today’s
quests, parameterized profile phrases, text-based profile and quest resolution,
and a direct Shortcuts link in Settings. The generated app bundle was inspected
and contains all five actions, entities, queries, and shortcut phrase templates
as discoverable metadata. Spoken profile names resolve against the profile name
stored in Kyndyn; the app does not infer legal names, nicknames, or aliases.

## Data and mutation rules

Person and quest-occurrence App Entities use existing stable UUIDs and
occurrence-day identity. Completion and undo call the same `AppModel` methods
used by SwiftUI, including duplicate-completion protection, awarded-XP rules,
collection evaluation, reminder refresh, and the persisted CloudKit mutation
queue. App Intents never write directly to CloudKit or independently calculate
progression.

All exposed actions require local device authentication before returning names,
quest titles, or family reward details. Parent-only creation, editing,
archiving, sharing, reward administration, security, backup, and household
management remain unavailable to Siri and continue to require Kyndyn's local
Parent authorization.

Kyndyn intentionally does not place family profiles or quest titles into the
general Spotlight content index in this milestone. The shortcuts themselves
are discoverable, while private household entities are resolved only when an
authenticated action needs them. No content is exposed through notification
payloads or lock-screen previews by this integration.

## Apple platform behavior

App Intents provide the stable integration across supported releases. Siri
recognition and background execution remain controlled by Apple and can vary by
device, language, settings, and OS version. Apple's iOS 27 App Schemas improve
natural-language understanding for supported domains, but the current SDK does
not provide a task, chore, or family-quest schema. Kyndyn therefore keeps its
honest custom App Intents rather than mapping private family data onto an
unrelated schema. Onscreen awareness and richer Apple Intelligence capabilities
remain availability-gated follow-up work.

Physical-device validation should cover Siri and Shortcuts discovery, locked
and unlocked execution, offline completion and undo, app relaunch, and later
CloudKit convergence. Simulator and deterministic tests do not prove Siri's
live speech recognition behavior.
