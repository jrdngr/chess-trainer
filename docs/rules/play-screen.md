# The Play screen

How a run is shown, ended and dealt. Code: `PlayView` and `RunView` in the
app, `PlaySession` and `RunModel` in the Game target. Rule 3 is tested in
`PlayScreenRules`; the others have no test yet, and the parts in the Game
target can be covered by `HeadlessApp` flow tests.

1. **A run is named by its opening, never by a mode,** with the side as a
   small square. A Drill run's opening is the one it tests: the deepest
   named opening on the line it heads for, not the position it starts in
   (Ruy Lopez, not King's Pawn Game, for a run starting at 2.Nf3). The
   header shows that opening's family (Sicilian Defence for a Najdorf
   line); Settings' Opening names switches it to the book's name.
2. **The round's card.** The intro deals the run's card from a deck. It
   shows the start position face up, the opening's full name above it, and
   a row of segments below, one for each of your own moves, lit up to where
   you take over. After a beat the card grows into the board; a tap goes
   straight there. Freeform shows no segments, but Home's button still
   names the opening the opponent steers toward.
3. **During a run,** the app bar shows the opening, the segments counting up
   as you play, and the pawns the run has earned so far. With book names
   on, a smaller line over a name deeper than its family names the family
   ("Sicilian Defence" over the Najdorf).
4. **Replay moves.** A run that starts inside its line opens on that
   position. Until your first move, Replay moves under the board plays the
   moves to it from move one, then hands it back.
5. **Ending.** Once you are past your prep, a Next run button under the
   board ends the round where it stands and deals the next. The X ends a
   round at any point: it asks "End session?" and goes Home.
6. **A finished round stays on its board as analysis.** There is no end
   screen. After a blunder, your move shows in red with the reply that
   punishes it, and how the round ended shows under the board (nothing when
   you ended it yourself).
   - Swipe the deck left or right to step through the moves. Past the
     game's end, a step forward plays the engine's top move.
   - Play a move on the board to try another line.
   - Tap the deck, or flick a card up, and the next round's card is dealt.
7. **Endgame header.** Once the game reaches the endgame rules (see
   [past prep](past-prep.md)), the header says Endgame and the lenses switch
   to their endgame forms.
