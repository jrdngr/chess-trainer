# Form

How each opening's form is read: a number from 0 to 1, shown as a ring
that fills clockwise and runs from red to green. Code: `Form.swift`, and
`EndgameMode.swift` for Endgames families. Tests: the `docs/rules/form.md`
suite in `Tests/SpecTests/Rules/FormRules.swift`.

1. **An answer's score.** A prepared move found in under 3 seconds scores
   1, in 3 to 8 seconds 0.8, slower 0.5. A miss scores 0.
2. **An opening keeps its last 10 answers.** An answer counts for the
   opening its position is in and every opening above it.
3. **The Playbook shows form at your move.** An opening's page and its arc
   on the tree show its last 10 answers to your move there. Your move is
   the opening's own last move when that move is yours, else your move from
   its position, so 1.d4 d5 and 1.d4 d5 2.c4 both show 2.c4. These answers are read from your history, the prep
   answers and misses in the event log, not kept on their own. Green and
   everything else still read rule 2.
4. **Form is the average** of the answers kept. Under 5 answers, the
   opening has no form yet and its ring is an empty track.
5. **Endgames families** keep their last 5 rounds, each a goal met or not,
   and read them the same way: the share of them with the goal met. Under 3
   rounds, no form yet.
6. **Each side has its own form.** An answer playing White counts only for
   White's form, one playing Black only for Black's, so White's 1.e4 and
   Black's answers to it never mix. A page that shows an opening without a
   side shows the side whose Playbook holds it, else the side whose move
   names it. Saves from before the split read their form as White's.
