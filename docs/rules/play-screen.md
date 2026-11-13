# The Play screen

How a run is shown, ended and dealt. Code: `PlayView` and `RunView` in the
app, `PlaySession` and `RunModel` in the Game target. Rule 3 is tested in
`PlayScreenRules`; the others have no test yet, and the parts in the Game
target can be covered by `HeadlessApp` flow tests.

1. **A run is named by its opening, never by a mode,** with the side as a
   small square.
2. **The round's card.** The intro deals the run's card from a deck. It
   shows the start position face up, the opening's full name above it, and
   a row of segments below, one for each of your own moves, lit up to where
   you take over. After a beat the card grows into the board; a tap goes
   straight there. Freeform shows no segments, but Home's button still
   names the opening the opponent steers toward.
3. **During a run,** the app bar shows the opening, the segments counting up
   as you play, and the rating the run has gained so far. Over a name
   deeper than its family, a smaller line names the family ("Sicilian
   Defence" over "Sicilian Defence: Najdorf Variation").
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
8. **The tutorial.** A new profile's first five runs are the tutorial's
   games, on the three openings it starts with. They force some moves, grow
   your line by a fixed number of moves twice, and ask you to end the run
   with the X three times. When a tutorial game ends, it stays on its board
   with no deck, and the X goes Home. A game that ended on its own (a
   blunder, mate or draw) points a tip at the X to go Home. A finished
   tutorial game takes a tap anywhere: one puts the blunder tip away while
   it is up, else the tap goes Home. A blunder shows "A blunder ends the game." first, in
   every tutorial game. After the games, tips walk through the Playbook tab;
   putting its last one away goes back Home. `Tutorial.swift` holds each
   game's setup.
