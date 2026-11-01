import ChessCore
import Foundation
import Testing
@testable import Engine

/// Speed of the engine's board and search, printed for comparing builds.
/// Fixed depths, so the work is the same from run to run.
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
}
