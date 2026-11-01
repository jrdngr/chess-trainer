import ChessCore
import Foundation
import Model
import Testing
@testable import Engine

/// How the engine does, printed for comparing builds. Runs only with
/// ENGINE_BENCH set (CI's release step), since the judge bench takes minutes.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ENGINE_BENCH"] != nil))
struct EngineBenchTests {
  static let positions = [
    START_FEN,
    "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
    "r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4",
    "r2q1rk1/pp2bppp/2n1pn2/3p4/2PP4/2N1PN2/PP3PPP/R2QKB1R w KQ - 0 9",
  ]

  func perft(_ pos: Position, _ depth: Int) -> Int {
    if depth == 0 { return 1 }
    var total = 0
    for move in pos.pseudoMoves() where pos.make(move) {
      total += perft(pos, depth - 1)
      pos.unmake(move)
    }
    return total
  }

  /// Speed: fixed depths, so the work is the same from run to run.
  @Test func bench() {
    var started = Date()
    let nodes = perft(Position(START_FEN), 4) + perft(Position(Self.positions[1]), 3)
    let perftSeconds = Date().timeIntervalSince(started)
    #expect(nodes == 197_281 + 97_862)

    started = Date()
    var searched = 0
    for fen in Self.positions {
      searched += search(fen, SearchOptions(maxDepth: 6, timeMs: 60_000, multiPv: 1), TranspositionTable())!.nodes
    }
    let searchSeconds = Date().timeIntervalSince(started)
    print(String(
      format: "BENCH perft %d nodes %.3fs (%.0f knps) | search %d nodes %.3fs (%.0f knps)",
      nodes, perftSeconds, Double(nodes) / perftSeconds / 1000, searched, searchSeconds, Double(searched) / searchSeconds / 1000))
  }

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

  /// Real blunders the judge has to catch.
  static let blunders: [(line: [String], san: String)] = [
    // Chigorin: 4.Nc3 drops d4 to ...Qxd4.
    (["d4", "d5", "c4", "Nc6", "cxd5", "Qxd5"], "Nc3"),
    // ...Qh4 hangs the queen to Nxh4.
    (["e4", "e5", "Nf3", "Nc6", "Bc4"], "Qh4"),
    // ...Nf6 allows Qxf7 mate.
    (["e4", "e5", "Qh5", "Nc6", "Bc4"], "Nf6"),
  ]

  func verdict(_ engine: BasicEngine, _ fen: String, _ san: String) async -> Judgement? {
    guard let move = applySan(fen, san), let base = await baseline(engine, fen, moments: false) else { return nil }
    return await judge(engine, base, san: san, uci: move.uci, color: fenTurn(fen), moments: false)
  }

  /// The judge's procedure, as Survival runs it, on known answers.
  @Test func judgeBench() async {
    let started = Date()
    var flagged: [String] = []
    for c in Self.bookMoves {
      let engine = BasicEngine()
      guard let v = await verdict(engine, c.fen, c.san) else { continue }
      if !v.ok { flagged.append("\(c.san) (lost \(Int(v.lost)))") }
    }
    var missed: [String] = []
    for c in Self.blunders {
      let fen = walkSan(c.line).fens.last!
      if let v = await verdict(BasicEngine(), fen, c.san), v.ok { missed.append(c.san) }
    }
    print("BENCH judge: false blunders \(flagged.count)/\(Self.bookMoves.count) \(flagged), missed blunders \(missed.count)/\(Self.blunders.count) \(missed), \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
    #expect(missed.isEmpty)
  }
}
