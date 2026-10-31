import ChessCore
import Foundation
import Model

/// What a search is asked for: `src/engine/types.ts`.
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

/// The prototype's backup engine: `src/engine/heuristic.ts` and `basic/`.
/// `onUpdate` returning true stops the search there.
public actor BasicEngine: ChessEngine {
  /// How long a search runs when the caller only names a depth, and the longest any runs.
  static let defaultMs: Double = 1000
  static let maxMs: Double = 2000

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

/* ── the opponent ── */

/// A Play strength: `src/model/play.ts`.
public struct Level: Sendable {
  public var id: String
  public var depth: Int
  public var multiPv: Int
  /// How often it declines the best line, 0...1.
  public var slip: Double
}

/// The engine plays the opponent at Club once the book has nothing left.
public let OPPONENT_LEVEL = Level(id: "club", depth: 5, multiPv: 4, slip: 0.3)

/// Which candidate line to play: weights fall off geometrically from the best.
public func chooseMove(_ lines: [EngineLine], _ level: Level, _ rand: () -> Double) -> String? {
  let usable = lines.filter { !$0.pv.isEmpty }.sorted { $0.multipv < $1.multipv }
  guard let first = usable.first else { return nil }
  if usable.count == 1 || level.slip <= 0 { return first.pv[0] }
  let weights = usable.indices.map { $0 == 0 ? 1 - level.slip : level.slip / pow(2, Double($0)) }
  var ticket = rand() * weights.reduce(0, +)
  for (i, line) in usable.enumerated() {
    ticket -= weights[i]
    if ticket <= 0 { return line.pv[0] }
  }
  return usable.last!.pv[0]
}

/// The opponent's move where the book is silent, as SAN.
public func opponentMove(_ engine: ChessEngine, _ fen: String, _ rand: () -> Double) async -> String? {
  let snap = await engine.analyse(fen, EngineLimits(depth: OPPONENT_LEVEL.depth, multiPv: OPPONENT_LEVEL.multiPv))
  return chooseMove(snap.lines, OPPONENT_LEVEL, rand).flatMap { applyUci(fen, $0)?.san }
}
