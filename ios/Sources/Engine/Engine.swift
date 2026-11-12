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
  public init(lines: [EngineLine], depth: Int, nodes: Int, thinking: Bool, fen: String) {
    self.lines = lines
    self.depth = depth
    self.nodes = nodes
    self.thinking = thinking
    self.fen = fen
  }
}

/// An engine behind one protocol. `onUpdate` sees each finished depth; the result is the last word.
public protocol ChessEngine: Sendable {
  func analyse(_ fen: String, _ limits: EngineLimits, onUpdate: @escaping @Sendable (EngineSnapshot) -> Bool) async -> EngineSnapshot
}

extension ChessEngine {
  public func analyse(_ fen: String, _ limits: EngineLimits) async -> EngineSnapshot {
    await analyse(fen, limits) { _ in false }
  }
}

/// A new engine, with its own memory of positions.
public func makeEngine() -> ChessEngine { CaissaEngine() }

/// One use's engine, made the first time it is asked for, so a use keeps its
/// own engine (and its memory) apart from other uses.
public final class EngineSlot: @unchecked Sendable {
  private let lock = NSLock()
  private var made: ChessEngine?

  public init() {}

  /// This use's engine.
  public func callAsFunction() -> ChessEngine {
    lock.withLock {
      if let made { return made }
      let engine = makeEngine()
      made = engine
      return engine
    }
  }

  /// This use's engine.
  public var current: ChessEngine { self() }
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
