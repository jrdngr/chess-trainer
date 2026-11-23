# The Play screen

How a run is shown, ended and dealt. Code: `PlayView` and `RunView` in the
app, `PlaySession` and `RunModel` in the Game target. Rules 3 and 9 are tested in
`PlayScreenRules` and rules 6 and 7 by flow tests; the others have no test yet, and the parts in the Game
target can be covered by `HeadlessApp` flow tests.

1. **A run is named by its opening, never by a mode,** with the side as a
   small square. A Drill run's opening is the one it tests: the deepest
   named opening on the line it heads for, not the position it starts in
   (Ruy Lopez, not King's Pawn Game, for a run starting at 2.Nf3). The
   header shows that opening's family (Sicilian Defense for a Najdorf
   line); Settings' Opening names switches it to the book's name.
2. **The round's card.** The intro deals the run's card from a deck. It
   shows only the start position, face up, and grows into the board; a tap
   goes straight there. The opening's name and segments are in the header
   (rule 3), which stays up while a card is drawn from the deck under a
   finished run. Freeform shows no segments, but Home's button still names
   the opening the opponent steers toward.
3. **During a run,** the app bar shows the opening, the segments counting up
   as you play, and the pawns the run has earned so far. With book names
   on, a smaller line over a name deeper than its family names the family
   ("Sicilian Defense" over the Najdorf).
4. **Replay moves.** A run that starts inside its line opens on that
   position. Until your first move, Replay moves under the board plays the
   moves to it from move one, then hands it back.
5. **Ending.** Once you are past your prep, a Next run button under the
   board ends the round where it stands and deals the next. The X ends a
   round at any point and goes Home. Once you have played a move it asks
   "End session?" first; before that it leaves without asking.
6. **A finished round stays on its board as analysis.** There is no end
   screen. After a blunder, your move shows in red with the reply that
   punishes it, and how the round ended shows under the board (nothing when
   you ended it yourself). Nothing plays on its own: a Show button beside
   "Blunder" goes back to the blunder and plays the engine's line that
   punishes it, a move every 0.8 seconds, the button held down meanwhile
   (its play triangle in the engine's blue, beating once a move).
   It stops on the move that takes your material or mates you, shown in
   red, and Show, now with a replay arrow, plays it again from the blunder. Its moves are part of
   the line to step back through; a step or a move of your own stops it.
   Test: `showPlaysOutTheBlundersPunishment` in
   `Tests/FlowTests/AnalysisFlowTests.swift`.
   - Swipe the deck left or right to step through the moves. A step
     forward plays the game's next move while the game has one, even where
     the arrow shows another top move. Past the game's end it plays the
     engine's top move; those moves stay, so stepping back into the game
     and forward again goes through the same moves.
     Test: `analysisStepsThroughTheGameThenTheEngine` in
     `Tests/FlowTests/AnalysisFlowTests.swift`.
   - Play a move on the board to start your own line from there. Forward
     on it plays the engine's top move. Stepping back over the move that
     started it, or tapping a move before it in the strip, drops it and
     the game comes back.
     Test: `analysisOwnLineGivesWayToTheGame` in
     `Tests/FlowTests/AnalysisFlowTests.swift`.
   - Engine moves, and your own line, are outlined in the engine arrow's
     blue in the move strip after a thin line, and the board has a rim in
     that blue while you are on them.
   - Tap the deck, or flick a card up, and the next round's card is dealt.
7. **Leaving your prep.** A miss shows Off prep under the board for a
   moment. A finished prep shows nothing there: its pawns fly to the header
   with their own Prep complete.
   Test: `drillRoundScoresPrepAndIsRecorded` in `Tests/FlowTests/PlayFlowTests.swift`.
8. **Endgame header.** Once the game reaches the endgame rules (see
   [past prep](past-prep.md)), the header says Endgame and the lenses switch
   to their endgame forms.
9. **Promotion.** A pawn moved to the last rank waits for its piece: the
   queen, knight, rook and bishop come down its file from the promotion
   square as keys over a dimmed board, queen first, only the ones the move
   may be (Growth can allow fewer). A tap on a key plays that promotion; a
   tap anywhere else takes the move back. Where only one piece is allowed,
   it is played at once.
   Test: `promotionOffersEachPieceQueenFirst` in `PlayScreenRules`.
