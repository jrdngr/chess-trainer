import ChessCore
import Engine
import Model
import Observation

/// What Growth asks the engine: the eval bar, with what each answer on
/// offer does to it.
@MainActor @Observable
public final class GrowthEngine {
  @ObservationIgnored private unowned let services: GameServices

  public init(services: GameServices) {
    self.services = services
  }

  /// The eval of a position, and of the moves offered there, centipawns from White's side.
  public struct Evals: Equatable {
    public var position: Double?
    public var moves: [String: Double] = [:]
  }

  private var known: [String: Evals] = [:]
  private var positions: [String: Double] = [:]

  @ObservationIgnored private var evalWaiting: (fen: String, sans: [String])?
  @ObservationIgnored private var evalBusy = false

  private static let depth = 16
  private static let evalMs: Double = 1200

  /* ── the eval bar ── */

  private static func key(_ fen: String, _ sans: [String]) -> String {
    "\(positionKey(fen))|\(sans.sorted().joined(separator: " "))"
  }

  /// The eval of a position and its moves as far as worked out, asking for the rest.
  public func evals(_ fen: String, _ sans: [String]) -> Evals {
    if let full = known[Self.key(fen, sans)] { return full }
    return Evals(position: positions[positionKey(fen)])
  }

  /// Only the position being looked at is worked out: a newer ask replaces one still waiting.
  public func askEvals(_ fen: String, _ sans: [String]) {
    guard known[Self.key(fen, sans)] == nil else { return }
    evalWaiting = (fen, sans)
    guard !evalBusy else { return }
    evalBusy = true
    services.spawn { [self] in
      while let next = evalWaiting {
        evalWaiting = nil
        if known[Self.key(next.fen, next.sans)] == nil { await evaluate(next.fen, next.sans) }
      }
      evalBusy = false
    }
  }

  private func evaluate(_ fen: String, _ sans: [String]) async {
    let engine = services.hints
    var position = positions[positionKey(fen)]
    if position == nil {
      let snap = await engine.analyse(fen, EngineLimits(depth: Self.depth, movetime: Self.evalMs, multiPv: 1))
      guard let line = snap.lines.first, let cp = whiteCp(cp: line.cp, mate: line.mate) else { return }
      position = cp
      positions[positionKey(fen)] = cp
    }
    let ucis = sans.compactMap { applySan(fen, $0)?.uci }
    var moves: [String: Double] = [:]
    if !ucis.isEmpty {
      let snap = await engine.analyse(
        fen, EngineLimits(depth: Self.depth, movetime: Self.evalMs, multiPv: ucis.count, searchmoves: ucis))
      for line in snap.lines {
        guard let uci = line.pv.first, let at = ucis.firstIndex(of: uci), let cp = whiteCp(cp: line.cp, mate: line.mate) else { continue }
        moves[sans.filter { applySan(fen, $0) != nil }[at]] = cp
      }
    }
    // The position is worth at least its best move: two searches never agree exactly.
    let white = fenTurn(fen) == .w
    for cp in moves.values { position = white ? max(position!, cp) : min(position!, cp) }
    positions[positionKey(fen)] = position
    known[Self.key(fen, sans)] = Evals(position: position, moves: moves)
  }
}
