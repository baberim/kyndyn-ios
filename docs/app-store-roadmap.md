# App Store roadmap

## Completed through Build 11

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

### Build 8 — Visual Identity and Personalization

- Add a device-local app icon selector with the current icon and the supplied
  alternate icon, using a catalog that can grow as more approved icons arrive.
- Put each person's earned companion and background front and center in a
  responsive Home hero beneath the personal/everyone view control.
- Move the personal greeting beneath that scene and rotate through a larger
  set of short, encouraging, privacy-safe messages when Home is freshly shown
  or refreshed, without remote AI or behavioral profiling.
- Replace the large profile-selector cards with polished circular companion
  portraits, names, clear selection state, and adaptive iPhone/iPad layouts.
- Add restrained visual flair while preserving unlock rules, progression,
  synchronization, accessibility, and reduced-motion behavior.
- Keep alternate-icon choice local to each installation; companion and
  background selections continue to follow the existing synced profile model.

See `docs/build-8-visual-identity.md` for the implemented scope.

### Build 9 — Personalization Parity

- Separate everyday Settings from protected Parent administration so any
  active profile can reach appearance and personalization safely.
- Move app-icon choice into Settings while keeping it device-local.
- Bring the complete approved Rowan companion artwork into the native
  collection, including the three owner-approved custom companions.
- Bring the remaining usable Rowan background scenes into the native
  collection while excluding generic locked-placeholder art.
- Preserve existing earned selections and apply deterministic milestone rules
  to new collection items without introducing random rewards.
- Keep parent grants available for accessibility and family discretion.

### Build 10 — Quest Planning Tools

- Added eleven native quest templates for common family routines.
- Added a household-time-zone-aware two-week schedule overview.
- Added recurrence diagnostics and explicit safe-repair tools.
- Preserved completion history and awarded XP when schedules are edited or
  repaired, while routing repairs through the existing sync queue.

See `docs/build-10-quest-planning.md` for the implemented scope.

### Build 11 — Siri and System Intelligence

- Siri and System Intelligence integration using App Intents rather than a
  dedicated Kyndyn AI service:
  - Expose privacy-limited profile and quest-occurrence choices to Siri and
    Shortcuts, with shortcut discovery available through Apple's system
    surfaces.
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

See `docs/build-11-system-intelligence.md` for the implemented foundation and
the remaining physical-device validation boundary.

## Completed through Build 14

### Build 12 — Family Communication

- Family broadcasts and announcements with parent controls.
- Richer parent and family summaries.
- Privacy-conscious delivery and expiration behavior.
- Keep announcements separate from synchronization notifications and quest
  reminders.

### Build 13 — Immersive Personal Home

- Replace the ambiguous Home personalization shortcut with a familiar,
  clearly labeled route to Settings, or remove it when the existing profile
  and Settings navigation makes it redundant.
- Recompose the selected background and companion as the Home header itself:
  the scene supplies the header atmosphere, the companion sits within it, and
  greeting, encouragement, and profile context remain legible parts of one
  responsive composition rather than a separate image card.
- Use safe-area-aware crops, gradients, and contrast treatments so the header
  works in light and dark mode without obscuring navigation or text.
- Adapt the composition for compact iPhones, larger Dynamic Type, iPad,
  landscape, VoiceOver, and Reduce Motion.
- Preserve earned-item rules and synchronized companion/background selection;
  this build changes presentation rather than progression or ownership.

See `docs/build-13-immersive-personal-home.md` for the implemented scope.

## Completed through Build 18

### Build 15 — Weekly Family Insights

- Protected weekly family overview and daily activity chart.
- Individual four-week completion and earned-XP trends.
- Completed, not-completed, and waiting summaries using household-time-zone
  boundaries.
- Deterministic parent observations without rankings, sibling comparisons, or
  behavioral profiling.
- Starting XP contributes to current level but not weekly earned-XP reporting.

See `docs/build-15-weekly-insights.md` for the implemented scope.

## Build 16 — Badge Recognition

- Added a dedicated badge gallery, deterministic quest/streak/quest-XP/family
  milestones, progress toward locked badges, and accessible earned-badge
  celebrations.
- Earned badges persist through sync and backup and cannot be inferred from a
  parent-entered starting XP adjustment.
- Legacy badge migration remains deferred; existing completion history can
  earn supported badges without trusting stale summary totals.

See `docs/badge-recognition.md` for the implemented scope.

