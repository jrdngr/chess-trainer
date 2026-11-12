import ChessCore

/// What an engine search reports.
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

public struct Trade: Equatable, Sendable, Codable {
  public var from: String
  public var to: String
  public var san: String
}

