# What the Playbook holds

Code: `BookMoves.swift`, `PlaybookMap.swift`, `NodePage.swift`.

Moves come in only through growth, choosing your openings, buying them
on the tree, and Tidy's switch (see [tidy](tidy.md)). Nothing is saved by hand.
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
3. **A tap opens an opening's branches;** a tap on the open one folds it.
   The tree stands on four columns. A row of branches starts under its
   opening, so the open path runs straight down. A row of more than four
   hangs off its opening's trunk: lines of three beside the trunk, then a
   last line of up to four that ends it. A locked opening
   shows when it grows: "~2 games" for Next, "Game 40" or "Green 7/9" for a
   level, "In line" for a hole further down the curve.
4. **An opening's page is about its position.** A tap on an opening you
   have opens its page. Its board stands at the opening's position and steps
   back through your moves to it; an opening you reach in
   another order than the book's opens at your order, and one your lines
   reach only past it, in another order, opens at the book's; Analysis opens
   from there.
   **View lines** walks on past it: in place of the page's cards it lists your
   Playbook's moves from the board's position, under whichever of your move
   orders they hang, in the Playbook's order, and a
   tap plays one. Each move is followed, dimmed, by up to the next 3 moves of
   its line (`VIEW_LINES_AHEAD`): your preferred move on your turn, the first
   reply in your Playbook on theirs. The back arrow at the top returns to the page at the opening. The page
   shows the opening's form at your move: its last 10 answers to that move
   and their average (see [form](form.md)).
5. **Grow waits for the curve.** Grow fills the first hole under the
   opening that an open level allows (see [growth](growth.md)). It starts a
   Play run at the hole, the moves to it played for you, and growth opens
   there at once; a hole at Black's first move starts from move one. The run
   is a Play run like any other, played on this opening without changing
   Home's, and its X returns to the page. Otherwise the
   page says what it waits for. Holes in open levels elsewhere grow first, so
   it names the next of them and how many there are. Failing that, it shows
   the games and green openings its first hole's level needs. With no hole
   under the opening, there is no Grow.
6. **Select** makes the opening Play's, as if it were picked in the opening
   picker, so Play and Middlegame draw their lines through it. It shows only
   once the opening picker is yours.
7. **Delete** takes the opening's last move and everything after it, with
   an undo. It's offered only past the named position of an opening you
   have, or on lines outside all of them: an opening you have stays yours
   (see [openings for sale](families.md)). In View lines, Delete takes the
   move on the board past the opening, by the same rule, and the board steps
   back one move. Nothing else edits the Playbook by hand.
8. **Tags are Sharp, Solid, Gambit and System.** An opening's tag comes from
   the picker's shelf it sits on, its own or the nearest above it; other
   shelves tag nothing. The card at the bottom shows the open opening's tag
   as a word in its color; the tree shows none. Code: `shelfOf` in `PlaybookMap.swift`.
