# Home

The first tab: the selection, the Autopilot button, the four mode tiles, and
three cards (Survival runs, Favorites, Milestones). The screen is
`src/screens/HomeScreen.tsx`; the cards are `src/components/HomeWidgets.tsx`;
milestones are `src/model/milestones.ts`.

## The top

**HOME-1** · port
Home leads with the selection bar (Settings is a gear on its row), the score
strip, and the Autopilot button. The button shows the opening Autopilot would
start with, by name, on a small board of its moves, with its side and how
far into your prep it would start along the bottom edge. With nothing to
practice it reads "Nothing to practice yet · open Growth" and opens Growth.
Under it are four tiles, icon and name only: Survival, Drill, Growth, Play.
Source: `HomeScreen`, `autopilot.roundSpan`, `recommendation.pickRound`; home-screen-rework (10-08), autopilot-naming (10-23)
Cases: `e2e:autopilot-first-runs`, `autopilot.prepDepth`

## Survival runs

**HOME-2** · port
A chart of moves survived in the last 16 runs, the latest at the right and
accented, with a dashed line at the best. It follows the selection: one
opening's runs, or every run under Any opening and Any favorite. Runs you
ended yourself are not in it.
Source: `HomeWidgets.SurvivalRuns`, `survival.survivalFor`; home-screen-rework
Cases: `survival.recordSurvival (runs)`, `const:HISTORY_RUNS`

## Favorites

**HOME-3** · port
Every favorite with its side, tier bar and rating, rated ones first and then
highest first, and how far the rating moved in the last 7 days as an arrow
and a number ("–" when it didn't move, nothing when unrated). The change is
the rating now less where it stood at the end of the last day, at or before
a week ago, that moved it. A favorite with an Extensions rating has a second
row for it. Tapping a row selects that opening with its side.
Source: `HomeWidgets.FavoritesLadder`, `scoring.ratingChange`, `scoring.ratingOn`
Cases: `scoring.ratingChange`, `scoring.ratingOn`

## Milestones

**HOME-4** · port
There are 18 milestones, all read from what the app already records, so
anything done before they existed counts: a longest streak of 3, 7 and 30
days; a Survival best of 10, 20 and 30 moves; a first opening whose peak
rating reached Familiar, Solid, Strong, Fluent and Mastered; 3, 5 and 10
families (second-rung openings, such as 1.e4 c5) whose peak reached
Familiar; and 100, 500, 1k and 5k rounds in any mode. A peak is the highest
of an opening's end-of-day ratings and its rating now.
Source: `milestones.milestones`, `milestones.longestStreak`, `milestones.peakRating`
Cases: `milestones.milestones`, `milestones.longestStreak`, `milestones.peakRating`

**HOME-5** · port
The card shows "N of 18", leads with the current streak (days in a row with
a round, up to today, or up to yesterday while today has none), ringed toward
the next of 3, 7 and 30, then the three unearned milestones closest to done,
ties in list order. Tapping it opens every milestone. Earning one shows a
toast when a round is recorded, never for what was already earned when the
app opened.
Source: `HomeWidgets.MilestonesCard`, `HomeWidgets.useMilestoneToasts`, `scoring.streak`, `milestones.nextUp`
Cases: `scoring.streak`, `milestones.nextUp`

## Conflicts for the owner

None found so far in this area.
