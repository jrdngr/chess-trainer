import ChessCore
import Model

/// Each side's best pawn break, for the Pawns lens.
/// Asked on its own engine, so a held lens never interrupts the game.
public enum PawnBreaks {
  static let thinkMs: Double = 300
  /// How much worse than the best move a break may be and still be drawn.
  public static let slack: Double = 150

  public typealias Breaks = [ChessCore.Color: (from: String, to: String)]

  private static let cache = Cache()

  public static func find(_ engine: ChessEngine, _ fen: String) async -> Breaks {
    let key = fen.split(separator: " ").prefix(2).joined(separator: " ")
    if let found = await cache.get(key) { return found }
    var breaks: Breaks = [:]
    for color in [ChessCore.Color.w, .b] {
      if let move = await best(engine, fen, color) { breaks[color] = move }
    }
    await cache.set(key, breaks)
    return breaks
  }

  private static func best(_ engine: ChessEngine, _ fen: String, _ color: ChessCore.Color) async -> (from: String, to: String)? {
    guard let mover = asMover(fen, color) else { return nil }
    let candidates = breakCandidates(mover, color)
    if candidates.isEmpty { return nil }
    let all = await engine.analyse(mover, EngineLimits(movetime: thinkMs, multiPv: 1))
    let only = await engine.analyse(mover, EngineLimits(movetime: thinkMs, multiPv: 1, searchmoves: candidates))
    guard let best = score(all.lines.first, color), let brk = score(only.lines.first, color),
      let uci = only.lines.first?.pv.first, candidates.contains(uci), best - brk <= slack
    else { return nil }
    return (String(uci.prefix(2)), String(uci.dropFirst(2).prefix(2)))
  }

  /// From `color`'s side, a mate counted as 100000.
  private static func score(_ line: EngineLine?, _ color: ChessCore.Color) -> Double? {
    guard let line else { return nil }
    let white = line.mate.map { $0 > 0 ? 100000 : $0 < 0 ? -100000 : 0 } ?? (line.cp ?? 0)
    return color == .w ? white : -white
  }

  private actor Cache {
    var entries: [String: Breaks] = [:]
    var order: [String] = []
    func get(_ key: String) -> Breaks? { entries[key] }
    func set(_ key: String, _ value: Breaks) {
      if entries.updateValue(value, forKey: key) == nil { order.append(key) }
      if order.count > 200 { entries[order.removeFirst()] = nil }
    }
  }
}
