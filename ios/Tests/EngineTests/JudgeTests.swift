import ChessCore
import Model
import Testing
@testable import Engine

/// An engine that scores each root move it is asked about from a table, White's side.
struct TableEngine: ChessEngine {
  let scores: [String: Double]
  func analyse(_ fen: String, _ limits: EngineLimits, onUpdate: @escaping @Sendable (EngineSnapshot) -> Bool) async -> EngineSnapshot {
    let moves = limits.searchmoves ?? Array(scores.keys)
    let lines = moves.compactMap { uci in scores[uci].map { (uci, $0) } }
      .sorted { $0.1 > $1.1 }
      .enumerated()
      .map { EngineLine(multipv: $0.offset + 1, depth: CONFIRM_DEPTH, cp: $0.element.1, mate: nil, pv: [$0.element.0]) }
    return EngineSnapshot(lines: lines, depth: CONFIRM_DEPTH, nodes: 1, thinking: false, fen: fen)
  }
}

/// After 1.e4 e6 2.d4 d5 3.Nc3 Nf6 4.e5 Nfd7 5.Nf3 c5 6.Bd3 cxd4 7.Nxd4 Nc6: 8.Nxe6 is the
/// moment, 8.Nxc6 the next best.
struct JudgeTests {
  static let fen = "r1bqkb1r/pp1n1ppp/2n1p3/3pP3/3N4/2NB4/PPP2PPP/R1BQK2R w KQkq - 2 8"
  static let engine = TableEngine(scores: ["d4e6": 150, "d4c6": -35, "c1e3": -108, "e1g1": -498])
  static let base = Baseline(fen: fen, cp: 150, best: "Nxe6", bestUci: "d4e6", second: (cp: -35, uci: "d4c6"))

  func judged(_ san: String) async throws -> Judgement {
    let move = try #require(applySan(Self.fen, san))
    return await judge(Self.engine, Self.base, san: san, uci: move.uci, color: .w, moments: true)
  }

  /// A missed moment is weighed against the next best move, and the next best itself loses nothing more.
  @Test func aMissedMomentIsJudgedAgainstTheNextBest() async throws {
    #expect(Self.base.isMomentFor(.w))
    let next = try await judged("Nxc6")
    #expect(next.moment && !next.found)
    #expect(next.ok, "the next best move never ends the game")
    #expect(try await judged("Be3").ok, "73 under the next best is within the line")
    let far = try await judged("O-O")
    #expect(!far.ok, "far under the next best is a blunder")
  }
}

/// Scores read with a true minus sign, and zero as +0.00.
@Test func scoresUseATrueMinus() {
  func line(cp: Double? = nil, mate: Double? = nil) -> EngineLine { EngineLine(multipv: 1, depth: 1, cp: cp, mate: mate, pv: []) }
  #expect(formatScore(line(cp: -35)) == "\u{2212}0.35")
  #expect(formatScore(line(cp: 120)) == "+1.20")
  #expect(formatScore(line(cp: 0)) == "+0.00")
  #expect(formatScore(line(mate: -3)) == "\u{2212}M3")
  #expect(formatScore(line(mate: 2)) == "M2")
}
