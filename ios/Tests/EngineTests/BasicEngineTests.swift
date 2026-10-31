import ChessCore
import Foundation
import Testing
@testable import Engine

/// The backup engine's own tests: `src/engine/basic/basic.test.ts`.
struct BasicEngineTests {
  func perft(_ pos: Position, _ depth: Int) -> Int {
    if depth == 0 { return 1 }
    var total = 0
    for move in pos.pseudoMoves() where pos.make(move) {
      total += perft(pos, depth - 1)
      pos.unmake(move)
    }
    return total
  }

  @Test(arguments: [
    (START_FEN, 3, 8902),
    ("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", 2, 2039),
    ("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", 3, 2812),
    ("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", 3, 9467),
    ("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", 2, 1486),
  ])
  func board(fen: String, depth: Int, nodes: Int) {
    #expect(perft(Position(fen), depth) == nodes)
  }

  let quick = SearchOptions(maxDepth: 64, timeMs: 400, multiPv: 1)
  func fenAfter(_ sans: [String]) -> String { walkSan(sans).fens.last! }

  @Test func takesAHangingQueen() {
    let r = search("rnb1kbnr/pppp1ppp/8/4p1q1/3P4/2N5/PPP1PPPP/R1BQKBNR w KQkq - 0 1", quick, TranspositionTable())!
    #expect(r.lines[0].uci == "c1g5")
  }

  @Test func findsAMateInOne() {
    let r = search("6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1", quick, TranspositionTable())!
    #expect(r.lines[0].uci == "d1d8")
    #expect(r.lines[0].mate == 1)
  }

  @Test func seesTheRecapture() {
    let fen = fenAfter(["d4", "d5", "c4", "Nc6", "cxd5", "Qxd5", "Nc3"])
    var opts = quick
    opts.multiPv = 3
    for line in search(fen, opts, TranspositionTable())!.lines { #expect(abs(line.score) < 150) }
    opts = quick
    opts.timeMs = 800
    let best = search(fen, opts, TranspositionTable())!.lines[0]
    #expect(best.uci == "d5d4")
    #expect(best.score > 0)
  }

  @Test func scoresOnlyTheMovesAskedFor() {
    let r = search(START_FEN, SearchOptions(maxDepth: 64, timeMs: 400, multiPv: 3, searchmoves: ["e2e4", "a2a3"]), TranspositionTable())!
    #expect(r.lines.map(\.uci).sorted() == ["a2a3", "e2e4"])
    #expect(r.lines[0].uci == "e2e4")
  }

  @Test func stopsNearItsTimeLimit() {
    let started = Date()
    _ = search(fenAfter(["e4", "e5", "Nf3", "Nc6", "Bb5", "a6"]), SearchOptions(maxDepth: 64, timeMs: 300, multiPv: 3), TranspositionTable())
    #expect(Date().timeIntervalSince(started) < 1.5)
  }

  @Test func nothingWithNoLegalMoves() {
    #expect(search("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1", quick, TranspositionTable()) == nil)
  }

  @Test func judgesABlunder() async {
    let engine = BasicEngine()
    // 1.e4 e5 2.Nf3 Nc6 3.Bc4: ...Qh4 hangs the queen to Nxh4.
    let fen = fenAfter(["e4", "e5", "Nf3", "Nc6", "Bc4"])
    let base = await baseline(engine, fen, moments: true)!
    let verdict = await judge(engine, base, san: "Qh4", uci: "d8h4", color: .b, moments: true)
    #expect(!verdict.ok)
    let sound = await judge(engine, base, san: "Nf6", uci: "g8f6", color: .b, moments: true)
    #expect(sound.ok)
  }
}
