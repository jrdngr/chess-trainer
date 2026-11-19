# Tips

Tips teach the game as it comes up: no tutorial, no forced moves. Code:
`Tips.swift` in Model, `RunModel` in Game. Tests: the
`docs/rules/tips.md` suite in `Tests/SpecTests/Rules/TipsRules.swift`, and
`tipsShowAtTheirTriggersOnce` in `Tests/FlowTests/OnboardingFlowTests.swift`
and `firstGameGrowsThePlaybookFromMoveOne` in `PlayFlowTests.swift` for rule 2.

1. **A tip shows once.** A tip in a game is seen the moment it shows; one
   off the board (Home, the Playbook tab) once it is put away. The save
   keeps what has been seen. A tip blocks only itself: a tap on the
   tip puts it away, and the first touch anywhere else puts it away and
   still does what it would have done without the tip.
2. **One trigger each, one tip at a time.** A tip shows the first time its
   trigger comes while no other tip is up; if one is up, it waits for its
   trigger to come again. Growth is the one exception: opening it puts
   away any tip that is up, so its own shows. In a game:
   - a Play game starts on your prep: your openings are flashcards
   - a prep move played: the prep bar
   - the first ✓ on a common move: what the ✓ means
   - a prepared move missed, the right one shown: remember it next time
   - growth opens: pick or play an answer
   - growth opens because a move is due, holding the Prep complete pawn: add a move to keep earning pawns on this opening
   - growth draws a green arrow: green moves may not be the engine's top pick, but keep the Playbook easier to remember; then, at a later turn, a red arrow: red moves break a pattern, so they are harder to remember (test: `greenThenRedExplained`)
   - a blunder ends the game
   - the first distance pawns: pawns every 5 moves past your prep (test: `theDistanceBarTakesOverPastThePrep`)
   - pawns earned: what they are for
   - a mission set: missions pay pawns
   - Next run shows past your prep in a Play game: tap it to end the game early
   - a lens owned, past your prep: tap a lens for hints
   - a Freeform game starts: play any of your lines
   - a Play game ends without a blunder: it is over, and its moves can be stepped through or played from
   - pawns paid in Play take the balance to 50 or more: tap ✕ to end the session and spend them in the Pawn Shop (test: `enoughPawnsPointToTheShop` in `PlayFlowTests.swift`)
3. **Home's tip** is a just bought side picker's or opening picker's, at
   its control on Home. No other bought feature has a tip. Once a streak
   day has paid and no picker's tip is waiting, Home shows the daily
   rewards tip at the streak ring: complete your prep once a day to earn
   them. The Shop tab
   shows a badge with the number of items you can buy now, and none at
   zero.