## Build 17 — Recognition Polish

- Name earned badges and explain the milestone in the celebration experience.
- Explain badge-count companion and background unlocks in the gallery.
- Surface a restrained badge count on Profiles without rankings or comparison.

## Build 18 — Calendar and Weather Refinement

- Improve upcoming-event timing and multi-event context on Home.
- Make cached weather freshness honest and visible.
- Open dismissible ten-day forecast and two-week calendar summaries from Home,
  while keeping device-local configuration in Settings.
- Stabilize startup, refresh, artwork loading, and Home spacing before the
  TestFlight build.

See `docs/calendar-weather.md` for the implemented privacy boundary.

Build 18 received a focused reliability follow-up released as version `0.18.1 (19)`. Its cumulative release notes are
recorded in `docs/build-18-changelog.md`.

## Build 20 — Household Data Safety

- Fetch and reconcile the complete paginated CloudKit household before
  recovery, including deterministic handling of repeated record revisions.
- Present a protected recovery preview with profile, quest, completion, undone
  history, and XP totals before any local data changes.
- Reject incomplete or internally inconsistent recoveries and roll back any
  failed insertion rather than accepting a partial household.
- Verify starting XP, awarded completion XP, undone state, and recovered entity
  identities before reporting success.
- Persist a privacy-safe recovery receipt and show the latest successful private
  backup export time in Parent tools.
- Keep empty-install recovery, manual private backups, and normal incremental
  synchronization as separate, understandable safety layers.

See `docs/build-20-household-data-safety.md` for the implemented safety model and
the Development-versus-Production validation boundary.

## Build 21 — App Store Readiness and Data Controls

- Rename the protected backup area to **Data and privacy** and explain which
  family data can sync, which settings stay device-only, and what diagnostics
  deliberately omit.
- Verify every prepared private backup before presenting the Files export UI.
- Include supported family announcements in backup validation and round-trip
  restore while retaining compatibility with earlier backups.
- Require a successful backup from the last 24 hours and exact household-name
  confirmation before removing local household data.
- Keep local removal separate from iCloud deletion: it creates no tombstones,
  does not stop sharing, and never deletes the CloudKit household.
- Add accessibility identifiers and readable status summaries for backup and
  destructive controls.

See `docs/build-21-app-store-readiness.md` for the implemented safeguards and
remaining external App Store work.

## Build 22 — Release Candidate Hardening

- Add a protected, privacy-safe household safety check before broader release
  testing.
- Verify active parent coverage, quest assignments, completion relationships,
  queued sync retries, unresolved conflicts, account state, and backup
  freshness without exposing household content in diagnostics.
- Add deterministic healthy and unsafe-household audit coverage plus a UI
  journey for the protected check.
- Add a synchronized household schedule pause with inclusive dates, automatic
  resume, reminder suppression, and paused-day exclusion from weekly missed
  summaries.
- Revalidate simulator compilation while keeping Production CloudKit and
  personal signing material outside the milestone.

## Build 23 — Calendar Identity Polish

- Preserve each EventKit calendar's device-local display name and color when
  presenting upcoming events.
- Use the source calendar color for event-card accents and borders on the Home
  preview and expanded Coming up sheet.
- Keep calendar titles, colors, identifiers, and event details out of CloudKit,
  household backups, and shared records.

See `docs/build-22-release-candidate.md` for the Build 22 implementation and
remaining physical-device release checklist.

## Build 24 — Focused Personalization Settings

- Replace the combined My profile editor with separate App color, Companion,
  Background, and App icon destinations in everyday Settings.
- Preserve synchronized profile appearance and earned collection rules while
  keeping app-icon choice local to each installation.
- Restore explicit alternate-icon declarations for iPad.
- Explain Apple platform restrictions when an iPad app running on Mac reports
  that alternate icons are unavailable instead of silently ignoring taps.

See `docs/build-24-personalization-settings.md` for the implemented boundary.

## Next builds — recommended order

### Build 25 — Multi-device release confidence — implemented with Build 24

- Complete the physical owner/participant checklist for automatic sync,
  offline recovery, invitations, revocation, relaunch, and empty-install
  recovery.
- Add a parent-readable recent sync-health summary without exposing CloudKit
  identifiers or raw errors.
- Verify schedule-pause fields in Development and promote only the reviewed
  schema additions before relying on them in Production.

