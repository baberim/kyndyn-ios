# Product scope

## Promise

kyndyn helps a family answer: what needs to happen today, how is everyone doing,
and what are we working toward together?

## Current product

Build 15 supports the complete everyday loop on iPhone and iPad:

- create a local household or recover/join an iCloud household;
- choose a person and see a personal or whole-household day;
- create, assign, schedule, complete, and exactly undo quests;
- derive XP, levels, streaks, badges, weekly insights, and reward progress from
  completion history;
- personalize profiles with colors, companions, backgrounds, and app icons;
- manage the family through a separately protected Parent area;
- work offline and synchronize later when family sync is enabled;
- optionally show read-only calendar context and local WeatherKit conditions;
- export or restore a private backup and import a supported legacy household
  into an empty installation.

## Product decisions

- Recognition comes before incentives: Quest → XP → Level → Badge → Collection
  → Reward.
- Completion events are historical source data; XP, levels, streaks, weekly
  insights, and family progress are deterministic projections.
- A parent-entered starting-XP adjustment changes current XP/level only. It does
  not invent completions, streaks, badges, or weekly earned XP.
- Shared quests require each participant to check in. Individual quests award
  each assigned participant independently.
- Household calendar calculations use the household time zone.
- Cosmetic unlocks, once granted, remain durable even if a completion is undone.
- Calendar, location, weather, device customization, authentication, and
  notification preferences remain local to the device.
- No ads, trading, random rewards, gacha, sibling leaderboards, child scoring,
  or child-directed behavioral profiling.
- CloudKit access does not establish parent authority inside kyndyn.

## Deliberately deferred

- guaranteed hosted remote notifications;
- durable reward-cycle history and exported insight reports;
- a full badge gallery and expanded recognition experience;
- StoreKit, premium entitlements, and family-purchase behavior;
- dedicated AI or assistant services;
- production release, localization, and final external security/accessibility
  reviews.
