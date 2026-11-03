import ChessCore
import Model
import Testing

/// Golden/cases/functions/chess.json: chess.js, move for move.
@Test func chess() throws {
  try check("chess", [
    "core.randomGame": { a in
      let rand = mulberry32(UInt32(a[0].int))
      var fen = START_FEN
      var sans: [String] = [], fens: [String] = [], counts: [Int] = []
      for _ in 0..<a[1].int {
        let moves = legalSans(fen)
        counts.append(moves.count)
        if moves.isEmpty { break }
        let san = moves[Int((rand() * Double(moves.count)).rounded(.down))]
        fen = applySan(fen, san)!.after
        sans.append(san)
        fens.append(fen)
      }
      let s = positionStatus(fen)
      return obj([
        "sans": sans, "fens": fens, "counts": counts,
        "status": obj(["check": s.check, "checkmate": s.checkmate, "stalemate": s.stalemate, "draw": s.draw, "gameOver": s.gameOver]),
      ])
    },
    "core.applySan": { a in
      guard let m = applySan(a[0].string, a[1].string) else { return .null }
      return obj([
        "from": m.from, "to": m.to, "san": m.san, "uci": m.uci, "promotion": m.promotion?.rawValue,
        "piece": m.piece.rawValue, "captured": m.captured?.rawValue, "after": m.after,
      ])
    },
  ])
}

/// The captured row's material: even trades cancel, only what a side is up remains.
@Test func materialShowsTheNetDifference() {
  // A pawn each is traded, then Bxf7+ Kxf7 gives a bishop for a pawn.
  var fen = START_FEN
  for san in line("e4 d5 exd5 Qxd5 Nc3 Qa5 Nf3 Nf6 Bc4 Bg4 Bxf7+ Kxf7") { fen = applySan(fen, san)!.after }
  // White gave a bishop for a pawn: Black is up a bishop, White up a pawn.
  #expect(material(fen) == Material(byWhite: [.p], byBlack: [.b], lead: -2))
  // A set-up queen mate: one queen, not 30 captures.
  #expect(material("8/8/8/4k3/8/8/8/3QK3 w - - 0 1") == Material(byWhite: [.q], byBlack: [], lead: 9))
  // Level material: nothing.
  #expect(material(START_FEN) == Material(byWhite: [], byBlack: [], lead: 0))
}
