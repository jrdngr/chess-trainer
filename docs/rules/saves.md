# Saves from older versions

How an older save is brought up to date when it loads. Code:
`Migrations.swift`. Tests: the `docs/rules/saves.md` suite in
`Tests/SpecTests/Rules/SavesRules.swift`.

1. **Every save has a version.** A new save starts at the current one (6).
   A save written before versions existed counts as 0. Each step below runs
   once, in order, and the save is written back after.
2. **Version 1: book moves only.** See [playbook](playbook.md).
3. **Version 2: schedules count runs.** A card's interval in days becomes 3
   runs per day. An Endgames position waits its interval in Endgame rounds
   from the current round. One saved with a date instead of a round is due.
4. **Version 3: new names.** Repertoire is Playbook, Survival is Run, and
   Autopilot's settings are Play's. The old Play mode's tallies are kept
   apart under their own name. A save already at version 3 reads as it is.
5. **Version 4: Middlegame counts moves.** Middlegame's record kept points;
   its bests and recent runs are dropped, and how many runs were played and
   ended stays.
6. **Version 5: the Pawn Shop.** A profile from before it owns every
   feature the shop sells and has seen every tip. A new profile owns none
   and has seen none.
7. **Version 6: one item per lens.** A profile that owned the lenses, one
   item before, owns all five lenses. One that didn't owns none.
