# Points, combo, moments and missions

What a run scores past the opening. Code: `Run.swift` (combo and moments)
and `Missions.swift`. Tests: the `docs/rules/scoring.md` suite in
`Tests/SpecTests/Rules/ScoringRules.swift`.

1. **Points.** A prepared move found is 1 point. Every move the engine
   judges earns the combo's multiplier, plus a found moment's bonus. A
   mission done adds 15.
2. **The combo** grows on a move that gives away 20 centipawns or less,
   holds at 40 or less, and breaks above that. A book move counts as giving
   away nothing (see [past prep](past-prep.md)). The multiplier is ×2 from 3,
   ×3 from 6 and ×4 from 10.
3. **A moment** is a position where your best move leaves you at +1 or
   better and at least 150 centipawns ahead of the second best, or mates
   when the second best doesn't. You find it by giving away 50 centipawns
   or less. A found moment is worth 10, plus 5 for each moment found in a
   row before it. A missed one breaks the combo and the streak.
4. **The first mission** is set where your prep runs out, from the eval:
   - at +2 or better with pieces on both sides, Convert it: trade a piece within 6 moves without dropping under +1;
   - at +1 or better, Keep your edge: stay at +1 or better for 10 moves;
   - at −1 or worse, Dig in: get back to −0.5 within 15 moves;
   - otherwise, Take the lead: reach +1 within 15 moves.
5. **Missions follow each other.** Three judged moves after one is settled,
   done or failed, the next is set from the eval then.
