# What the next run is

How Play picks each run: the opening, the side and the focus. Code:
`nextRound` (`Rounds.swift`), `recommend` (`Recommend.swift`) and the
questions in `Recommendations.swift`; the first two steps are in
`PlayView.make`. Tests: the `docs/rules/next-run.md` suite in
`Tests/SpecTests/Rules/NextRunRules.swift`.

1. **The order.** The first match wins:
   1. the tutorial's next game, whatever is selected;
   2. with nothing in the Playbook, a first game as White from move one, in no opening yet;
   3. Black's first runs (rule 2);
   4. a Freeform round, when Home's switch is on Freeform (see [freeform](freeform.md));
   5. a run that heads for a gap, when a new move is due (rule 3);
   6. the recommendation (rules 4 to 9), started by the [Drill rules](drill.md).
2. **Black's first runs.** On Any Opening with Black or Either, while Black
   has no answer to 1.e4 or to 1.d4, the run is Black from move one: the
   opponent plays the move with no answer (1.e4 first), and growth opens
   there. A specific opening picked on Home never gets these runs.
3. **A new move is due after Moves per fill runs.** Pace is the Play runs
   since anything was added to the Playbook, from any source, over Moves per
   fill (default 3). From a pace of 1, the run heads for the selection's gap
   with the highest p × m² × g, if that is at least 1 (see
   [growth](growth.md)). Only gaps past at least one move of yours count: a
   White first move with no answer is left to Home's Recommendations.
4. **Candidates.** For each side the selection covers that has a Playbook,
   each opening at or below the selection where you have a move gets a
   Review candidate. The selection itself also gets a Test candidate.
   Neither is a candidate with a need of 0.
5. **Review's need** is the larger of 0.9 × due ⁄ (due + 24) and
   0.5 × new ⁄ (new + 4), where due counts your positions in the opening
   with a need of 1 or more (see [scheduling](scheduling.md)) or that your
   own games went off prep at, and new counts positions never asked, at most 8.
6. **Test's need** is 0.4 + 0.4 × added ⁄ (added + 10), at least 0.55
   before your first run, times 0.25 + 0.75 × how long your stalest line in
   the opening has been left (0 to 1). "Added" counts your moves in the opening
   added since its last run, and "your first run" means any run at all. Both
   read the run history under the old Play mode's name, which no round
   records any more. So every move counts as added and no run as played.
7. **Score.** need × (1 + 2 × freshness) × 0.6^levels × 0.5^recent:
   - freshness is 1 for the candidate run longest ago, falling evenly to 0
     for the most recent;
   - levels counts how far below the selection the opening is;
   - recent counts runs of the same focus among the session's last 5.

   The highest score wins. Ties go to the higher need, then Test before Review,
   then opening, then side.
8. **A winning Review narrows.** It moves down to the variation below it
   with the most Review work, as long as that variation holds more than
   level ⁄ (level + 1) of its parent's work (half at the first level, two
   thirds at the second), and so on down.
9. **Steering pauses.** After a run in an opening below the selection, the
   next 3 runs are on the selection itself. Freeform runs never count as
   steered.
10. **The session remembers its runs.** The focuses and steered flags of
    rules 7 and 9 are kept in memory only, from when the app loads a profile
    until it is closed or the profile changes.
11. **On Either, the recommendation picks the side.** On White or Black, the
    side is the picked one.
