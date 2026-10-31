# Autopilot: what a round is and where it starts

Autopilot picks every run for you: the opening, the side, what the opponent
steers into, and where the run starts. What Autopilot is for is
[docs/autopilot.md](../autopilot.md); these are the rules that do it. The run
itself is [run.md](run.md).

## The recommendation

**AUTO-1** · port
A round is about one opening, on one side, with one focus: Test (the lines
you would meet) or Review (your weakest). Nothing is recommended when the
selection holds no prep for any side it covers; Autopilot never builds prep.
Source: `recommend.recommend`, `recommend.candidates`
Cases: `recommend.recommend`

**AUTO-2** · port
An opening is a candidate only when your prep goes past its own position. A
Review asks by its due and unseen positions (`recommend.reviewNeed`); a Test,
which is only ever the selection itself from move one, asks by the prep added
since it last ran and how long its lines were left (`recommend.testNeed`).
Source: `recommend.candidates`, `recommend.reviewNeed`, `recommend.testNeed`
Cases: `recommend.reviewNeed`, `recommend.testNeed`, `recommend.saturate`, `recommend.recommend`

**AUTO-3** · port
Candidates are scored by need, how stale each is against the others, how deep
below the selection it sits (a star takes a level off), and a brake on the
focus the last five rounds kept choosing. Ties go to need, then Test before
Review, then opening id and side.
Source: `recommend.rank`, `recommend.effectiveLevel`, `recommend.recentCount`
Cases: `recommend.rank`, `recommend.effectiveLevel`, `recommend.recentCount`, `const:BRAKE`, `const:DEPTH`, `const:STALENESS`

**AUTO-4** · port
A winning Review narrows to a variation inside it that holds most of its
work: half for a first move under the selection, two thirds for a family,
three quarters for a variation. A Test is never narrowed.
Source: `recommend.recommend`, `recommend.narrowingBar`
Cases: `recommend.narrowingBar`, `recommend.recommend`

**AUTO-5** · port
After a round steered into an opening below the selection, those openings are
closed for the next two rounds.
Source: `recommend.steeredRecently`, `recommend.isSteered`
Cases: `recommend.steeredRecently`, `recommend.recommend`, `const:STEER_GAP`

**AUTO-6** · port
A round on an opening two plies deep or more starts in its position; a round
on a first move, or on everything, starts from move one.
Source: `recommend.startsInside`
Cases: `recommend.recommend`

**AUTO-7** · port
Test steers toward the lines you would meet most; Review toward your weakest.
Source: `autopilot.LEAN_FOR`, `autopilot.survivalPlanFor`
Cases: `const:LEAN_FOR`

**AUTO-18** · port
A position you slipped off your prep at counts as due whatever its card
says: one your imported games went off prep at, or one in the mistakes log,
within the selection. Positions you kept reaching with nothing prepared do
not count. One slip alone is not enough to beat a Test; a few in one opening
turn the round into a Review of it.
Source: `recommend.recommend` (slipped), `store/recommendation.evidenceIn`, `repair.buildRepairs`
Cases: `recommend.recommend`, `repair.buildRepairs`

## Where a run starts

**AUTO-8** · port
A run that starts in an opening's position has three ways to start: a
position start (the moves to the opening's own position are played for you),
an inside start (the moves to one position deeper in), or a cold start (from
move one, the opponent steering toward the opening).
Source: `recommendation.nextRound`, `autopilot.startKind`; autopilot-survival-only (10-23)
Cases: `autopilot.startKind`, `e2e:autopilot-first-runs`

**AUTO-9** · port
Your positions split into the way in (before the opening's own position) and
inside (past it).
Source: `autopilot.splitItems`
Cases: `autopilot.splitItems`

**AUTO-10** · port
A position's need is counted in runs: the runs since one last asked it over
its gap, so 1 and over is due. The gap is 2 runs while it is being learned,
and its interval times 3 runs a day once known (at least 2). A position no
run has asked yet keeps to its date.
Source: `srs.runNeed`, `srs.runGap`; grow-from-autopilot (10-25)
Cases: `srs.runNeed`, `srs.runGap`, `const:RUNS_PER_DAY`

**AUTO-11** · port
The way in wants playing by the runs since its stalest move was last asked,
over 6. A move of the way in no run has asked counts as never played.
Source: `autopilot.coldNeed`
Cases: `autopilot.coldNeed`, `const:COLD_GAP`

**AUTO-12** · port
An inside start goes to the position inside the opening that is most
overdue. With nothing due while your prep keeps missing in runs (accuracy
under 95% over the last 5 runs), it goes to the one you answer worst, at need
1. Only positions with a card are candidates.
Source: `autopilot.insideStart`, `recommend.missingPrep`, `recommendation.prepAccuracy`
Cases: `autopilot.insideStart`, `recommend.missingPrep`, `const:ACCURACY_RUNS`

**AUTO-13** · port
The start is a position start unless another has more need: inside when a
position deeper in is due, cold when the way in is, the greater need when
both are (cold on a tie). Neither comes twice running, and a cold start comes
at least every 3rd run, counted across sessions.
Source: `autopilot.chooseStart`
Cases: `autopilot.chooseStart`, `const:COLD_EVERY`

**AUTO-14** · port
The first run of an opening is always a position start, whatever is owed.
Source: `autopilot.chooseStart`, `recommendation.nextRound`; grow-from-autopilot (10-25)
Cases: `autopilot.chooseStart`, `e2e:autopilot-first-runs`

**AUTO-15** · port
Where runs started is kept with the score, the last 6, so the every-3rd-run
rule holds across sessions.
Source: `scoring.recordStart`
Cases: `scoring.recordStart`, `e2e:autopilot-first-runs`

**AUTO-16** · port
The prep segments show how far your prep reaches along the run's line: the
way in played for you, then your prep on its first choice in every position,
up to the first move of yours it does not have.
Source: `autopilot.prepDepth`, `autopilot.roundSpan`; autopilot-naming (10-23)
Cases: `autopilot.prepDepth`

## Any favorite

**AUTO-17** · port
Under Any favorite, each round picks a side first (Random flips among the
sides that have a favorite), then one favorite of that side: the one played
longest ago most likely, each next one half as likely, never the last one
while another is there. With no favorite on the sides asked, the round is on
everything.
Source: `anyFavorite.resolveFavorite`, `anyFavorite.pickFavorite`; any-favorite
Cases: `anyFavorite.resolveFavorite`, `anyFavorite.pickFavorite`, `anyFavorite.favoritesIn`

**AUTO-19** · port
An Autopilot round never reads a mode's own setup. Its runs are Survival on
your lines with no clock and moments, missions and combo on, the Undefended
flash off; its only settings are the move scores and board glow.
Source: `autopilotPrefs.autopilotModes`, `autopilotPrefs.autoSurvival`; autopilot-own-settings (10-25)
Cases: `autopilotPrefs.autopilotModes`, `const:DEFAULT_AUTOPILOT`

## Settled

- **AUTO-12** ported as the code does it: any position with a card can be an inside start, including one only Drill has shown. The owner ruled on 10-31 that the code is the truth: docs/autopilot.md now says so.
