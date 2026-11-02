import ChessCore
import Model
import Testing

/// A held lens keeps only its own pieces bright: every pawn for Pawns; Space and Eval dim nothing.
@Test func heldLensKeepsOnlyItsPieces() {
  let line = ["d4", "d5", "c4", "e6", "Nc3", "Nf6", "cxd5", "exd5", "Bg5", "c6", "e3", "Be7", "Bd3", "Nbd7", "Nf3", "h6"]
  let fen = walkSan(line).fens.last!
  #expect(heldLens(.space, fen, .w).focus == nil)
  // Eval draws nothing from the board on its own, and leaves every piece bright.
  #expect(heldLens(.eval, fen, .w) == LensMarks())
  #expect(heldLens(.pawns, fen, .w).focus?.count == 14)
}
