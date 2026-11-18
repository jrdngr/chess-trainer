# Growth inside a run

How the Playbook grows. Code: `Curve.swift` (holes, levels, the gate, calm
answers and unlocking), `Recommendations.swift` (gaps, pace and the question
at a hole), `prepRanOut`
(`RunController.swift`) and `askAtHole`, `addMove` and `fillReply` in
`RunModel` (Game target). Tests: the `docs/rules/growth.md` suite in
`Tests/SpecTests/Rules/GrowthRules.swift`.

1. **A hole** is a reply with no answer in your Playbook that the curve
   can grow:
   - the reply is played in at least 5% of strong players' games at its position;
   - it is still inside the opening the book names along that line;
   - at least 1% of your games meet it: the share of games reaching its
     position times the reply's share there.

   Holes are ranked by that last number, most met first. Where a line just
   stops, its most played reply is "too short"; every other hole is "no
   answer yet". (The older gap list, `gaps`, still names a line that stops
   as one gap at its most played reply; Grow here uses it.)
2. **A run reaches at most one hole.** That is the first time it is your
   turn with no move of yours. Your prep must have been followed without a
   miss, and the run must be past the moves played for you. Only Play runs
   reach holes.
3. **The curve grows depth first.** Each hole has a level: 1 or 2 when it
   is "no answer yet" at the opponent's first or second move, so it leaves
   your openings there; 0 for every other hole. Level 0 is always open.
   Level 2 opens once no hole is left in the open levels, you have played
   20 Play games, and every opening you have is green (rule 5). Level 1
   opens the same way after level 2, at 40 games. The curve's next hole is
   the most met hole in the open levels; for a selection, the most met one
   inside it, with the levels opened by the whole Playbook.
4. **The question at the hole.** The answer is yes when the pace (Play runs
   since anything was added to the Playbook, over 3)
   has reached 1 and the hole is the curve's next one in the selection. A run
   set to grow at a gap (see [drill](drill.md), [next run](next-run.md) and
   an opening's Grow in [playbook](playbook.md)) grows there whatever the
   answer.
5. **Green** is an opening's form (see [form](form.md)) of at least 0.8 over
   at least 5 answers. The openings that count are the deepest named opening
   each of your lines reaches, on the sides the curve grows: White, and
   Black once the side picker is yours.
6. **The opponent plays only what you have unlocked.** Where your Playbook
   has replies, it plays only those (see [opponent](opponent.md)); a hole
   is met in a run only on the way to a gap.
7. **On a yes, the board turns into New move.** It offers the book's most
   played answers, and each pick is saved as it is made. The
   opponent replies along the gap's line while it can, then with the book's
   most played reply. It stops after 3 of your moves, at the end
   of the named opening, or when no reply is played in 5% of games. Done
   stops it at any time; Undo takes the last pick back out.
8. **New moves aren't graded that run.** They count in the book's color,
   and later runs drill them.
9. **On a no, a Grow here button shows** while it is your move at the
   hole. It starts the same New move. Where a line just stops, every reply
   played in at least 5% of games there gets the button, not only the gap's
   most played one; only that one is asked about.
10. **Growth never goes past the book.** See [playbook](playbook.md).
11. **As Black, the calmest answer goes first.** Of the three most played
    answers to a new reply, the one whose opening is least sharp leads the
    answers offered and is the one an unlock adds; the rest keep their order.
    As White the order stays.
12. **Growth stays inside your openings.** A hole is only a hole past the
    start of an opening you have (see [families](families.md)); anything
    else is bought, not grown. There is no early unlock; a locked variation
    opens only through the curve.

Rules 2 (the conditions), 7 (the replies) and 9 live in `RunModel` and
have no test yet; `HeadlessApp` flow tests can cover them.
