import ChessCore
import Model

/// Which open steps of a plan the engine says to hold off on: the first move
/// toward each loses more than `slack` against the best move.
/// Asked on its own engine at low depth, so it never holds up the game.
public enum PlanChecks {
  static let depth = 6
  static let thinkMs: Double = 250
  public static let slack: Double = 100

  private static let cache = Cache()

  /// The steps, by index, that are not yet good to start.
  public static func notYet(_ engine: ChessEngine, _ fen: String, _ me: ChessCore.Color, _ steps: [PlanStep], open: [Bool]) async -> Set<Int> {
    var moves: [Int: String] = [:]
    for (i, step) in steps.enumerated() where open[i] {
      if let uci = firstMove(step, fen, me) { moves[i] = uci }
    }
    if moves.isEmpty { return [] }
    let position = fen.split(separator: " ").prefix(4).joined(separator: " ")
    guard let best = await bestScore(engine, fen, position, me, nil) else { return [] }
    var out: Set<Int> = []
    for (i, uci) in moves.sorted(by: { $0.key < $1.key }) {
      if Task.isCancelled { return out }
      guard let score = await bestScore(engine, fen, position, me, uci) else { continue }
      if best - score > slack { out.insert(i) }
    }
    return out
  }

  /// The best score from `me`'s side, over every move or only `uci`.
  private static func bestScore(_ engine: ChessEngine, _ fen: String, _ position: String, _ me: ChessCore.Color, _ uci: String?) async -> Double? {
    let key = position + " " + (uci ?? "*")
    if let found = await cache.get(key) { return found }
    let snap = await engine.analyse(fen, EngineLimits(depth: depth, movetime: thinkMs, multiPv: 1, searchmoves: uci.map { [$0] }))
    guard let line = snap.lines.first, let white = whiteCp(cp: line.cp, mate: line.mate) else { return nil }
    let score = me == .w ? white : -white
    await cache.set(key, score)
    return score
  }

  private actor Cache {
    var entries: [String: Double] = [:]
    var order: [String] = []
    func get(_ key: String) -> Double? { entries[key] }
    func set(_ key: String, _ value: Double) {
      if entries.updateValue(value, forKey: key) == nil { order.append(key) }
      if order.count > 400 { entries[order.removeFirst()] = nil }
    }
  }
}
