# What the Playbook holds

Code: `BookMoves.swift`, `PlaybookMap.swift`.

Moves come in only through growth, choosing your openings, and buying
them on the tree. Nothing is saved by hand.
Tests: the `docs/rules/playbook.md` suite in
`Tests/SpecTests/Rules/PlaybookRules.swift`.

1. **Only book moves.** A move is a book move when the book has it at that
   position, however rarely it is played. Adding a line keeps it up to the
   first move the book lacks, for either side, and growth only offers book
   moves (see [growth](growth.md)).
2. **The tab is a tree.** One side at a time, the first moves on top. Under
   each opening hang the named openings your lines reach next, most played
   first, and after them the openings the curve will add (see
   [growth](growth.md)), locked, under the nearest opening you have, the
   Next one first, and after them the openings on the list you don't
   have, for sale (see [families](families.md)). Exactly one opening on the tree is Next. Home's Next line
   names it and when it grows, and opens the tree at it. Code:
   `PlaybookMap.swift`.
3. **A tap opens an opening's branches;** a tap on the open one folds it. A
   row of more than four goes on two tiers, yours above and locked below,
   or in halves by rank when either holds more than four. A locked opening
   shows when it grows: "~2 games" for Next, "Game 40" or "Green 7/9" for a
   level, "In line" for a hole further down the curve.
