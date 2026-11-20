# Developer tools

What the Developer screen changes, for testing on a phone. Xcode and TestFlight
builds show it as the last row of Settings; App Store builds don't, so a player
has one profile. Code: `DevTools.swift` in Model and in the Game target, and
`DeveloperView` in the app, which also checks the build (not tested: Linux
can't be a TestFlight build). Tests: the `docs/rules/dev-tools.md` suite in
`Tests/SpecTests/Rules/DevToolsRules.swift`, and
`Tests/FlowTests/DevToolsFlowTests.swift` for rules 1, 8 to 12.

1. **Changes log nothing and earn nothing.** They set the save directly:
   no event goes in the log, not even a settings change, and pawns added by
   hand don't touch the streak or a run's score.
2. **Pawn Shop items** are owned or not by hand. Owning one owns every item
   it needs first; taking one away takes every item that needs it. Endgames
   plays the families owned, as it does after buying. Own all and Own none
   do the whole tree and the endgame families.
3. **Pawns** are added in steps or zeroed. The balance never goes below 0.
4. **Openings on the list** go into the Playbook free, with their seed lines,
   or come out with their moves, cards and form.
   Neither moves the price ladder.
5. **Tips** are marked seen or unseen, one at a time or all at once. An
   unseen tip shows again at its trigger.
6. **The streak** is set by hand: its days and its last day, today or up
   to 3 days back. The next game goes on from there as if those days had
   been played.
7. **Growth levels** show their gate: Play games, openings green, levels
   open. Play games are added ten at a time, each ending on your first move.
   An opening's form is set green, middle, red or empty, or every opening
   green.
8. **The clock** runs whole days ahead. It belongs to the device, kept over
   relaunches and every profile; Home shows "+N days" while it runs ahead.
   A pinned clock (tests, replays) doesn't move.
9. **The App Store unlock** can be ignored on the device: one the App Store
   hands back as owned isn't credited, so the unlock shows and can be bought
   again, and buying it credits it. Forgetting credited purchases lets any
   transaction credit once more.
10. **Profiles** live here. A new one opens on Welcome. Duplicate copies the
   profile in use to a new one, which opens; the original stays as it was.
11. **The save** goes out as JSON and comes back in by paste, replacing the
   profile in use. A paste that isn't a save at this version changes nothing.
12. **Replay Welcome** opens Welcome again on the profile in use. Its
   Playbook stays, and the openings picked go in beside it.
