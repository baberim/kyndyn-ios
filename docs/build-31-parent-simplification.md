# Build 31 — Parent simplification and reward history

Build 31 makes protected family management easier to understand without
changing permissions, sync ownership, or the offline-first data model.

## Parent navigation

The Parent dashboard keeps Create a quest, Add a person, and Share an
announcement as quick actions. Everything else is grouped into four clear
destinations:

- Family and quests
- Rewards and progress
- Family sync
- Device and privacy

These groups remove duplicate entries while preserving every existing tool.

## Family-friendly language

Visible callouts now explain outcomes in ordinary language. Developer-only
CloudKit configuration details remain available in Debug builds but are hidden
from release users. Privacy and recovery guidance remains explicit without
exposing internal record or synchronization terminology.

## Reward history

The family reward screen lists concluded reward cycles newest first. Each row
shows the reward name, ending progress, date, and whether the goal was reached
or changed. History uses the synchronized reward-cycle facts introduced in
Build 30, so it does not alter profile XP, levels, streaks, or quest history.

Report exporting is not included because it does not currently solve a
demonstrated family need.

## Validation

- iPhone 17 Pro simulator build passed.
- iPad Pro 13-inch simulator build passed.
- 103 unit tests passed; one full-suite simulator process crash passed when
  rerun independently and produced no assertion failure.
- Six affected parent-navigation and reward UI journeys passed, including
  creating a new reward cycle and finding its history.
