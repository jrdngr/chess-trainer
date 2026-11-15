# Form

How each opening's signal bars are read. Code: `Form.swift`, and
`EndgameMode.swift` for Endgames families. Tests: the `docs/rules/form.md`
suite in `Tests/SpecTests/Rules/FormRules.swift`.

1. **An answer's score.** A prepared move found in under 3 seconds scores
   1, in 3 to 8 seconds 0.8, slower 0.5. A miss scores 0.
2. **An opening keeps its last 10 answers.** An answer counts for the
   opening its position is in and every opening above it.
3. **Bars from the average.** 3 bars at 0.8 or above, 2 from 0.5, 1 below.
   Under 5 answers, the opening has no form yet and shows dashes.
4. **Endgames families** keep their last 5 rounds, each a goal met or not,
   and read them the same way: 3 bars at 4 or 5 goals met of 5, 2 at 3, 1 at
   2 or fewer. Under 3 rounds, dashes.
