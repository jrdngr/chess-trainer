# The Play screen

How a run is shown, ended and dealt. Code: `PlayView` and `RunView` in the
app, `PlaySession` and `RunModel` in the Game target. Rule 3 is tested in
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
   you ended it yourself). A moment later the engine's line that punishes
   it plays out, a move every 0.6 seconds, and stops on the move that
   takes your material or mates you, shown in red. Its moves are part of
   the line to step back through; a step or a move of your own stops it.
   Test: `aBlunderPlaysOutItsPunishment` in
   `Tests/FlowTests/AnalysisFlowTests.swift`.
   - Swipe the deck left or right to step through the moves. A step
     forward always plays the engine's top move, the one its arrow shows;
     where the game went another way, the game's later moves give way to
     it.
     Test: `analysisStepsPlayTheTopMoveShown` in
     `Tests/FlowTests/AnalysisFlowTests.swift`.
   - Play a move on the board to try another line.
   - Tap the deck, or flick a card up, and the next round's card is dealt.
7. **Leaving your prep.** A miss shows Off prep under the board for a
   moment. A finished prep shows nothing there: its pawns fly to the header
   with their own Prep complete.
   Test: `drillRoundScoresPrepAndIsRecorded` in `Tests/FlowTests/PlayFlowTests.swift`.
8. **Endgame header.** Once the game reaches the endgame rules (see
   [past prep](past-prep.md)), the header says Endgame and the lenses switch
   to their endgame forms.
