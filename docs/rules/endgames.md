# Endgames

Must-know endings, each played against the engine with one goal. Code:
`EndgameMode.swift`. Tests: the `docs/rules/endgames.md` suite in
`Tests/SpecTests/Rules/EndgamesRules.swift`. The endgame rules inside a
Play run are in [past prep](past-prep.md).

1. **The library.** Each entry has a goal, Win or Hold Draw, and a mission on top of it:
   - Basic mates: Queen mate (mate in 10), Rook mate (16), Two bishops (19).
   - King and pawn: Key squares, Opposition and Square rule, each as a Win (queen a pawn) and a Hold Draw (hold for 15 moves, 12 for Square rule).
   - Rook endings: Lucena (Win, queen a pawn), Philidor (Hold Draw, hold for 20).
2. **Every round is a fresh position.** Colors are swapped at random and
   the board is mirrored at random. A pawn or rook ending is kept only when
   the tablebase, or the known ending, gives you the entry's goal. With none
   found, the textbook position is played. Basic mates keep their king off the
   edge, with nothing hanging and no check.
3. **From your games.** An endgame result given away in a Play run is kept,
   once per position, newest first, up to 30. A Win is to queen a pawn if
   you have one, else mate within 50 moves. A Hold Draw holds for 15. The
   fifty-move count starts afresh.
4. **A round ends at its goal.**
   - Mate wins, and meets a mate mission when it comes within its count. Being mated loses.
   - A draw holds a Hold Draw and loses a Win, as "Stalemate" or "Drawn".
   - A queened pawn wins while the win still stands.
   - Holding for the mission's moves holds.
   - A Win still going after 50 of your moves is out of moves.
5. **Each position has its own schedule, in Endgame rounds.** A success
   pushes it out 3 rounds, then 2.5 times as far each time. A failure makes
   it due at once.
6. **The next round** is the position due longest, else the first never
   played. A position never played isn't due; it waits its turn.
7. **Each family has a form:** its last rounds, read as a form ring (see
   [form](form.md)).
8. **Bounties, not rounds, pay.** Each library ending pays once for its
   first clear (250), its first mission met (100) and mastery (500).
   Mastered is 3 successes in a row, each on a different day; a failure
   starts the count again. Each From your games position pays 100 once, on
   its first success. Other rounds pay nothing.
9. **Tune-ups keep a mastered ending.** The first comes due 14 days after
   mastery; each pass pays 100 and doubles the wait, up to 90 days. A failed
   one pays nothing and comes back in 3 days, and mastery is kept. Practice
   plays tune-ups due first, and while one is due the Endgames tile on Home
   shows a plain dot with no count.
