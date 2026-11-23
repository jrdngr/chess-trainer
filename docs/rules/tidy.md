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
   one (a common reply and then one move of yours land on it), or failing
   that it is a **habit**: you play it in at least `HABIT_MIN` similar
   positions elsewhere, and choose it there at least as often as you pass
   it up. A move that finishes a setup (such as ...Bg7 after ...g6) counts
   as a habit when at least `HABIT_MIN` of your other lines finish it the
   same way. A habit never replaces a move that is itself a habit. Your
   move is judged without its own subtree.
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
   the book's most played of your replies on theirs. A habit's card has one
   step: the switch.
5. **The list.** Habits last; otherwise most moves removed first, then the
   earliest. The
   Playbook tab shows the count while it is above 0.
6. **Switch these moves.** The offered move becomes yours there and your
   move goes with everything under it. The position's card starts over and
   the misses logged there are cleared. An undo puts it all back. A move
   on the way to an opening you own is never switched and never listed,
   the same as Delete (families rule 6).
7. **Tips.** The Playbook tab's Tidy button explains Tidy the first time it
   shows. Each kind of find (joins your line, can join your line, your
   usual move) explains itself on the first card of that kind, once. When
   several kinds are on the list unexplained, their tips follow one
   another in list order.
