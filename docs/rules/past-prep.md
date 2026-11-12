# Misses, blunders and the book after your prep

How a run judges your moves and when it ends. Code: `RunController.swift`,
`Run.swift`, `judgeByEval` (`OpeningRun.swift`) and `Endgame.swift`.
Tests: the `docs/rules/past-prep.md` suite in
`Tests/SpecTests/Rules/PastPrepRules.swift`.

1. **A prepared move is graded, and its time shown.** The card is reviewed
   by speed (see [scheduling](scheduling.md)).
2. **A miss never ends a run.** A move other than your prep's, if it isn't
   a blunder, fails the card, logs the miss, shows the prepared move as a
   green arrow, and the game goes on.
3. **A run ends at a blunder, or when the game is over.** Past or off your
   prep, a move that gives away more than the blunder line ends the run.
   The line is 80 centipawns, plus 0.25 for each centipawn you lead by past
   +1. Checkmate and draws end it too. The X ends it at any point.
4. **The book phase.** Once your prep runs out without a miss, the run is in
   the book phase for as long as the position is in the book.
5. **A book move** is played in at least 5% of strong players' games there
   and gives away 40 centipawns or less. It gets a quiet tick with its time,
   keeps the combo going as if it cost nothing, and never moves a card.
6. **Any other move ends the book phase,** and costs nothing for it. So
   does a position the book has nothing for.
7. **Moments only count past your prep.**
8. **Endgame rules** start once the game has reached at most 8 points of
   material (knight or bishop 1, rook 2, queen 4) and stay on after. A move
   then fails only when the result it keeps is worse than before and it also
   gives away more than 80 centipawns. Scores are held within ±600
   centipawns for this, and +300 or better counts as a win. Where a
   tablebase knows the exact results, any worse result fails.
9. **A missed mate in a won ending doesn't end the run.** It says "Missed
   mate", and the board shows the move.
10. **An endgame given away is kept** for Endgames to replay (see
    [endgames](endgames.md)).
