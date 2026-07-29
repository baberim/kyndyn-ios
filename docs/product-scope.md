# Product scope

## Promise

kyndyn helps a family answer: what needs to happen today, how is everyone doing, and what are we working toward together?

## Native v1 core

The first release focuses on the reliable daily loop: household setup, profile choice, personal/family dashboards, recurring quests, participant-aware completion and undo, deterministic progression, a family reward goal, parent-managed people and quests, offline persistence, accessibility, and notifications.

## Current vertical slice

This milestone runs fully on-device. It creates fictional sample data on request, persists it with SwiftData, derives progress from active completion events, protects parent tools with Apple device-owner authentication or a local PIN, and schedules local reminders without a server.

## Product decisions

- Recognition comes before incentives: Quest → XP → Level → Badge → Collection → Reward.
- Completion events are source data; XP and streaks are projections.
- Shared quests require each participant to check in. Individual quests award each assigned participant independently.
- Household calendar calculations use the household time zone.
- Cosmetic unlocks, once granted, should be durable even if a completion is undone.
- No ads, trading, random rewards, gacha, or child-directed behavioral profiling.
