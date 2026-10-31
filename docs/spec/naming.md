# Names and the opening catalogue

How positions are matched, what the book calls a line, and the catalogue of
openings every selection, region and rating hangs off. The book is
`src/model/reference.ts`; the catalogue is `src/model/openingTree.ts`.
Every opening in today's book is pinned in `openingTree.node`, so a port on the
same book must build the same catalogue.

## Positions and move text

**NAME-1** · port
A position is matched by its key: the board, side to move, castling rights
and en passant square, without the move counters. Two move orders that reach
the same key are the same position everywhere in the app.
Source: `core.positionKey`
Cases: `core.positionKey`, `repertoire.shape`

**NAME-2** · port
A line is written with move numbers ("1. e4 c5 2. Nf3"); a single move is
labelled after itself, "1.e4" for White and "1...c5" for Black.
Source: `core.sansToMoveText`, `openingTree.moveLabel`
Cases: `core.sansToMoveText`, `openingTree.moveLabel`

## What the book calls a line

**NAME-3** · port
A line is called by the deepest name the book gives along it, with that
name's ECO code and the ply it was given at. The names are read by position,
so a transposed line takes the name of the position it reaches. A line with
no name anywhere along it has none.
Source: `reference.deepestName`, `reference.namesAlong`
Cases: `reference.deepestName`, `reference.namesAlong`

**NAME-4** · port
A name's family is the part before its colon, read as the shortest name the
book gives on its own that is that part or starts with it; when the book has
none, the part before the colon stands. A name with no colon, or one the book
never gives, is its own family.
Source: `reference.familyName`
Cases: `reference.familyName`

**NAME-5** · port
Game counts are written short: as they are under 1,000; one decimal of
thousands under 10,000 ("1.1k"); whole thousands under a million ("99k");
one decimal of millions under 10 million ("1.3M"); whole millions above.
Source: `reference.formatGameCount`
Cases: `reference.formatGameCount`

## The catalogue

**NAME-6** · port
The catalogue is built from the book: Any opening at the top, every first
move the book plays under it (named by the book or by its move label), and
every named catalogue entry. An entry sits under the deepest entry whose
moves it extends, unless that one is of another family and its own family is
an entry: then it sits under its family, so a King's Indian Fianchetto is
inside the King's Indian. A parent chain that would loop is cut at the first
move. Openings under each are ordered by games, then name.
Source: `openingTree.buildOpeningTree`
Cases: `openingTree.node`, `openingTree.ancestorsOf`

**NAME-7** · port
A selection is a line of moves. One in the catalogue is that opening; a legal
line the catalogue lacks is a custom opening one level under the deepest
opening it passes, with that opening's name; anything else is Any opening.
Source: `openingTree.nodeById`
Cases: `openingTree.nodeById`

## Regions

**NAME-8** · port
An opening as a region is its own position and every variation's under it;
reaching any of them, by any move order, is reaching the opening. A line is
"reached" once it lands in one, "on its way" while every position so far is
one the book can get there from, and "outside" from the first position that
is neither. Any opening is reached by everything.
Source: `openingTree.regionOf`, `openingTree.approachOne`, `openingTree.lineStatus`
Cases: `openingTree.lineStatus`

**NAME-9** · port
A line belongs to the deepest catalogue opening whose position it passes,
the deepest by catalogue depth, ties to the later. This is what a line is
called in the app and where its rating goes. Steering inside a selection uses
the deepest such opening under the selection, else the selection itself.
Source: `openingTree.deepestNodeAlong`, `openingTree.deepestNodeWithin`
Cases: `openingTree.deepestNodeAlong`, `openingTree.deepestNodeWithin`, `survival/clean-prep-into-the-book`

## Conflicts for the owner

None found so far in this area. One oddity is kept as the book has it: the
book names 1.d4 Nf6 2.c4 g6 3.Nc3 the King's Indian Defence, so the Grünfeld
sits under the King's Indian in the catalogue (see the comment in
`buildOpeningTree`).
