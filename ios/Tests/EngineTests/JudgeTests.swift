import ChessCore
import Model
import Testing
@testable import Engine

/// An engine that scores each root move it is asked about from a table, White's side, with its line
/// from `lines` (the move alone when none is given).
struct TableEngine: ChessEngine {
  let scores: [String: Double]
  var lines: [String: [String]] = [:]
  func analyse(_ fen: String, _ limits: EngineLimits, onUpdate: @escaping @Sendable (EngineSnapshot) -> Bool) async -> EngineSnapshot {
    let moves = limits.searchmoves ?? Array(scores.keys)
    let lines = moves.compactMap { uci in scores[uci].map { (uci, $0) } }
      .sorted { $0.1 > $1.1 }
      .enumerated()
      .map { EngineLine(multipv: $0.offset + 1, depth: CONFIRM_DEPTH, cp: $0.element.1, mate: nil, pv: self.lines[$0.element.0] ?? [$0.element.0]) }
    return EngineSnapshot(lines: lines, depth: CONFIRM_DEPTH, nodes: 1, thinking: false, fen: fen)
  }
}

/// After 1.e4 e6 2.d4 d5 3.Nc3 Nf6 4.e5 Nfd7 5.Nf3 c5 6.Bd3 cxd4 7.Nxd4 Nc6: 8.Nxe6 is the
/// moment, 8.Nxc6 the next best.
struct JudgeTests {
  static let fen = "r1bqkb1r/pp1n1ppp/2n1p3/3pP3/3N4/2NB4/PPP2PPP/R1BQK2R w KQkq - 2 8"
  static let scores: [String: Double] = ["d4e6": 150, "d4c6": -35, "c1e3": -108, "e1g1": -498]
  /// After 8.O-O the knight on d4 falls: the line is down a knight and stays down.
  static let engine = TableEngine(scores: scores, lines: ["e1g1": ["e1g1", "c6d4", "a2a3", "a7a6", "b2b3"]])
  static let base = Baseline(fen: fen, cp: 150, best: "Nxe6", bestUci: "d4e6", second: (cp: -35, uci: "d4c6"))

  func judged(_ san: String, _ engine: TableEngine = Self.engine) async throws -> Judgement {
    let move = try #require(applySan(Self.fen, san))
    return await judge(engine, Self.base, san: san, uci: move.uci, color: .w, moments: true)
  }

  /// A missed moment is weighed against the next best move, and the next best itself loses nothing more.
  @Test func aMissedMomentIsJudgedAgainstTheNextBest() async throws {
    #expect(Self.base.isMomentFor(.w))
    let next = try await judged("Nxc6")
    #expect(next.moment && !next.found)
    #expect(next.ok, "the next best move never ends the game")
    #expect(try await judged("Be3").ok, "73 under the next best is within the line")
    let far = try await judged("O-O")
    #expect(!far.ok, "far under the next best, losing a knight, is a blunder")
    #expect(far.line == ["c6d4"], "its line runs to the move that takes the knight")
  }

  /// A costly move whose line loses no material stands, with what it cost.
  @Test func aCostlyMoveWithoutAReasonStands() async throws {
    let far = try await judged("O-O", TableEngine(scores: Self.scores))
    #expect(far.ok)
    #expect(far.lost > 80)
  }
}

/// From a book position, a costly move the engine gives no line for, even searched again, stands: with no line there is
/// nothing to show. After 1.e4 e5 2.Bc4 Nf6 the book has 3.Bxf7+ losing 351.
@Test func aBookBlunderWithoutALineStands() async throws {
  let fen = try #require(walkSan(["e4", "e5", "Bc4", "Nf6"]).fens.last)
  let base = Baseline(fen: fen, cp: 30, best: "d3", bestUci: "d2d3", second: nil)
  /// Only the engine's own move comes back.
  let engine = TableEngine(scores: ["d2d3": 30])
  let judged = await judge(engine, base, san: "Bxf7+", uci: "c4f7", color: .w, moments: false)
  #expect(judged.ok && judged.line.isEmpty)
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
