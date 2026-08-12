# Build 17A — Weekly Family Insights

Build 17A adds protected, deterministic weekly summaries without introducing
a new analytics service or CloudKit record type.

## Parent experience

- Parent includes a compact weekly preview with completed, not-completed, and
  earned-XP totals.
- Parent > Insights provides this week, last week, and earlier-week navigation,
  a seven-day completion chart, family totals, and individual summaries.
- Each person has a four-week view of completed occurrences, completion rate,
  earned XP, current streak, and current level.
- A small Worth a look section surfaces factual observations about unfinished
  or concentrated activity without rankings, sibling comparisons, grades, or
  behavioral conclusions.

## Calculation rules

- The household time zone defines weeks and day boundaries.
- Today’s unfinished occurrences are Waiting. They become Not completed only
  after their scheduled day concludes.
- Future occurrences are excluded. Reversed completions do not count.
- Archived quests and people retain applicable historical activity but do not
  generate new expectations after archival.
- Parent-entered starting XP contributes to current level but never appears as
  weekly XP earned, a completion, a streak day, or a badge milestone.

## Privacy and deferred scope

All calculations run locally from existing household records. Nothing is sent
to an analytics or AI service, and the feature adds no child scoring or family
leaderboard. Reward-cycle history, PDF exports, scheduled reports, and hosted
notification delivery remain deferred to later milestones.
