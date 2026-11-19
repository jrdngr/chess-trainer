# Tidy

Code: `Tidy.swift` (Model), `TidyScan.swift` (Game). What Tidy is for:
[tidy](../tidy.md).

Tidy finds the places where another move would bring your lines together,
and switches to it on request. Tests: the `docs/rules/tidy.md` suite in
`Tests/SpecTests/Rules/TidyRules.swift`, and the Tidy flow in
`Tests/FlowTests/TidyFlowTests.swift`.

1. **What it looks at.** Every move you chose, in every playbook, both
   sides in one list. A position reached by two move orders is looked at
   once. Your first move of a game is never a find.
2. **What counts as a find.** A book move other than yours, at or above the
   book's minimum share, that reaches the rest of your lines better than
   yours does: it **transposes** (lands on a position you have, now or after
   at least a quarter of the replies), or failing that it **heads toward**
   one (a common reply and then one move of yours land on it). Your move is
   judged without its own subtree. A move you play in similar positions
   elsewhere (a habit) is never a reason.
3. **Eval decides.** Of the moves that count, the one that gives up the
   least against the best move is offered: the book's Stockfish table where
   it has the position, otherwise the engine. A move giving up more than
   `CLEARLY_WORSE_CP` beyond yours is never offered. A position waits off
   the list until every loss it needs is known.
4. **The card's two lines.** Both start where the lines split. The target
   line plays the switch, the book's most played moves to the position you
   have, then up to 3 moves of your Playbook from there
   (`TIDY_KNOWN_STEPS`). The current line plays your move and then the same
   number of moves, or fewer if it ends: your preferred move on your turn,
   the book's most played of your replies on theirs.
5. **The list.** Most moves removed first, then the earliest. The Playbook
   tab shows the count while it is above 0.
6. **Switch these moves.** The offered move becomes yours there and your
   move goes with everything under it. The position's card starts over and
   the misses logged there are cleared. An undo puts it all back.
