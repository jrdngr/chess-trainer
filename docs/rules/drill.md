# Drill: where a run starts

What a Drill run does before your first move. Code: `drillStart`
(`DrillStart.swift`) and `nextRound` (`Rounds.swift`). Tests: the
`docs/rules/drill.md` suite in `Tests/SpecTests/Rules/DrillRules.swift`.

1. **A run starts at one of your moves.** The moves before it are played for
   you, and the board opens with that move yours to play.
2. **The most due move comes first.** Within the run's opening, the start is
   your move with the highest need (see [scheduling](scheduling.md)). A move
   no run has asked yet counts as the most due.
3. **With nothing due, weakness or closeness decides.** While your prep keeps
   missing (under 95% found over your last 5 runs on that side), the start is
   your weakest move: lapses count double, plus misses, minus right answers.
   Otherwise it is the move closest to due.
4. **Never your first move as White.** A run never starts at the starting
   position, so it never asks which first move a given opening wants.
5. **Nothing to start at: move one, then grow.** When the opening holds no
   move of yours past White's first, the run starts from move one, follows
   the opening's top gap, and grows there whatever the line's need (see
   [growth](growth.md)).
6. **A run that heads for a gap starts on the gap's line.** It starts at your
   move most due among those on the line before the reply, by rules 2 to 4.
   With none of yours on the line, it starts from move one and grows at the
   gap.
