# Pawns

What earns pawns, the currency the Pawn Shop sells for. Code: `Pawns.swift`,
`RunController.swift` and, for the counter, `PawnDrops.swift` in the Game
target. Tests: the `docs/rules/pawns.md` suite in
`Tests/SpecTests/Rules/PawnsRules.swift`.

1. **Only these events pay**, in Play and Middlegame runs and Endgames
   rounds: prep complete 1, blunder punished 1, a found moment
   2, a mission done 2, reaching the endgame 1, checkmate 3, an Endgames
   round's goal met 1. Single moves, growth and milestones pay nothing.
2. **Prep complete** pays when your prep runs out, asked you something, and
   was never missed.
3. **A blunder punished** pays when, past your prep, the opponent's move
   dropped their eval by 200 centipawns or more since your last scored move,
   and your reply gave back 50 or less.
4. **Reaching the endgame** pays once a game, on the move that reaches
   endgame rules (see [past prep](past-prep.md)). **Checkmate** pays when you
   give it, never when you take it.
5. **The streak.** The first game you finish each day pays 1 in the
   streak's first week (days 1 to 7), 2 in its second, 3 in its third, 4 in
   its fourth and 5 from day 29 on. A missed day starts it again at day 1.
   The pawns go onto the balance when the game ends, but the counter takes
   them only when you next open Home, where they pop out of the streak ring
   and the ring lights up.
6. **Pawns land as they are earned.** Each goes straight onto the balance;
   the counter on screen takes it when it arrives. A run's score is the
   pawns its events earned, the streak's aside.
7. **A personal best is moves survived,** for Play and for Middlegame alike.
8. **The streak ring** on Milestones has a part for each day of the
   streak's week. Before today's game it shows the day the game will make
   and the pawns it will pay as outlines; once played, the day it made and
   the pawns filled in.
