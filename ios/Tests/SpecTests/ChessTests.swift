import ChessCore
import Model
import Testing

/// spec/cases/functions/chess.json: chess.js, move for move.
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