Implemented in `0.24.0 (25)`: the parent-readable privacy-safe sync-health
summary and deterministic state coverage. The physical-device checklist and
Development-to-Production schema review remain release validation steps because
they require the owner's Apple devices and CloudKit Console access.

### Build 26 — Parent planning and reward expansion

This scope was deferred when hosted notifications became the higher priority;
it is now scheduled as Build 30 below.

- Improve bulk quest planning and assignment without weakening the validated
  schedule editor.
- Support multiple prepared or rotating family rewards while keeping one clear
  active goal.
- Preserve reward and XP history when goals change.

### Build 27 — Hosted family notifications

- Add the minimal authenticated service needed for dependable APNs delivery of
  family broadcasts and other explicitly approved alerts.
- Keep CloudKit synchronization hints, local quest reminders, and visible
  family announcements as separate notification categories.
- Add token rotation, revocation, privacy controls, rate limits, and operating
  cost monitoring before external release.

Implemented and physically validated between an owner iPhone and participant
iPad. The Git-deployed Cloudflare Worker uses capability-authenticated device
enrollment, short-lived pairing codes, encrypted APNs tokens, per-device
privacy controls, revocation, rate limits, and separate Sandbox/Production
routing. Version `0.27.1 (28)` reconciles the complete Builds 20–25 feature line
and prevents paired devices from receiving both hosted and CloudKit-fallback
alerts for the same announcement.

### Build 29 — Consolidated release candidate

- Reconcile household safety, schedule pause, personalization, calendar,
  weather, sync health, and hosted-notification work onto one release line.
- Keep pull-to-refresh behavior and visible feedback consistent throughout
  refreshable screens, including device-local calendar and weather context.
- Prevent duplicate delivery when hosted APNs succeeds while preserving the
  CloudKit fallback for devices that are not enrolled with the hosted service.
- Revalidate the complete native suite, iPhone and iPad compilation, Release
  configuration, and the hosted-notification service before TestFlight.

See `docs/build-29-release-candidate.md` for validation and handoff details.

## Next builds — recommended order

### Build 30 — Parent planning and reward expansion — implemented

- Added a responsive seven-day parent planner, whole-batch validation, bulk
  one-time quest creation, and safe day copying through the established quest
  schedule and synchronization paths.
- Added a synchronized, explicitly ordered queue of up to five prepared family
  rewards while keeping exactly one clear active goal.
- Added carry-or-reset activation. Reward-cycle facts are retained while
  profile XP, levels, streaks, completion history, and earned collections are
  never reset.
- See `docs/build-30-parent-planning-rewards.md` for behavior and validation.

### Build 31 — Parent simplification and reward history — implemented

- Group the protected Parent area into clear task-based destinations while
  keeping common actions close at hand.
- Rewrite technical and developer-oriented callouts in family-friendly terms.
- Show durable reward-cycle history for reached and replaced goals.
- Keep report exporting out of scope until real families demonstrate a need.
- See `docs/build-31-parent-simplification.md` for behavior and validation.

### Build 32 — Premium boundaries and entitlement design — implemented

- Finalized the free-versus-premium feature matrix without removing the core
  family loop, security, backups, recovery, or earned items.
- Set proposed launch pricing at $3.99 monthly or $29.99 annually, with a
  14-day trial and Apple Family Sharing.
- Defined entitlement sources, expiration/refund behavior, restoration,
  complimentary access, and grandfathering boundaries.
- See `docs/build-32-premium-foundation.md`.

### Build 33 — StoreKit implementation — implemented

- Added verified StoreKit 2 purchases, restoration, transaction updates,
  localized plans, entitlement caching, and family-safe expiration behavior.
- Added the authenticated Parent-area Premium surface without gating any
  currently shipped feature.
- Local StoreKit and Apple sandbox transaction scenarios remain the next manual
  validation boundary. See `docs/build-33-storekit.md`.

### Build 34 — Apple Watch premium companion

- Build a deliberately small Watch experience for viewing today's quests,
  completing an exact occurrence, and seeing current progress.
- Keep the phone app useful without a Watch and treat Watch access as premium.

### Build 35 — Public-release hardening

- Complete the remaining security, accessibility, localization, privacy,
  support, physical-device, and App Store release gates.

## Later

- Reward history refinements should be driven by household testing. Report
  exporting is intentionally deferred unless real users request it.

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
- Complete the remaining roadmap and robust parent editors.
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
