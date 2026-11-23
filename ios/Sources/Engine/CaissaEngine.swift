import Caissa
import ChessCore
import Foundation
import Model

/// Caissa's network, `Sources/Engine/CaissaNet/caissa.pnn`, loaded once, the first time an engine is made.
enum CaissaNetwork {
  static let loaded: Bool = {
    guard let path = Bundle.module.url(forResource: "caissa", withExtension: "pnn", subdirectory: "CaissaNet")?
      .path(percentEncoded: false)
    else { return false }
    return caissa_load_network(path)
  }()
}

/// Caissa (MIT, `Sources/Caissa`): the engine, with a neural network
/// evaluation. `onUpdate` returning true stops the search there.
public actor CaissaEngine: ChessEngine {
  /// How long a search runs when the caller only names a depth, and the longest any runs:
  /// the judge's confirmation of a suspected blunder.
  static let defaultMs: Double = 1000
  static let maxMs: Double = CONFIRM_MS

  private nonisolated(unsafe) let searcher: OpaquePointer

  /// The network ships in the bundle, so a failure here is a broken build.
  public init() {
    guard CaissaNetwork.loaded, let searcher = caissa_create(16) else { fatalError("Caissa's network didn't load") }
    self.searcher = searcher
  }

  deinit { caissa_destroy(searcher) }

  public func analyse(_ fen: String, _ limits: EngineLimits, onUpdate: @escaping @Sendable (EngineSnapshot) -> Bool) async -> EngineSnapshot {
    let moves = limits.searchmoves.flatMap { $0.isEmpty ? nil : $0 }
    let legal = legalMoves(fen)
    // Caissa answers a position with one legal move at once, scored 0: search the position after it.
    if legal.count == 1, let only = legal.first, moves.map({ $0.contains(only.uci) }) ?? true {
      return await forced(fen, only, limits, onUpdate: onUpdate)
    }
    let choices = moves?.count ?? legal.count
    guard choices > 0 else { return EngineSnapshot(lines: [], depth: 0, nodes: 0, thinking: false, fen: fen) }
    let multiPv = max(1, min(limits.multiPv ?? 3, choices))
    let ms = max(50, min(limits.movetime ?? Self.defaultMs, Self.maxMs))
    let progress = Progress(fen: fen, onUpdate: onUpdate)
    let context = Unmanaged.passUnretained(progress).toOpaque()
    var out = [CChar](repeating: 0, count: 1 << 16)
    var nodes: UInt64 = 0
    let depth = withExtendedLifetime(progress) {
      caissa_search(
        searcher, fen, UInt32(limits.depth ?? 0), UInt32(ms), UInt32(multiPv), moves?.joined(separator: " "),
        { context, depth, text in
          let progress = Unmanaged<Progress>.fromOpaque(context!).takeUnretainedValue()
          let lines = caissaLines(text.map { String(cString: $0) } ?? "", Int(depth), progress.fen)
          let snapshot = EngineSnapshot(lines: lines, depth: Int(depth), nodes: 0, thinking: true, fen: progress.fen)
          return progress.onUpdate(snapshot) || Task.isCancelled
        }, context, &out, UInt32(out.count), &nodes)
    }
    let text = out.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    return EngineSnapshot(lines: caissaLines(text, Int(depth), fen), depth: Int(depth), nodes: Int(nodes), thinking: false, fen: fen)
  }

  /// A position with one legal move: that move, then the search of the position after it.
  private func forced(
    _ fen: String, _ only: LegalMove, _ limits: EngineLimits, onUpdate: @escaping @Sendable (EngineSnapshot) -> Bool
  ) async -> EngineSnapshot {
    let status = positionStatus(only.after)
    if status.gameOver {
      let mate: Double? = status.checkmate ? (fenTurn(fen) == .w ? 1 : -1) : nil
      let line = EngineLine(multipv: 1, depth: 1, cp: mate == nil ? 0 : nil, mate: mate, pv: [only.uci])
      return EngineSnapshot(lines: [line], depth: 1, nodes: 0, thinking: false, fen: fen)
    }
    let mover: Double = fenTurn(fen) == .w ? 1 : -1
    @Sendable func lift(_ snap: EngineSnapshot) -> EngineSnapshot {
      let lines = snap.lines.prefix(1).map { line in
        // A mate for the side that moved is one move further off; a mate against it is as far.
        let mate = line.mate.map { $0 * mover > 0 ? $0 + mover : $0 }
        return EngineLine(multipv: 1, depth: line.depth + 1, cp: line.cp, mate: mate, pv: [only.uci] + line.pv)
      }
      return EngineSnapshot(lines: lines, depth: snap.depth + 1, nodes: snap.nodes, thinking: snap.thinking, fen: fen)
    }
    var after = limits
    after.searchmoves = nil
    after.multiPv = 1
    if let depth = limits.depth { after.depth = max(1, depth - 1) }
    return lift(await analyse(only.after, after) { onUpdate(lift($0)) })
  }

  private final class Progress: @unchecked Sendable {
    let fen: String
    let onUpdate: @Sendable (EngineSnapshot) -> Bool
    init(fen: String, onUpdate: @escaping @Sendable (EngineSnapshot) -> Bool) {
      self.fen = fen
      self.onUpdate = onUpdate
    }
  }
}

/// The bridge's lines ("<cp> <mate> <moves...>", the side to move's) in White's frame, as the app reads engines.
func caissaLines(_ text: String, _ depth: Int, _ fen: String) -> [EngineLine] {
  let sign: Double = fenTurn(fen) == .b ? -1 : 1
  return text.split(separator: "\n").compactMap { row -> [Substring]? in
    let parts = row.split(separator: " ")
    return parts.count >= 3 ? parts : nil
  }.enumerated().map { i, parts in
    let cp = Double(parts[0]) ?? 0, mate = Double(parts[1]) ?? 0
    return EngineLine(
      multipv: i + 1, depth: depth, cp: mate == 0 ? sign * max(-2000, min(2000, cp)) : nil,
      mate: mate == 0 ? nil : sign * mate, pv: parts.dropFirst(2).map(String.init))
  }
}
