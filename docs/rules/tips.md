# Tips

Tips teach the game as it comes up: no tutorial, no forced moves. Code:
`Tips.swift` in Model, `RunModel` and `EndgameGame` in Game. Tests: the
`docs/rules/tips.md` suite in `Tests/SpecTests/Rules/TipsRules.swift`, and
`tipsShowAtTheirTriggersOnce` in `Tests/FlowTests/OnboardingFlowTests.swift`
and `firstGameGrowsThePlaybookFromMoveOne` in `PlayFlowTests.swift` for rule 2.

1. **A tip shows once.** A tip in a game is seen the moment it shows; one
   off the board (Home, the Playbook tab) once it is put away. The save
   keeps what has been seen. While a tip is up, the next tap anywhere on
   the screen puts it away and does nothing else.
2. **One trigger each, one tip at a time.** A tip shows the first time its
   trigger comes while no other tip is up; if one is up, it waits for its
   trigger to come again. Growth is the one exception: opening it puts
   away any tip that is up, so its own shows. In a game:
   - a Play game starts on your prep: your openings are flashcards
   - a prep move played: the prep bar
   - your prep runs out without a miss: the ✓ marks common moves
   - a move past the book gets its score: what scores mean
   - growth opens: pick or play an answer, Done stops early
   - a blunder ends the game: the arrow shows the threat
   - pawns earned: what they are for
   - a mission set: what it pays
   - the board glows for a moment: find the strong move
   - the lenses owned, past your prep: tap a lens for hints
   - a Freeform game starts: play any of your lines
   - a Middlegame round reaches the board: the replay and the plan card
   - an Endgames round starts: win it or hold it
3. **Home's tip** is a bought feature's, at its control on Home (the side
   picker, the opening picker, the Freeform switch, Recommendations,
   Middlegame, Endgames), and once those are seen, the Pawn Shop tab's when
   something there is yours to buy. The Playbook tab has one tip, the first
   time it opens.
4. **Profiles from before the tips** have seen every one (see
   [saves](saves.md)).
