import Book
import ChessCore
import Engine
import Model

/// The engine and the book as a handoff build asks for them. Band checks search
/// shallow and briefly: they only need to tell a sound move from one that tips the game.
func handoffTools(_ engine: ChessEngine, _ index: ReferenceIndex, _ level: Level) -> HandoffTools {
  let quick = EngineLimits(depth: HANDOFF_DEPTH, movetime: 400, multiPv: 1)
  return HandoffTools(
    book: { bookCandidates(index, $0) },
    evaluate: { fen in
      let snap = await engine.analyse(fen, quick)
      return snap.lines.first.flatMap(whiteScore)
    },
    score: { fen, sans in
      let ucis = sans.compactMap { applySan(fen, $0)?.uci }
      if ucis.isEmpty { return [:] }
      let snap = await engine.analyse(fen, EngineLimits(depth: HANDOFF_DEPTH, movetime: 400, multiPv: ucis.count, searchmoves: ucis))
      var out: [String: Double] = [:]
      for line in snap.lines {
        guard let uci = line.pv.first, let san = applyUci(fen, uci)?.san, let cp = whiteScore(line) else { continue }
        out[san] = cp
      }
      return out
    },
    engineMoves: { fen in
      let snap = await engine.analyse(fen, EngineLimits(depth: level.depth, multiPv: level.multiPv))
      return levelCandidates(fen, snap.lines, level)
    })
}

/// A line's score in centipawns, White's, a mate as a large number.
private func whiteScore(_ line: EngineLine) -> Double? {
  if let cp = line.cp { return cp }
  if let mate = line.mate { return mate > 0 ? 10_000 : -10_000 }
  return nil
}
