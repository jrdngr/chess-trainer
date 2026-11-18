# Form

How each opening's form is read: a number from 0 to 1, shown as a ring
that fills clockwise and runs from red to green. Code: `Form.swift`, and
`EndgameMode.swift` for Endgames families. Tests: the `docs/rules/form.md`
suite in `Tests/SpecTests/Rules/FormRules.swift`.

1. **An answer's score.** A prepared move found in under 3 seconds scores
   1, in 3 to 8 seconds 0.8, slower 0.5. A miss scores 0.
2. **An opening keeps its last 10 answers.** An answer counts for the
   opening its position is in and every opening above it.
3. **Form is the average** of the answers kept. Under 5 answers, the
   opening has no form yet and its ring is an empty track.
4. **Endgames families** keep their last 5 rounds, each a goal met or not,
   and read them the same way: the share of them with the goal met. Under 3
   rounds, no form yet.
5. **Each side has its own form.** An answer playing White counts only for
   White's form, one playing Black only for Black's, so White's 1.e4 and
   Black's answers to it never mix. A page that shows an opening without a
   side shows the side whose Playbook holds it, else the side whose move
   names it. Saves from before the split read their form as White's.
