import ChessCore
import Engine
import Model
import Observation

/// What the hint engine says of single moves, asked one at a time and kept
/// for the app's lifetime: what a line's moves give away, for the Save sheet,
/// and whether a move off the book is sound, for Tidy and Growth.
@MainActor @Observable
final class EngineChecks {
  static let shared = EngineChecks()

  /// What a move gives away against the engine's best, and the position's worth after it.
  struct MoveCheck: Equatable {
    /// Centipawns given away, from the mover's side. Never negative.
    var lost: Double
    /// Centipawns from White's side.
    var after: Double
    /// The engine's own move here, in UCI.
    var best: String?
  }

  private(set) var checks: [String: MoveCheck?] = [:]
  private(set) var sound: [String: Bool] = [:]

  private enum Job { case check(String, String), sound(String, String) }
  @ObservationIgnored private var queue: [Job] = []
  @ObservationIgnored private var busy = false

  private static func key(_ fen: String, _ san: String) -> String { "\(fen)|\(san)" }

  /// The check for a move, nil while not answered; `.some(nil)` when the engine could not judge it.
  func check(_ fen: String, _ san: String) -> MoveCheck?? { checks[Self.key(fen, san)] }

  /// Whether a move is sound; nil until known.
  func isSound(_ fen: String, _ san: String) -> Bool? { sound[Self.key(fen, san)] }

  func askCheck(_ fen: String, _ san: String) {
    guard checks[Self.key(fen, san)] == nil else { return }
    queue.append(.check(fen, san))
    pump()
  }

  func askSound(_ fen: String, _ san: String) {
    guard sound[Self.key(fen, san)] == nil else { return }
    queue.append(.sound(fen, san))
    pump()
  }

  private func pump() {
    guard !busy else { return }
    busy = true
    Task {
      while !queue.isEmpty {
        switch queue.removeFirst() {
        case .check(let fen, let san):
          let key = Self.key(fen, san)
          if checks[key] != nil { continue }
          checks[key] = .some(await Self.runCheck(fen, san))
        case .sound(let fen, let san):
          let key = Self.key(fen, san)
          if sound[key] != nil { continue }
          sound[key] = await Self.runSound(fen, san)
        }
      }
      busy = false
    }
  }

  private static func score(_ line: EngineLine?) -> Double? { line.flatMap { whiteCp(cp: $0.cp, mate: $0.mate) } }

  private static func runCheck(_ fen: String, _ san: String) async -> MoveCheck? {
    guard let move = applySan(fen, san) else { return nil }
    let engine = HintEngine.shared
    let full = await engine.analyse(fen, EngineLimits(depth: 14, movetime: 700, multiPv: 1))
    guard let best = full.lines.first, let before = score(best) else { return nil }
    if best.pv.first == move.uci { return MoveCheck(lost: 0, after: before, best: move.uci) }
    let held = await engine.analyse(fen, EngineLimits(depth: 14, movetime: 700, multiPv: 1, searchmoves: [move.uci]))
    guard let after = score(held.lines.first) else { return nil }
    return MoveCheck(lost: max(0, evalLoss(fenTurn(fen), before, after)), after: after, best: best.pv.first)
  }

  private static func runSound(_ fen: String, _ san: String) async -> Bool {
    guard let move = applySan(fen, san) else { return false }
    let engine = HintEngine.shared
    let scoreOf = { (line: EngineLine?) -> Double? in
      guard let line else { return nil }
      if let cp = line.cp { return cp }
      return line.mate.map { $0 > 0 ? 10_000 : -10_000 }
    }
    guard let before = scoreOf(await engine.analyse(fen, EngineLimits(movetime: 400, multiPv: 1)).lines.first),
      let after = scoreOf(await engine.analyse(fen, EngineLimits(movetime: 400, multiPv: 1, searchmoves: [move.uci])).lines.first)
    else { return false }
    return judgeByEval(fenTurn(fen), before, after).ok
  }
}
