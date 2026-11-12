# Middlegame

One of your lines played on for you to a middlegame, then yours to play.
Code: `Middlegame.swift`, and `MiddlegameSession` and `RunModel` in the
Game target.
Tests: the `docs/rules/middlegame.md` suite in
`Tests/SpecTests/Rules/MiddlegameRules.swift`.

1. **Setup.** The opponent steers toward one of your lines, or a line that
   ends at a gap. Moments, missions and the combo are always on, so the
   mode always scores in points.
2. **The line** is the one the draw picked (see [opponent](opponent.md)),
   to its end. A draw that finds no line of yours plays nothing out.
3. **The handoff** plays your line as it stands, then book moves for both
   sides, then the engine at your level once the book runs out.
4. **Every move played for you stays near your line's eval:** within 100
   centipawns of the engine's score where your line ended.
   - A book move in that band is picked by how often it is played.
   - With no book move in the band, an engine move in it is played instead.
   - With nothing in the band, the move closest to it is played.
   - The engine's moves are scored as deep as that eval, so the two compare like with like.
5. **The handoff stops on your turn** once the middlegame has started and
   the book has nothing more, or at an endgame. Ply 60 is the hard limit.
6. **The middlegame has started** when both sides are developed, or once each
   side has played 15 moves. Developed means at most one knight or bishop still on its
   starting square, and the king castled, moved or without castling rights.
7. **A gap line hands over at the gap,** right after the reply you have no
   answer to.
8. **After the handoff, nothing is prep.** Your prep is never asked, even if
   the game transposes back into your Playbook. The book phase is over
   before it starts. The opponent plays the book, then the engine, never
   your lines. The first mission is set from the eval at the handoff.
9. **Middlegame's points are kept apart** from Play's run record.
10. **The plan comes from the handoff's pawn structure.**
