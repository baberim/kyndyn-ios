# App Store roadmap

Current feature set and TestFlight upload: **kyndyn 0.15.0 (Build 15)**.

## Completed foundation

### Builds 1–6 — Local core, CloudKit, and first UI system

- Offline SwiftData household, people, quests, schedules, completions, XP,
  levels, streaks, rewards, reminders, authentication, backup/import, and
  archive/restore workflows.
- Owner/participant CloudKit sharing, invitations, conflict-safe offline queue,
  automatic foreground/relaunch sync, subscription hints, and recovery states.
- Production-capable signing/container configuration and physical two-account
  Development CloudKit validation.
- Initial TestFlight pipeline, rebrand, app icon, responsive iPhone/iPad UI,
  dark-mode consistency, profile color fixes, and pull to refresh.

Historical details remain in the 0.2–0.8 milestone documents.

### Builds 7–9 — Setup and personalization

- Guided owner/participant onboarding plus revisitable family setup help.
- Backup, restore, iCloud recovery, and family-member invitation explanations.
- Immersive companion/background Home presentation, expanded encouragement,
  polished profile switching, complete approved collection, alternate app icons,
  and separate everyday Settings versus protected Parent administration.

See [Build 7](build-7-guided-family-setup.md), [Build 8](build-8-visual-identity.md),
and [Build 9](build-9-personalization-parity.md).

### Build 10 — Quest planning

- Native templates, two-week schedule overview, recurrence diagnostics, and
  safe repair tools.
- Prevent invalid recurrence during quest creation/editing where possible while
  retaining repair for previously stored/imported schedules.

See [Build 10](build-10-quest-planning.md).

### Build 11 — System intelligence foundation

- Privacy-limited App Intents for today's quests, reward progress, opening a
  person's dashboard, completion, and exact undo.
- Shortcuts reuse the local store, progression engine, and sync queue.
- Spoken Siri invocation remains dependent on Apple's evolving OS behavior and
  is not considered guaranteed.

See [Build 11](build-11-system-intelligence.md).

### Build 12 — Family communication

- Parent-managed family broadcasts, CloudKit synchronization, expiration, and
  local notification handling.
- Broadcasts remain separate from sync hints and quest reminders. Guaranteed
  prompt closed-app delivery requires a future hosted APNs service.

### Build 13 — Immersive personal Home

- Safe-area-spanning profile scene header, grounded companion composition,
  adaptive contrast/depth treatment, and clearer Settings navigation.

See [Build 13](build-13-immersive-personal-home.md).

### Build 14 — Calendar, weather, and settings polish

- Optional read-only EventKit calendar context and device-local selected
  calendars.
- Optional one-shot location and WeatherKit conditions with replaceable local
  cache.
- Consistent Settings/Parent rows, callouts, dark mode, iPad layouts, context
  card sizing, level visibility, and parent-entered starting XP.

See [Calendar and weather](calendar-weather.md).

### Build 15 / 17A — Weekly family insights

- Protected current/past weekly overview, seven-day chart, family totals,
  individual four-week trends, and factual observations.
- Completed, not-completed, waiting, and earned-XP rules respect the household
  time zone and exclude starting-XP adjustments.
- No rankings, sibling comparisons, grades, AI conclusions, or behavioral
  profiling.

See [Weekly Family Insights](build-17a-weekly-insights.md).

## Candidate next work

Priority should be chosen before starting the next build; the remaining work is
not locked to build numbers.

1. **Insights 17B — reward history and private reports**
   - durable reached/replaced reward-cycle history;
   - locally generated weekly/monthly reports with parent preview before export;
   - accessibility and multi-device validation for expanded insights.
2. **Badge recognition**
   - dedicated gallery, more deterministic milestones, accessible celebrations,
     and explicit legacy badge migration;
   - never infer badges from manually entered starting XP.
3. **Hosted notification delivery**
   - minimal trusted service for APNs tokens and prompt broadcasts;
   - consent, deletion, security, abuse prevention, and operating-cost review.
4. **Business model and entitlements**
   - keep the core family loop, security, accessibility, backup/export/recovery,
     and useful small-household sync free;
   - reserve premium for meaningful expansion such as advanced planning,
     reports, customization, multiple rewards, and integrations;
   - define household ownership, Apple Family Sharing, gifts/promo access,
     expiration, refunds, restoration, transfer, and grandfathering before
     implementing StoreKit.
5. **Public-release hardening**
   - independent security/privacy review, accessibility audit, localization,
     support/privacy URLs, deletion/export flows, production failure testing,
     and broader TestFlight coverage.

## Apple-service status

- App ID, bundle identity, CloudKit container, Development/Production
  environments, WeatherKit capability, signing capabilities, App Store Connect
  record, and TestFlight pipeline are configured.
- Debug uses Development CloudKit; Release/TestFlight uses Production.
- Every additive CloudKit schema change still needs Development review and
  Production deployment before that field/type is relied upon in TestFlight.
- Background CloudKit and silent notifications are best effort. Foreground and
  relaunch catch-up remain required.
- StoreKit and a hosted notification service remain unconfigured.

## Public-release gates

- Privacy labels, policy, retention/deletion behavior, and child-safety review.
- VoiceOver, Dynamic Type, Reduce Motion, contrast, iPhone/iPad, and localization
  audits.
- Production CloudKit account/share/revocation/reinstall/offline testing with
  fictional data before personal-data use.
- External security review of parent authentication, transfer files, CloudKit,
  and any future hosted service.
- Support URL, screenshots/metadata, export/deletion guidance, crash monitoring
  decision, and sustained family TestFlight validation.
