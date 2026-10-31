# The Playbook

Your prep: one tree of moves per side, what each move is, where it came from,
and the mistakes log. The tree is `src/model/repertoire.ts`; move kinds are
`src/model/extensions.ts`. "Playbook" is the UI's name for what the code
calls a repertoire.

## The tree

**BOOK-1** · port
Each side has one tree. Adding a line reuses the moves already there and adds
the rest. The first move added from a position is the preferred one. Every
move keeps where it came from and when it was added.
Source: `repertoire.addLine`, `repertoire.addMove`
Cases: `repertoire.shape`

**BOOK-2** · port
The positions you answer are found by position, not by move order: a
position reached two ways is one position to answer, with the moves from both
routes as its options, preferred first.
Source: `repertoire.decisionPoints`, `session.allItems`
Cases: `repertoire.shape`

**BOOK-3** · port
Removing a line takes its moves and every move that only led to it, up to the
first position where something else branches off. Removing the preferred move
makes the first remaining sibling preferred.
Source: `repertoire.pruneLine`, `repertoire.pruneCount`, `repertoire.removeSubtree`
Cases: `repertoire.pruneLine`

**BOOK-4** · port
Where a move came from is one of: Opening picker, Book, Growth, Engine,
Entered by hand, Analysis, Imported games, Play game, Tidy switch, Play on the
board, Sample. A move with none reads Entered by hand. Growth labels a move
Growth when the book has it and Engine when it doesn't.
Source: `moveSource.SOURCE_LABELS`, `moveSource.sourceLabel`, `moveSource.growthSource`; user-added-replies (10-02)
Cases: `moveSource.sourceLabel`, `moveSource.growthSource`, `const:SOURCE_LABELS`

## What a move is

**BOOK-5** · port
Each of your moves is a book move (at least 5% of strong players' games at
that position, and not a mistake), rare (sound, but under 5% or not in the
book where the book has the position), a mistake (the engine says it gives
away more than 80cp), or past the book (the book has no games at the
position). The kind is worked out from the book loaded, never stored; only
the engine's loss is kept on the move.
Source: `extensions.moveKind`; extensions-design (10-24)
Cases: `extensions.moveKind`, `const:BOOK_SHARE`, `const:BLUNDER_LIMIT`

**BOOK-6** · port
The opponent's moves are always book, however rare. Once one of your moves
leaves the book, your later moves on that line are extensions too: a book
move under an extension reads as rare.
Source: `extensions.lineKinds`, `extensions.treeKinds`, `extensions.bookLength`
Cases: `extensions.lineKinds`, `extensions.bookLength`, `extensions.movedBy`

## How often the opponent plays your replies

**BOOK-7** · port
Where the opponent chooses from the book, every reply you prepared comes up at
least 15% of the time, the lifted replies taking at most half of the position
between them; the book's other moves are scaled to make room.
Source: `prepFloor.withFloor`; user-added-replies (10-02)
Cases: `prepFloor.withFloor`, `const:PREPARED_FLOOR`, `const:MAX_LIFTED`

## Mistakes

**BOOK-8** · port
A miss is logged as a mistake at its position. The log keeps one entry per
position, the latest miss there, newest last, and at most 200. A right answer
at the position clears it.
Source: `mistakes.addMistake`, `mistakes.recentMistakes`, `lineDrillController.answer`, `useStore.grade`
Cases: `mistakes.addMistake`, `mistakes.recentMistakes`, `drill/lines-a-group`, `const:MISTAKE_LIMIT`

## The Playbook tab

**BOOK-9** · port
The Playbook tab lists each side's tree by family: a region of the tree
joins the row of its family, and a region of another family starts its own
row even inside one (the King's Indian under the Indian Defence's 1...Nf6).
A row with no lines of its own is only a way in and is not listed. Each row
has its ECO (the family's own position where the tree passes it), its moves,
lines, depth, and what deleting it removes. A Black row the book names after
White's moves (King's Pawn Game, King's Knight Opening, Queen's Pawn Game,
Zukertort Opening) is called by Black's first move, "1...e5", unless two rows
would share that label.
Source: `openings.familiesIn`, `openings.nameForBlack`, `RepertoireScreen`; onboarding-redesign (10-24)
Cases: `openings.familiesIn`

**BOOK-10** · port
Elsewhere (Browse, Extensions, the onboarding board) a tree's openings are
its named regions, biggest first, each with its variations. A name that only
leads somewhere is dropped: the first move's name when anything is named
under it, and a region with no lines of its own and exactly one region under
it.
Source: `openings.openingsIn`, `openings.collapse`
Cases: `openings.openingsIn`

**BOOK-11** · port
Inside a family each line is named for the deepest name it reaches, with the
family's name taken off its front ("Najdorf Variation" under the Sicilian); two lines that reach the same name are told apart by the
move they split off at. Deleting a line removes the moves only it owns, and
the family's first moves too when it is the family's only line.
Source: `openings.linesOf`
Cases: `openings.linesOf`

## Settled

- The King's Indian by 3.Nf3 g3 is its own King's Indian row, as the code does it.
- A tree holding only 1.e4 e5 is listed as King's Pawn Game, as the code does it.

The owner ruled on 10-31 that the code is the truth: both are ported as they are.
