import ChessCore
import Foundation
import Model
import Testing
@testable import Engine

/// How the judge and the levels do, printed for comparing builds. Runs only with
/// ENGINE_BENCH set (CI's release step), since the judge bench takes minutes.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["ENGINE_BENCH"] != nil))
struct EngineBenchTests {
  /// The most played move in the book's 60 most played positions. Strong
  /// players' main moves are sound, so each one flagged is a false blunder.
  static let bookMoves: [(fen: String, san: String)] = [
    ("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1", "c5"),
    ("rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1", "Nf6"),
    ("rnbqkb1r/pppppppp/5n2/8/3P4/8/PPP1PPPP/RNBQKBNR w KQkq - 0 1", "c4"),
    ("rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1", "Nf3"),
    ("rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 0 1", "d6"),
    ("rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1", "Nf3"),
    ("rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 0 1", "Nc6"),
    ("rnbqkbnr/pppppppp/8/8/8/5N2/PPPPPPPP/RNBQKB1R b KQkq - 0 1", "Nf6"),
    ("rnbqkb1r/pppppppp/5n2/8/2PP4/8/PP2PPPP/RNBQKBNR b KQkq - 0 1", "e6"),
    ("r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 0 1", "Bb5"),
    ("rnbqkbnr/ppp1pppp/8/3p4/3P4/8/PPP1PPPP/RNBQKBNR w KQkq - 0 1", "c4"),
    ("r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 0 1", "Nf6"),
    ("rnbqkbnr/pp2pppp/3p4/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 0 1", "d4"),
    ("rnbqkbnr/pppppppp/8/8/2P5/8/PP1PPPPP/RNBQKBNR b KQkq - 0 1", "e5"),
    ("rnbqkbnr/pppp1ppp/4p3/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1", "d4"),
    ("rnbqkbnr/pp1ppppp/2p5/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1", "d4"),
    ("rnbqkb1r/pppp1ppp/4pn2/8/2PP4/8/PP2PPPP/RNBQKBNR w KQkq - 0 1", "Nc3"),
    ("rnbqkbnr/ppp1pppp/8/3p4/2PP4/8/PP2PPPP/RNBQKBNR b KQkq - 0 1", "e6"),
    ("rnbqkb1r/pppppppp/5n2/8/3P4/5N2/PPP1PPPP/RNBQKB1R b KQkq - 0 1", "e6"),
    ("rnbqkbnr/pppp1ppp/4p3/8/3PP3/8/PPP2PPP/RNBQKBNR b KQkq - 0 1", "d5"),
    ("rnbqkbnr/ppp2ppp/4p3/3p4/3PP3/8/PPP2PPP/RNBQKBNR w KQkq - 0 1", "Nc3"),
    ("rnbqkbnr/pp2pppp/3p4/2p5/3PP3/5N2/PPP2PPP/RNBQKB1R b KQkq - 0 1", "cxd4"),
    ("rnbqkbnr/pp2pppp/3p4/8/3pP3/5N2/PPP2PPP/RNBQKB1R w KQkq - 0 1", "Nxd4"),
    ("rnbqkb1r/pppppppp/5n2/8/8/5N2/PPPPPPPP/RNBQKB1R w KQkq - 0 1", "g3"),
    ("rnbqkbnr/pp2pppp/3p4/8/3NP3/8/PPP2PPP/RNBQKB1R b KQkq - 0 1", "Nf6"),
    ("rnbqkb1r/pp2pppp/3p1n2/8/3NP3/2N5/PPP2PPP/R1BQKB1R b KQkq - 0 1", "a6"),
    ("rnbqkbnr/pp1ppppp/2p5/8/3PP3/8/PPP2PPP/RNBQKBNR b KQkq - 0 1", "d5"),
    ("rnbqkb1r/pp2pppp/3p1n2/8/3NP3/8/PPP2PPP/RNBQKB1R w KQkq - 0 1", "Nc3"),
    ("r1bqkb1r/pppp1ppp/2n2n2/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 1", "O-O"),
    ("rnbqkbnr/pp2pppp/2p5/3p4/3PP3/8/PPP2PPP/RNBQKBNR w KQkq - 0 1", "e5"),
    ("r1bqkbnr/pp1ppppp/2n5/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 0 1", "d4"),
    ("rnbqkbnr/ppp1pppp/8/3p4/8/5N2/PPPPPPPP/RNBQKB1R w KQkq - 0 1", "g3"),
    ("rnbqkb1r/ppp2ppp/4pn2/3p4/2PP4/5N2/PP2PPPP/RNBQKB1R w KQkq - 0 1", "Nc3"),
    ("rnbqkb1r/ppp1pppp/5n2/3p4/3P4/5N2/PPP1PPPP/RNBQKB1R w KQkq - 0 1", "c4"),
    ("rnbqkbnr/ppp1pppp/8/3p4/3P4/5N2/PPP1PPPP/RNBQKB1R b KQkq - 0 1", "Nf6"),
    ("rnbqkb1r/pppp1ppp/4pn2/8/2PP4/5N2/PP2PPPP/RNBQKB1R b KQkq - 0 1", "d5"),
    ("rnbqkbnr/ppp2ppp/4p3/3p4/2PP4/8/PP2PPPP/RNBQKBNR w KQkq - 0 1", "Nc3"),
    ("rnbqkb1r/1p2pppp/p2p1n2/8/3NP3/2N5/PPP2PPP/R1BQKB1R w KQkq - 0 1", "Be3"),
    ("rnbqkb1r/pppppp1p/5np1/8/2PP4/8/PP2PPPP/RNBQKBNR w KQkq - 0 1", "Nc3"),
    ("rnbqkbnr/pp1p1ppp/4p3/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 0 1", "d4"),
    ("r1bqkb1r/pppp1ppp/2n2n2/1B2p3/4P3/5N2/PPPP1PPP/RNBQ1RK1 b kq - 0 1", "Nxe4"),
    ("r1bqkb1r/pppp1ppp/2n5/1B2p3/4n3/5N2/PPPP1PPP/RNBQ1RK1 w kq - 0 1", "Re1"),
    ("rnbqkb1r/ppp2ppp/4pn2/3p4/2PP4/2N2N2/PP2PPPP/R1BQKB1R b KQkq - 0 1", "Bb4"),
    ("rnbqkb1r/pppp1ppp/4pn2/8/2PP4/2N5/PP2PPPP/R1BQKBNR b KQkq - 0 1", "Bb4"),
    ("r1bqkbnr/1ppp1ppp/p1n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 1", "Ba4"),
    ("rnbqkbnr/ppp2ppp/4p3/3p4/3PP3/2N5/PPP2PPP/R1BQKBNR b KQkq - 0 1", "Nf6"),
    ("r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 0 1", "Nf6"),
    ("r1bqkbnr/1ppp1ppp/p1n5/4p3/B3P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 0 1", "Nf6"),
    ("rnbqkbnr/ppp1pppp/3p4/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1", "d4"),
    ("rnbqkbnr/ppp1pppp/3p4/8/3PP3/8/PPP2PPP/RNBQKBNR b KQkq - 0 1", "Nf6"),
    ("rnbqkb1r/pppppp1p/5np1/8/2PP4/2N5/PP2PPPP/R1BQKBNR b KQkq - 0 1", "Bg7"),
    ("r1bqkb1r/pppp1ppp/2n5/1B2p3/4n3/5N2/PPPP1PPP/RNBQR1K1 b kq - 0 1", "Nd6"),
    ("r1bqkb1r/pppp1ppp/2nn4/1B2p3/8/5N2/PPPP1PPP/RNBQR1K1 w kq - 0 1", "Nxe5"),
    ("r1bqkb1r/pppp1ppp/2nn4/1B2N3/8/8/PPPP1PPP/RNBQR1K1 b kq - 0 1", "Be7"),
    ("r1bqk2r/ppppbppp/3n4/4R3/8/8/PPPP1PPP/RNBQ1BK1 b kq - 0 1", "O-O"),
    ("r1bq1rk1/ppppbppp/3n4/4R3/8/8/PPPP1PPP/RNBQ1BK1 w - - 0 1", "d4"),
    ("rnbqkbnr/pp2pppp/2p5/3p4/2PP4/8/PP2PPPP/RNBQKBNR w KQkq - 0 1", "Nf3"),
    ("rnbqkbnr/pp1ppppp/8/2p5/4P3/2N5/PPPP1PPP/R1BQKBNR b KQkq - 0 1", "Nc6"),
    ("rnbqk2r/pppp1ppp/4pn2/8/1bPP4/2N5/PP2PPPP/R1BQKBNR w KQkq - 0 1", "e3"),
    ("r1bq1rk1/ppppbppp/3n4/4R3/3P4/8/PPP2PPP/RNBQ1BK1 b - - 0 1", "Bf6"),
  ]

