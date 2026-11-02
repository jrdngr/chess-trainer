import ChessCore
import Model
import Testing

/// A held lens keeps only its own pieces bright: every pawn for Pawns, both ends of a threat for Threats; Space dims nothing.
@Test func heldLensKeepsOnlyItsPieces() {
  // A Carlsbad where ...h6 hits the bishop on g5, a piece attacked by a cheaper one.
  let line = ["d4", "d5", "c4", "e6", "Nc3", "Nf6", "cxd5", "exd5", "Bg5", "c6", "e3", "Be7", "Bd3", "Nbd7", "Nf3", "h6"]
  let fen = walkSan(line).fens.last!
  #expect(heldLens(.space, fen, .w).focus == nil)
  let threats = heldLens(.threats, fen, .w)
  #expect(threats.rings == nil)
  #expect(threats.arrows == [LensArrow(from: "h6", to: "g5", tone: "threat")])
  #expect(threats.focus == ["g5", "h6"])
  #expect(heldLens(.pawns, fen, .w).focus?.count == 14)
}
