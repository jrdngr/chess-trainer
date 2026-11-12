# What the Playbook holds

Code: `BookMoves.swift`, and the save and board-building sheets in the app.
Tests: the `docs/rules/playbook.md` suite in
`Tests/SpecTests/Rules/PlaybookRules.swift`.

1. **Only book moves.** A move is a book move when the book has it at that
   position, however rarely it is played. Saving a line keeps it up to the
   first move the book lacks, for either side, and growth only offers book
   moves (see [growth](growth.md)).
2. **A save from before keeps only book moves.** On load, every move the
   book lacks goes, yours or the opponent's, with everything under it and
   the cards of the positions that went (see [saves](saves.md)).
