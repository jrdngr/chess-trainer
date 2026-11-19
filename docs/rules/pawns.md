# Pawns

What earns pawns, the currency the Pawn Shop sells for. Code: `Pawns.swift`,
`RunController.swift` and, for the counter, `PawnDrops.swift` in the Game
target. Tests: the `docs/rules/pawns.md` suite in
`Tests/SpecTests/Rules/PawnsRules.swift`.

1. **Only these events pay**, in Play and Middlegame runs and Endgames
   rounds: prep complete 1 for each prep move asked, blunder punished 3, a
   found moment 6, a mission done 6, reaching the endgame 3, checkmate (rule 4),
   distance markers and a held draw (rules 9 and 10), and Endgames bounties
   (see [endgames](endgames.md)). Single moves, growth and milestones pay
   nothing.
2. **Prep complete** pays when your prep runs out, asked you something, and
   was never missed: a pawn for each prep move asked. Each prepared move
   you find pops a pawn out of its square into the pot beside the prep bar,
   which counts them; nothing is paid until the prep completes, when the
   pot's pawns fly to the counter. When it completes the turn the last
   prepared move was found, that move's pawn, still on its way into the
   pot, turns and flies straight to the counter, and the pot pays the rest. A miss loses the pot: it turns red and
   drains, and the rest of the run still pays. When growth opens there
   because a move is due, the pot waits, breathing: the first move you add
   pays it out, every pawn from the pot, and Done or the game ending first
   drains it. An opening
   complete through the book has nothing due, so it always pays. Tests:
   the clean-prep and held-pot flows in `Tests/FlowTests/PlayFlowTests.swift`.
3. **A blunder punished** pays when, past your prep, the opponent's move
   dropped their eval by 200 centipawns or more since your last scored move,
   and your reply gave back 50 or less.
4. **Reaching the endgame** pays once a game, on the move that reaches
   endgame rules (see [past prep](past-prep.md)). **Checkmate** pays when you
   give it, never when you take it: 100, less 2 for each of your moves
   played under endgame rules before the mate, down to 25. A quick finish
   pays the most, and dragging out a won ending only costs.
5. **The streak.** The first game you finish each day pays 10 on the
   streak's first day and 10 more each day after, up to 90 from day 9 on.
   In Play, only a game whose prep you completed counts: one you quit or
   missed before then doesn't. Test: `theStreakWaitsForACompletedPrep` in
   `Tests/FlowTests/PlayFlowTests.swift`.
   A missed day starts it again at day 1, unless a freeze or a repair keeps
   it (rule 11). The pawns go onto the balance when the game ends, but the
   counter takes them only when you next open Home, where they pop out of
   the streak ring and the ring lights up.
6. **Pawns land as they are earned.** Each goes straight onto the balance;
   the counter on screen takes it when it arrives. As the first pawn of an
   award lands, why it was paid shows under the counter for 1.5 seconds,
   with no count: Prep complete, Blunder punished, Found it, Mission
   complete, Endgame reached, Checkmate, Held the draw, and
   for Endgames First clear, First mission, Mastered, Tune-up passed and
   Converted. Distance pawns say nothing: they pop out of the bar
   past the prep. Pawns flying into the prep's pot say nothing until it pays.
   Test: `landingPawnsSayWhyTheyWerePaid` in
   `Tests/FlowTests/PlayFlowTests.swift`. A run's score is the
   pawns its events earned, the streak's aside.
7. **A personal best is moves survived,** for Play and for Middlegame alike.
8. **The streak ring** on Milestones has a part for each day of the
   streak's week. Before today's game it shows the day the game will make
   and the pawns it will pay in outline; once played, the day it made and
   the pawns filled in. Days kept by a freeze or a repair show icy, with no
   pawns.
9. **Distance markers** pay every 5 of your moves past your prep: 20
   each. Once your prep
   is behind you (from your first move past it, or from the start with no
   prep), a gold bar takes the prep bar's place in the header: a step for
   each move toward the next marker, and a pawn at its end that brightens
   with each step and that the marker's pawns pop out of. In Middlegame, where every move is past prep,
   they pay 15 each. Growth moves and your prep's own moves don't
   count. Markers stop once the game reaches endgame rules, and after the
   run's 10th (200 pawns in all); the bar goes with them.
10. **Held the draw** pays 20, under the least a mate pays, when a game ends
   drawn and, once it reached endgame rules, you stood at −3 or worse (a
   lost ending). Other draws pay nothing extra.
11. **Freezes and repairs keep the streak.** A freeze costs 1,000 in the
   Pawn Shop, and you can hold 2. Each missed day uses one on its own,
   oldest first. A repair costs 2,000 and is offered only when yesterday is
   the one missed day, all through today: quietly, as a faint part on the
   streak ring and a row in the Milestones sheet, never a popup. Finishing
   a game today without it starts the streak again. A frozen or repaired
   day counts toward the streak's length and pays nothing.
12. **Continue after a blunder** costs 500, once a run. While you have the
   pawns, a blunder holds the board with End run and Continue; Continue
   takes the blunder back, its threat drawn until your next move, and the
   run goes on. Moves after it don't count toward your best; events still
   pay.
