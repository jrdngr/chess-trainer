# Growth inside a run

How a Play run adds moves to your Playbook. Code: `Recommendations.swift`
(gaps, pace, mastery and the question at a hole), `prepRanOut`
(`RunController.swift`) and `askAtHole`, `addMove` and `fillReply` in
`RunModel` (Game target). Tests: the `docs/rules/growth.md` suite in
`Tests/SpecTests/Rules/GrowthRules.swift`.

1. **A gap** is a common reply with no answer in your Playbook:
   - the reply is played in at least 5% of strong players' games at its position;
   - it is still inside the opening the book names along that line;
   - you meet it in at least 2% of your games, after a 0.85 discount for each full move of depth.

   A reply where you answer others, or at move one, is "no answer yet". A
   line that just stops is "too short", and is one gap, at its most played
   reply.
2. **A run reaches at most one hole.** That is the first time it is your
   turn with no move of yours. Your prep must have been followed without a
   miss, and the run must be past the moves played for you. Only Play runs
   reach holes.
3. **The question at the hole.** The answer is yes when p × m² × g ≥ 1
   and the gap is past at least one move of yours. The gap is looked up among
   the selection's gaps, or the whole Playbook's when the selection has none
   or doesn't hold it. A run set to grow at a gap (see [drill](drill.md) and
   [next run](next-run.md)) grows there whatever the answer.
4. **p, pace,** is the Play runs since anything was added to the
   Playbook, over Moves per fill (default 3).
5. **m, mastery,** is the average over your moves from move one to the
   hole. Each move scores its share of right answers × (0.6 + 0.4 × how fast),
   where fast is the card's ease from 1.3 (0) to 2.5 (1). A move never asked
   scores 0. A line with no move of yours yet scores 1.
6. **g** is the gap's importance next to the selection's top gap, at most 1.
7. **On a yes, the board turns into New move.** It offers the answers a
   Growth sitting would offer, and each pick is saved as it is made. The
   opponent replies along the gap's line while it can, then with the book's
   most played reply. It stops after Moves per fill of your moves, at the end
   of the named opening, or when no reply is played in 5% of games. Done
   stops it at any time; Undo takes the last pick back out.
8. **New moves aren't graded that run.** They count in the book's color,
   and later runs drill them.
9. **On a no, a Grow here button shows** while it is your move at the
   hole. It starts the same New move.
10. **Growth never goes past the book.** See [playbook](playbook.md).

Rules 2 (the conditions), 7 (the replies) and 9 live in `RunModel` and
have no test yet; `HeadlessApp` flow tests can cover them.
