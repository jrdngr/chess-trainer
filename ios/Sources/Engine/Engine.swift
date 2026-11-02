import ChessCore
import Foundation
import Model

/// What a search is asked for.
public struct EngineLimits: Sendable {
  /// With movetime as well, the search stops at whichever it reaches first.
  public var depth: Int?
  public var movetime: Double?
  public var multiPv: Int?
  /// Only consider these root moves (UCI).
  public var searchmoves: [String]?
  public init(depth: Int? = nil, movetime: Double? = nil, multiPv: Int? = nil, searchmoves: [String]? = nil) {
    self.depth = depth
    self.movetime = movetime
    self.multiPv = multiPv
    self.searchmoves = searchmoves
  }
}

public struct EngineSnapshot: Sendable {
  public var lines: [EngineLine]
  public var depth: Int
  public var nodes: Int
  public var thinking: Bool
  public var fen: String
}

/// An engine behind one protocol, so a stronger one can take its place.
/// `onUpdate` sees each finished depth; the result is the last word.
public protocol ChessEngine: Sendable {
  func analyse(_ fen: String, _ limits: EngineLimits, onUpdate: @escaping @Sendable (EngineSnapshot) -> Bool) async -> EngineSnapshot
}

extension ChessEngine {
  public func analyse(_ fen: String, _ limits: EngineLimits) async -> EngineSnapshot {
    await analyse(fen, limits) { _ in false }
  }
}

/// The engine: the search in `Basic/`.
/// `onUpdate` returning true stops the search there.
public actor BasicEngine: ChessEngine {
  /// How long a search runs when the caller only names a depth, and the longest any runs:
  /// the judge's confirmation of a suspected blunder.
  static let defaultMs: Double = 1000
  static let maxMs: Double = CONFIRM_MS

  private let tt = TranspositionTable()

  public init() {}

  public func analyse(_ fen: String, _ limits: EngineLimits, onUpdate: @escaping @Sendable (EngineSnapshot) -> Bool) async -> EngineSnapshot {
    let options = SearchOptions(
      maxDepth: limits.depth ?? 64, timeMs: max(50, min(limits.movetime ?? Self.defaultMs, Self.maxMs)),
      multiPv: limits.multiPv ?? 3, searchmoves: limits.searchmoves)
    var stop = false
    let result = search(fen, options, tt, onDepth: { depth in
      if onUpdate(snapshotOf(fen, depth, thinking: true)) { stop = true }
    }, stopped: { stop || Task.isCancelled })
    return snapshotOf(fen, result, thinking: false)
  }
}

/// A search result in White's frame, as the app reads engines.
func snapshotOf(_ fen: String, _ result: DepthResult?, thinking: Bool) -> EngineSnapshot {
  let sign: Double = fenTurn(fen) == .b ? -1 : 1
  let lines = (result?.lines ?? []).enumerated().map { i, line in
    EngineLine(
      multipv: i + 1, depth: result!.depth,
      cp: line.mate == nil ? sign * Double(max(-2000, min(2000, line.score))) : nil,
      mate: line.mate.map { sign * Double($0) }, pv: line.pv)
  }
  return EngineSnapshot(lines: lines, depth: result?.depth ?? 0, nodes: result?.nodes ?? 0, thinking: thinking, fen: fen)
}

/// A score as Analysis writes it, in White's frame: "+0.35", "-M3". `formatScore`.
public func formatScore(_ line: EngineLine) -> String {
  if let mate = line.mate { return "\(mate > 0 ? "" : "-")M\(Int(abs(mate)))" }
  guard let cp = line.cp else { return "\u{2014}" }
  // A zero reads "+0.00" whatever its sign, as JavaScript prints it.
  let pawns = cp == 0 ? 0 : cp / 100
  return (pawns < 0 ? "" : "+") + String(format: "%.2f", pawns)
}

/// 0...1 of the eval bar that is White's. `winFraction`.
public func winFraction(_ line: EngineLine?) -> Double {
  guard let line else { return 0.5 }
  if let mate = line.mate { return mate > 0 ? 1 : 0 }
  guard let cp = line.cp else { return 0.5 }
  return 1 / (1 + exp(-cp / 320))
}
