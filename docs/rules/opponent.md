# The opponent in a Drill run

What the other side plays. Code: `beginRun`, `regionSource` and
`opponentReply` (`OpeningRun.swift`), `bookReply` (`Run.swift`) and
`Strength.swift`. Tests: the `docs/rules/opponent.md` suite in
`Tests/SpecTests/Rules/OpponentRules.swift`. Freeform's opponent is in
[freeform](freeform.md).

1. **It follows a line of yours.** When the run starts, one of your lines
   that passes through the start position and reaches the run's opening is
   drawn, and the opponent plays its moves.
2. **Lines that ask at least 4 of your moves are drawn first.** Shorter ones
   are drawn only when there are no longer ones.
3. **Never the same line twice running,** while there is another to draw.
4. **The draw is weighted.** Each line weighs how often the book's players
   reach it, times how long it has been left (see
   [scheduling](scheduling.md)). A Review run also multiplies by how weak the
   line's positions are; a Test run doesn't.
5. **A run that heads for a gap follows the gap's line** while it is on it.
6. **Off the drawn line, a new one is drawn** from where the run stands, by
   the same rules.
7. **With no line of yours to follow,** it plays a reply your Playbook has
   there or one played in at least 5% of strong players' games, weighted by
   how often it is played. Replies that keep the run in your lines or the
   book come first.
8. **Past the book, the engine plays at your strength,** rounded to the
   nearest 50.
9. **Your strength** starts at 1200. Each of your moves the engine judges
   moves it by 0.3 × (what a player of your rating loses on average − what
   the move lost, counted at most 300 centipawns), by at most 40 points a
   move, between 600 and 2200.
