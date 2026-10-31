# Play

A game against the engine, with the opening kept. The rules are
`src/model/play.ts`; the screen is `src/screens/play/PlayScreen.tsx`.

## Setup

**PLAY-1** · port
Setup picks a strength (Casual, Club, Strong, Full; Club by default) and four
toggles: Save the opening, Warn me off book, Show the evaluation, and Take
backs. Warn, Save and Take backs start on; the evaluation starts off. The
game is played from the selection's side and opening.
Source: `play/Setup.tsx`, `modes.DEFAULT_PLAY`, `play.LEVELS`
Cases: `play.levelById`, `const:LEVELS`, `const:DEFAULT_LEVEL`, `e2e:play-game`

## The engine's moves

**PLAY-2** · port
While the game is still on the selected opening's move order, and on its way
into it, the engine plays that move order, so a game in the Najdorf is a
Najdorf. Past it, or once you step off it, the engine searches at the level's
depth for the level's number of candidates.
Source: `PlayScreen` (the engine's turn)
Cases: `e2e:play-game`, `openingTree.lineStatus`

**PLAY-3** · port
A level picks among its candidates by chance: the best with probability
1 − slip, and each worse one half as likely as the one before (slip 65%
Casual, 30% Club, 8% Strong, 0 Full). With one candidate, or no slip, it
plays the best. Strength comes only from this and the search depth, so it
works the same on the backup engine.
Source: `play.chooseMove`
Cases: `play.chooseMove`, `const:LEVELS`

## During the game

**PLAY-4** · port
With Warn me off book on, a move that leaves your own prep (your Playbook
has a different move at that position, matched by position) says so at once,
"Nf6 — your prep says d5", and is logged as a mistake.
Source: `PlayScreen.onMove`
Cases: `mistakes.addMistake`, `e2e:play-game`

**PLAY-5** · port
Take back undoes your last move and the engine's reply (or just yours while
the engine is thinking), and reopens a finished game. Resign loses the game.
Mate, stalemate and the other drawing rules end it on their own.
Source: `PlayScreen.takeBack`, `PlayScreen` (settling)
Cases: `e2e:play-game`

## After the game

**PLAY-6** · port
A finished game (won, lost or drawn, with at least 2 plies) is kept with the
imported games, as You against "Engine (<level>)", with the result from
White's side, the UTC date, and its first 40 plies. Ending the same game twice
(a take back after resigning) replaces it. The newest 200 are kept, ahead of
the imports; across devices they are merged by id, newest first, while
imports stay on the device that made them.
Source: `play.playedGame`, `play.withPlayGame`, `play.mergeGames`
Cases: `play.playedGame`, `play.withPlayGame`, `play.withPlayGame (cap)`, `play.mergeGames`, `const:PLAY_GAMES_CAP`, `const:PLAY_GAME_PLIES`

**PLAY-7** · port
Save this opening offers the game's first 16 plies, trimmed to end on your
own move, to the Save sheet for your side; a game too short to save says
"Too short to save". Nothing goes into the Playbook unless you save it.
Source: `play.openingLine`, `PlayScreen.save`
Cases: `play.openingLine`, `const:OPENING_PLIES`, `e2e:play-game`

## Settled

- **Save the opening** ported as the code does it: the toggle is shown and stored, and nothing reads it. The owner ruled on 10-31 that the code is the truth: nothing is saved unless you tap Save this opening.
