import ChessCore
import Model
import Testing

/// A held lens keeps only its own pieces bright: none for Space, the piece at risk for Threats, every pawn for Pawns.
@Test func lensFocusKeepsOnlyItsPieces() {
  // A Carlsbad where ...h6 hits the bishop on g5, a piece attacked by a cheaper one.
  let line = ["d4", "d5", "c4", "e6", "Nc3", "Nf6", "cxd5", "exd5", "Bg5", "c6", "e3", "Be7", "Bd3", "Nbd7", "Nf3", "h6"]
  let fen = walkSan(line).fens.last!
  #expect(lensMarks(.space, fen, .w).focus == [])
  #expect(lensMarks(.threats, fen, .w).focus == ["g5"])
  #expect(lensMarks(.pawns, fen, .w).focus?.count == 14)
}
