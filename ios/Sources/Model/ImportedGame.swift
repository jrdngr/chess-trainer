import ChessCore

/// A game fetched from Lichess or Chess.com. Read once to seed the Playbook, never saved.
public struct ImportedGame: Equatable, Sendable {
  public var id: String
  public var site: GameSite
  public var white: String
  public var black: String
  public var result: String
  /// The colour the importing user played, when known.
  public var userColor: Color?
  public var date: String?
  public var moves: [String]
  public var url: String?

  public init(
    id: String, site: GameSite, white: String, black: String, result: String, userColor: Color?,
    date: String? = nil, moves: [String], url: String? = nil
  ) {
    self.id = id
    self.site = site
    self.white = white
    self.black = black
    self.result = result
    self.userColor = userColor
    self.date = date
    self.moves = moves
    self.url = url
  }
}