  /// Real blunders the judge should catch. Reported, not asserted: the
  /// Chigorin 4.Nc3 sits right at the 80cp line for this engine.
  static let blunders: [(line: [String], san: String)] = [
    // Chigorin: 4.Nc3 drops d4 to ...Qxd4.
    (["d4", "d5", "c4", "Nc6", "cxd5", "Qxd5"], "Nc3"),
    // ...Qh4 hangs the queen to Nxh4.
    (["e4", "e5", "Nf3", "Nc6", "Bc4"], "Qh4"),
    // ...Nf6 allows Qxf7 mate.
    (["e4", "e5", "Qh5", "Nc6", "Bc4"], "Nf6"),
  ]

  func verdict(_ engine: CaissaEngine, _ fen: String, _ san: String) async -> Judgement? {
    guard let move = applySan(fen, san), let base = await baseline(engine, fen, moments: false) else { return nil }
    return await judge(engine, base, san: san, uci: move.uci, color: fenTurn(fen), moments: false)
  }

  /// The judge's procedure, as Survival runs it, on known answers.
  @Test func judgeBench() async {
    let started = Date()
    var flagged: [String] = []
    for c in Self.bookMoves {
      let engine = CaissaEngine()
      guard let v = await verdict(engine, c.fen, c.san) else { continue }
      if !v.ok { flagged.append("\(c.san) (lost \(Int(v.lost)))") }
    }
    var missed: [String] = []
    for c in Self.blunders {
      let fen = walkSan(c.line).fens.last!
      if let v = await verdict(CaissaEngine(), fen, c.san), v.ok { missed.append("\(c.san) (lost \(Int(v.lost)), best \(v.best ?? "?"))") }
    }
    print("BENCH judge: false blunders \(flagged.count)/\(Self.bookMoves.count) \(flagged), missed blunders \(missed.count)/\(Self.blunders.count) \(missed), \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
  }

  /// Book positions after the first trades, where the opponent plays once the book runs out.
  static let middlegames = [
    "r1bqk2r/ppppbppp/3n4/4R3/8/8/PPPP1PPP/RNBQ1BK1 b kq - 0 1",
    "r1bq1rk1/ppppbppp/3n4/4R3/8/8/PPPP1PPP/RNBQ1BK1 w - - 0 1",
    "r1bq1rk1/ppppbppp/3n4/4R3/3P4/8/PPP2PPP/RNBQ1BK1 b - - 0 1",
    "r1bq1rk1/pppp1ppp/3n1b2/4R3/3P4/8/PPP2PPP/RNBQ1BK1 w - - 0 1",
    "r1bq1rk1/pppp1ppp/3n1b2/8/3P4/8/PPP1RPPP/RNBQ1BK1 b - - 0 1",
    "r1bq1rk1/pppp1ppp/3n1b2/8/3P4/8/PPP2PPP/RNBQRBK1 b - - 0 1",
    "r1bqkb1r/ppp2ppp/2pn4/4P3/8/5N2/PPP2PPP/RNBQ1RK1 b kq - 0 1",
    "r1bqkb1r/ppp2ppp/2p5/4Pn2/8/5N2/PPP2PPP/RNBQ1RK1 w kq - 0 1",
    "r1bQkb1r/ppp2ppp/2p5/4Pn2/8/5N2/PPP2PPP/RNB2RK1 b kq - 0 1",
    "r1bk1b1r/ppp2ppp/2p5/4Pn2/8/5N2/PPP2PPP/RNB2RK1 w - - 0 1",
    "rnbqkb1r/pp3ppp/2p2p2/8/3P4/8/PPP2PPP/R1BQKBNR w KQkq - 0 1",
    "r1bk1b1r/ppp2ppp/2p5/4Pn2/8/2N2N2/PPP2PPP/R1B2RK1 b - - 0 1",
    "rnbqkb1r/ppp1pp1p/6p1/8/3PP3/2P5/P4PPP/R1BQKBNR b KQkq - 0 1",
    "rnbqk2r/ppp1ppbp/6p1/8/3PP3/2P5/P4PPP/R1BQKBNR w KQkq - 0 1",
    "r2k1b1r/pppb1ppp/2p5/4Pn2/8/2N2N2/PPP2PPP/R1B2RK1 w - - 0 1",
    "rnbqkb1r/pp3ppp/2p2p2/8/3P4/2P5/PP3PPP/R1BQKBNR b KQkq - 0 1",
    "rnbqk2r/pp3ppp/2pb1p2/8/3P4/2P5/PP3PPP/R1BQKBNR w KQkq - 0 1",
    "rnbqk2r/pp3ppp/2pb1p2/8/3P4/2PB4/PP3PPP/R1BQK1NR b KQkq - 0 1",
    "rnbqk2r/ppp1ppbp/6p1/8/3PP3/2P2N2/P4PPP/R1BQKB1R b KQkq - 0 1",
    "r1bqk2r/p1pp1ppp/2p2n2/8/1b2P3/2N5/PPP2PPP/R1BQKB1R w KQkq - 0 1",
    "rnbq1rk1/pp3ppp/2pb1p2/8/3P4/2PB4/PP3PPP/R1BQK1NR w KQ - 0 1",
    "rnbk1b1r/ppp2ppp/5n2/4p3/4P3/2N5/PPP2PPP/R1B1KBNR w KQ - 0 1",
    "r1bqk2r/p1pp1ppp/2p2n2/8/1b2P3/2NB4/PPP2PPP/R1BQK2R b KQkq - 0 1",
    "r2k1b1r/pppb1ppp/2p5/4Pn2/8/2N2N2/PPP2PPP/R1BR2K1 b - - 0 1",
    "r1bqkb1r/p1pp1ppp/2p2n2/8/4P3/8/PPP2PPP/RNBQKB1R w KQkq - 0 1",
    "r1bqkb1r/pp3ppp/2np4/1N1Pp3/8/8/PPP2PPP/R1BQKB1R b KQkq - 0 1",
    "rnbqk2r/pp2ppbp/6p1/2p5/3PP3/2P2N2/P4PPP/R1BQKB1R w KQkq - 0 1",
    "r1bqkb1r/p2p1ppp/2p1pn2/8/4P3/2N5/PPP2PPP/R1BQKB1R w KQkq - 0 1",
    "rnb2rk1/ppp2pp1/4pq1p/8/1bBP4/2N1PN2/PP3PPP/2RQK2R b K - 0 1",
    "rnb2rk1/pp3pp1/4pq1p/2p5/1bBP4/2N1PN2/PP3PPP/2RQK2R w K - 0 1",
    "rnbqkb1r/pp2pppp/2p5/8/4Q3/5N2/PPPP1PPP/R1B1KB1R b KQkq - 0 1",
    "r1bqkb1r/p2p1ppp/2p1pn2/4P3/8/2N5/PPP2PPP/R1BQKB1R b KQkq - 0 1",
    "r1bqkb1r/p2p1ppp/2p1p3/3nP3/8/2N5/PPP2PPP/R1BQKB1R w KQkq - 0 1",
    "r1bqkb1r/p2p1ppp/2p1p3/3nP3/4N3/8/PPP2PPP/R1BQKB1R b KQkq - 0 1",
    "rnbq1rk1/pp3ppp/2pb1p2/8/3P4/2PB4/PPQ2PPP/R1B1K1NR b KQ - 0 1",
    "rnbqkb1r/ppp2ppp/3p4/8/8/2P2N2/PPP2PPP/R1BQKB1R b KQkq - 0 1",
    "r1bqkb1r/pppp1ppp/3n4/1B2R3/8/8/PPPP1PPP/RNBQ2K1 b kq - 0 1",
    "r1bqk2r/ppppbppp/3n4/1B2R3/8/8/PPPP1PPP/RNBQ2K1 w kq - 0 1",
    "rnb1k2r/pp3ppp/2p2q2/3p4/2PPp3/2P1P1P1/P4PBP/R2QK1NR b KQkq - 0 1",
    "r1b1k2r/pp1n1ppp/2p2q2/3p4/2PPp3/2P1P1P1/P4PBP/R2QK1NR w KQkq - 0 1",
    "r1b1k2r/pp1n1ppp/2p2q2/3P4/3Pp3/2P1P1P1/P4PBP/R2QK1NR b KQkq - 0 1",
    "r1bqk2r/p1p2ppp/2p2n2/3p4/1b2P3/2NB4/PPP2PPP/R1BQK2R w KQkq - 0 1",
    "rnbqkb1r/pp3ppp/3p4/1N1Pp3/8/8/PPP2PPP/R1BQKB1R w KQkq - 0 1",
    "rnbqk2r/ppp1bppp/3p4/8/8/2P2N2/PPP2PPP/R1BQKB1R w KQkq - 0 1",
    "rnbqr1k1/pp3ppp/2pb1p2/8/3P4/2PB4/PPQ2PPP/R1B1K1NR w KQ - 0 1",
    "rnbqr1k1/pp3ppp/2pb1p2/8/3P4/2PB4/PPQ1NPPP/R1B1K2R b KQ - 0 1",
    "rnb2rk1/pp3pp1/4pq1p/2p5/1bBP4/2N1PN2/PP3PPP/2RQ1RK1 b - - 0 1",
    "r1bqnrk1/ppppbppp/8/4R3/3P4/8/PPP2PPP/RNBQ1BK1 w - - 0 1"
,
  ]

  func score(_ line: EngineLine) -> Double? {
    if let cp = line.cp { return cp }
    return line.mate.map { $0 > 0 ? 10_000 - Double($0) : -10_000 - Double($0) }
  }

  /// What each level's moves cost on average, against a deeper search: how
  /// human each level plays, to set beside the ratings' expected losses.
  @Test func levelBench() async {
    let started = Date()
    let reference = EngineLimits(depth: 12, movetime: 800, multiPv: 1)
    let engine = CaissaEngine(), judge = CaissaEngine()
    var report: [String] = []
    for level in LEVEL_RATINGS.map(levelFor(rating:)) {
      let rand = mulberry32(seed: Double(level.rating))
      var total = 0.0, slips = 0, blunders = 0
      for fen in Self.middlegames {
        let snap = await engine.analyse(fen, EngineLimits(depth: level.depth, multiPv: level.multiPv))
        guard let move = chooseMove(snap.lines, level, rand),
              let best = await judge.analyse(fen, reference).lines.first?.pv.first else { continue }
        if move == best { continue }
        var limits = reference
        limits.multiPv = 2
        limits.searchmoves = [best, move]
        let lines = await judge.analyse(fen, limits).lines
        guard let top = lines.first(where: { $0.pv.first == best }).flatMap(score),
              let mine = lines.first(where: { $0.pv.first == move }).flatMap(score) else { continue }
        // Scores are White's; the loss is the mover's.
        let sign: Double = fenTurn(fen) == .w ? 1 : -1
        let loss = min(1000, max(0, sign * (top - mine)))
        total += loss
        if loss >= 50 { slips += 1 }
        if loss >= 200 { blunders += 1 }
      }
      let n = Double(Self.middlegames.count)
      report.append(String(format: "%@: avg loss %.0f (expected %.0f), 50+ %d, 200+ %d", level.name, total / n, expectedLoss(Double(level.rating)), slips, blunders))
    }
    print("BENCH levels over \(Self.middlegames.count) positions: \(report.joined(separator: " | ")), \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
  }
}
