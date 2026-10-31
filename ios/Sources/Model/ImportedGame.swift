import ChessCore

/// A game brought in from elsewhere, or played here in Play: `ImportedGame` in `model/types.ts`.
public struct ImportedGame: Equatable, Sendable, Codable {
  /// Where the game came from: an import, or one you played here in Play.
  public enum Source: String, Sendable, Codable {
    case lichess, chesscom, pgn, play
  }

  public var id: String
  public var source: Source
  public var white: String
  public var black: String
  public var result: String
  /// The colour the importing user played, when known.
  public var userColor: Color?
  public var timeControl: String?
  public var date: String?
  public var opening: String?
  public var moves: [String]
  public var url: String?

  public init(
    id: String, source: Source, white: String, black: String, result: String, userColor: Color?,
    timeControl: String? = nil, date: String? = nil, opening: String? = nil, moves: [String], url: String? = nil
  ) {
    self.id = id
    self.source = source
    self.white = white
    self.black = black
    self.result = result
    self.userColor = userColor
    self.timeControl = timeControl
    self.date = date
    self.opening = opening
    self.moves = moves
    self.url = url
  }
}
