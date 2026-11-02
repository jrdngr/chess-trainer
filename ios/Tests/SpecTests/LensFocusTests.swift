import ChessCore
import Model
import Testing

/// A held lens keeps only its own pieces bright: every pawn for Pawns, the rated pieces for Pieces; Eval dims nothing.
@Test func heldLensKeepsOnlyItsPieces() {
  let line = ["d4", "d5", "c4", "e6", "Nc3", "Nf6", "cxd5", "exd5", "Bg5", "c6", "e3", "Be7", "Bd3", "Nbd7", "Nf3", "h6"]
  let fen = walkSan(line).fens.last!
  // Pieces rates knights, bishops, rooks and queens; its square tints never pull a pawn or king into focus.
  let pieces = heldLens(.pieces, fen, .w)
  #expect(pieces.focus?.contains("c3") == true)
  #expect(pieces.focus?.contains("d4") == false)
  #expect(pieces.focus?.contains("g1") == false)
  // Eval draws nothing from the board on its own, and leaves every piece bright.
  #expect(heldLens(.eval, fen, .w) == LensMarks())
  #expect(heldLens(.pawns, fen, .w).focus?.count == 14)
}
