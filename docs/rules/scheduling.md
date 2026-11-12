# Scheduling

When a position wants asking again, counted in runs. Dates are kept only
to show. Code: `Srs.swift`, `Freshness.swift`, `weaknessFromCards`
(`OpeningRun.swift`) and `recordRound` (`Scoring.swift`). Tests: the
`docs/rules/scheduling.md` suite in
`Tests/SpecTests/Rules/SchedulingRules.swift`, and the golden cases in
`srs.json`.

1. **A run is a finished Play run.** Each one moves the run count on by
   one. Growth sittings and Middlegame rounds don't.
2. **Each of your positions has a card.** A run that asks it reviews the
   card. A right answer is graded by speed: under 3 seconds Easy, under 8
   Good, slower Hard. A miss is Again. The first answer a position ever gets
   counts as Good, however long it took.
3. **New cards are learned first.** A new card needs 2 right answers to be
   known, and a card that lapsed needs 1. Hard leaves a learning card where
   it is, and Easy makes it known at once.
4. **A known card waits its interval, in runs.** It becomes known at 3 runs
   (12 on Easy). Each right answer once it is due multiplies the interval:
   Hard by 1.2, Good by the card's ease, Easy by the ease × 1.3. Intervals
   stay between 3 and 1095 runs. Ease starts at 2.5, falls 0.2 on Again and
   0.15 on Hard, rises 0.15 on Easy, and never goes below 1.3.
5. **A miss on a known card halves its interval** (to at least 3 runs) and
   sends it back to learning. Relearned, it is known again at the larger of
   that interval and 3 runs.
6. **Asked early, a known card keeps its interval.**
7. **Need** is the runs since the card was last asked, over its gap: 2 runs
   while learning, its interval once known (at least 2). A need of 1 or more
   is due. A position no run has asked yet is due.
8. **Staleness** is how long ago a run last went through a position: 0 for
   the last run, rising to 1 after 3 runs or never. A line's staleness is its
   own tail's (the moves after it last parts from your other lines), times
   0.5 + 0.5 × its head's.
9. **Weakness** is how much a position wants practice when the opponent
   leans weak:
   - it starts at 1 (1.5 for a position never asked);
   - plus 2 for each of your games that went off prep there, at most 3;
   - plus 1.2 for each lapse, and 2 × (2.5 − ease);
   - plus 1 while learning, and 1 when due;
   - plus 2 × the share of answers that were misses.
