import ChessCore

/// What an engine search reports: `src/engine/types.ts`.
public struct EngineLine: Equatable, Sendable, Codable {
  public var multipv: Int
  public var depth: Int
  /// Centipawns from White's side; nil when a mate is found.
  public var cp: Double?
  /// Moves to mate from White's side, positive when White mates.
  public var mate: Double?
  /// The principal variation as UCI moves.
  public var pv: [String]
  public init(multipv: Int, depth: Int, cp: Double?, mate: Double?, pv: [String]) {
    self.multipv = multipv
    self.depth = depth
    self.cp = cp
    self.mate = mate
    self.pv = pv
  }
}

/// A line's score from one side, a mate folded to ±100000: `hintEngine.lineScore`.
public func lineScore(_ line: EngineLine?, _ color: Color) -> Double? {
  guard let line else { return nil }
  let white = line.mate.map { ($0 > 0 ? 1 : $0 < 0 ? -1 : 0) * 100_000 } ?? line.cp ?? 0
  return color == .w ? white : -white
}

/// Cash out: how far ahead before trades are suggested, and how much worse than the best a trade may be.
public let CASH_OUT_FROM: Double = 200
public let CASH_OUT_SLACK: Double = 30

public struct Trade: Equatable, Sendable, Codable {
  public var from: String
  public var to: String
  public var san: String
}

/// The trade worth offering among the engine's lines, if any: `engine/cashOut.ts`.
public func pickTrade(_ fen: String, _ lines: [EngineLine], _ me: Color) -> Trade? {
  guard let best = lineScore(lines.first, me), best >= CASH_OUT_FROM else { return nil }
  let moves = legalMoves(fen)
  for line in lines {
    guard let score = lineScore(line, me), best - score <= CASH_OUT_SLACK, score >= CASH_OUT_FROM else { continue }
    guard let move = moves.first(where: { $0.uci == line.pv.first }), let captured = move.captured, captured != .p, move.piece != .k else {
      continue
    }
    // Taken straight back, by a piece of about the same worth.
    guard line.pv.count > 1, String(line.pv[1].dropFirst(2).prefix(2)) == move.to else { continue }
    if abs(PIECE_VALUES[captured]! - PIECE_VALUES[move.piece]!) > 1 { continue }
    return Trade(from: move.from, to: move.to, san: move.san)
  }
  return nil
}
