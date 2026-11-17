# Pawns

What earns pawns, the currency the Pawn Shop sells for. Code: `Pawns.swift`,
`RunController.swift` and, for the counter, `PawnDrops.swift` in the Game
target. Tests: the `docs/rules/pawns.md` suite in
`Tests/SpecTests/Rules/PawnsRules.swift`.

1. **Only these events pay**, in Play and Middlegame runs and Endgames
   rounds: prep complete 1 for each prep move asked, blunder punished 3, a
   found moment 6, a mission done 6, reaching the endgame 3, checkmate 15,
   distance markers and a held draw (rules 9 and 10), and Endgames bounties
   (see [endgames](endgames.md)). Single moves, growth and milestones pay
   nothing.
2. **Prep complete** pays when your prep runs out, asked you something, and
   was never missed: a pawn for each prep move asked. Each prepared move
   you find pops a pawn out of its square into the pot beside the prep bar,
   which counts them; nothing is paid until the prep completes, when the
   pot's pawns fly to the counter. A miss loses the pot: it turns red and
   drains, and the rest of the run still pays. When growth opens there
   because a move is due, the pot waits, breathing: the first move you add
   pays it out, and Done or the game ending first drains it. An opening
   complete through the book has nothing due, so it always pays. Tests:
   the held-pot flows in `Tests/FlowTests/PlayFlowTests.swift`.
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
9. **Distance markers** pay every 5 of your moves past your prep: 10 for
   the first, 15 for the second and 20 for each one after, popping out of
   the move that reached it. In Middlegame, where every move is past prep,
   they pay 40%: 4, 6, then 8. Growth moves and your prep's own moves don't
   count.
10. **Held the draw** pays half of checkmate, rounded down (7), when a game
   ends drawn and you stood at −1.5 or worse after your prep (the engine's
   word before your first move past it). Other draws pay nothing extra.
