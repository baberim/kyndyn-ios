# App Store roadmap

## Completed through Build 7

### Build 4 — Daily Experience and Recovery 0.8.1

- Recover an existing owner-hosted or shared household from iCloud after an
  empty reinstall without creating a duplicate household.
- Add honest startup/recovery states and privacy-safe diagnostics.
- Improve quest browsing with status counts, search, details, and completion
  history.
- Turn the Parent landing screen into a useful daily snapshot with quick
  actions, reward progress, sync status, and visible version/build metadata.
- Let the active person safely choose their profile color and starter companion
  while parent-only identity and permission controls remain protected.
- Improve personal XP, level, streak, and recent-completion explanations.
- Keep launch presentation, iPad layout, dark mode, Dynamic Type, VoiceOver,
  automatic sync, and pull-to-refresh consistent.

### Build 5 — Recognition and Collections 0.8.2

- Continue the loose visual-consistency pass, beginning with a calmer Home
  hierarchy, unified personal progress, and quieter activity presentation.
- Native badges derived from deterministic progression.
- Durable companion collection and unlock rules.
- Background collection and profile scenes.
- Calm unlock introductions and parent-managed grants.
- No random rewards, trading, or child-directed behavioral profiling.

### Build 6 — UI Layout Corrections 0.8.3

- Make the Kyndyn purple-black background consistent throughout dark mode.
- Correct compact-iPhone profile customization, companion sizing, and
  background-preview overflow.
- Make companion and background selectors adapt cleanly to iPhone and iPad.
- Use a single full-width iPad surface and center quest filtering controls.
- Improve iPad quest-card use of available portrait and landscape space.
- Keep this release visual-only, without changing household data, progression,
  collections, or synchronization behavior.

### Build 7 — Guided Family Setup 0.9.0

- Add a proper first-run onboarding journey that explains Kyndyn's core family
  loop before asking someone to configure a household.
- Clearly separate adding a person/profile inside a household from inviting a
  family member to use Kyndyn on another device.
- Walk the household owner through enabling iCloud family sync, creating the
  share, sending an invitation, and confirming that the other device joined and
  reached an up-to-date state.
- Give invited participants a focused join flow that avoids accidental sample
  or duplicate household creation and explains what access they received.
- Explain local-only versus iCloud-synchronized households honestly, including
  Apple-account, network, and background-sync limitations.
- Teach parents how to export a private backup, where to store it safely, how
  restore/import differs from iCloud recovery, and why imports require an empty
  installation where applicable.
- Provide a parent-accessible setup checklist or Help surface so these lessons
  can be revisited after onboarding instead of appearing only once.
- Allow safe skipping where appropriate, preserve local-only use, use no real
  family information in examples, and cover VoiceOver, Dynamic Type, iPhone,
  and iPad layouts.

See `docs/build-7-guided-family-setup.md` for the implemented scope.

## Next

### Build 8 — Quest Planning Tools

- Native quest templates for common family routines.
- Schedule overview and diagnostics for recurring quests.
- Safer bulk planning and recurrence repair tools.
- Preserve completion history when schedules are edited.

### Build 9 — Family Communication

- Family broadcasts and announcements with parent controls.
- Richer parent and family summaries.
- Privacy-conscious delivery and expiration behavior.
- Keep announcements separate from synchronization notifications and quest
  reminders.

## Later

- Siri and System Intelligence integration using App Intents rather than a
  dedicated Kyndyn AI service:
  - Expose privacy-limited Person, Quest, quest-occurrence, and family-reward
    entities to Siri, Shortcuts, Spotlight, and supported Apple Intelligence
    experiences.
  - Begin with safe actions such as listing today's quests, showing reward
    progress, opening a person's dashboard, and completing or undoing an exact
    quest occurrence.
  - Reuse SwiftData, deterministic progression, duplicate-completion
    protection, and the existing offline CloudKit mutation queue; Siri must not
    write directly to CloudKit or calculate progression independently.
  - Require device authentication where appropriate and preserve Kyndyn's
    separate Parent authorization for creating, editing, archiving, sharing,
    reward management, and household administration.
  - Keep child names and quest details unavailable from the lock screen, and
    gate newer Siri AI, onscreen-awareness, and App Schema capabilities by OS
    availability while retaining useful App Shortcuts on older supported iOS
    versions.
  - Add deterministic App Intents tests plus physical-device Siri, Shortcuts,
    Spotlight, locked-device, offline, and synchronization validation.
- Read-only calendar integration with explicit permission and privacy design.
- Weather as derived, replaceable cache data rather than shared source truth.
- Business Model and Entitlements must be designed and approved before adding
  StoreKit:
  - Keep the core family loop free: one household, parent and child profiles,
    quest creation and assignment, completion and exact-occurrence undo, basic
    recurrence, XP, levels, streaks, one family reward, local reminders,
    local-only use, backup, restore, export, privacy, security, and
    accessibility.
  - Keep useful family synchronization available for a small household so the
    free app remains a genuine multi-person family product.
  - Reserve premium for expansion such as advanced planning and templates,
    richer insights and reports, additional customization and collections,
    multiple or rotating rewards, family communication, calendar and weather
    integrations, and Siri/System Intelligence features.
  - Never charge for Face ID or other security, accessibility, backup, export,
    recovery, or access to existing household data.
  - Never delete or hide household history when an entitlement expires, revoke
    items a child already earned, or direct purchase pressure toward children.
  - Define household-level entitlement ownership, Apple Family Sharing,
    participants outside the purchaser's Apple family, subscription transfer,
    billing failure, expiration, refunds, purchase restoration, and
    grandfathering before implementation.
  - Evaluate subscription versus one-time purchase based on actual ongoing
    value and operating cost rather than assuming a subscription is required.
- Add StoreKit only after those product rules, child-safety boundaries, and
  expiration behaviors are covered by tests and user-facing documentation.

## Remaining before public release

- Complete independent security review of local parent authentication and recovery limitations.
- Continue validating Production CloudKit private/shared zones, invitations,
  participant permissions, revocation, and recovery through TestFlight.
- Validate notification scheduling and privacy across supported physical
  devices and account roles.
- Complete the remaining Build 7–9 roadmap above and robust parent editors.
- Continue expanding accessibility identifiers, UI coverage, and real-family
  TestFlight validation.

## Current Apple setup

Kyndyn has its App ID, bundle identity, iCloud/CloudKit container, Development
and Production environments, signing capabilities, App Store Connect record,
and TestFlight pipeline configured. Archived Release builds use Production
CloudKit while local Debug builds use Development CloudKit. Continue reviewing
schema changes before deployment and test them with fictional data before using
personal household data.

StoreKit remains intentionally unconfigured until monetization and family
purchase behavior are approved as a separate milestone.

## Release gates

Privacy/security review, VoiceOver and Dynamic Type audit, reduced-motion and contrast review, localization readiness, real-device offline/relaunch testing, CloudKit sharing failure tests, StoreKit sandbox tests, deletion/export flows, support URL, privacy policy, and TestFlight family testing.
