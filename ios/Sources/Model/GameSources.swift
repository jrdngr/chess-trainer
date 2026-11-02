import ChessCore
import Foundation

/// Games from a PGN, tagged with the side you had.

/// The two sites games are fetched from.
public enum GameSite: String, Sendable, CaseIterable {
  case lichess, chesscom

  public var name: String { self == .lichess ? "Lichess" : "Chess.com" }
  public var source: ImportedGame.Source { self == .lichess ? .lichess : .chesscom }
}

/// The side `username` played, matched exactly (ignoring case).
func colorOf(white: String, black: String, _ username: String) -> Color? {
  let u = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  if white.lowercased() == u { return .w }
  if black.lowercased() == u { return .b }
  return nil
}

/// Turn a PGN blob into importable games, tagging which side the user had.
/// A game set up from another position is left out: an imported game's moves are read from the start.
public func gamesFromPgn(_ pgn: String, _ username: String, _ source: ImportedGame.Source = .pgn) -> [ImportedGame] {
  var out: [ImportedGame] = []
  for (i, game) in parsePgn(pgn).enumerated() {
    let h = game.headers
    if let fen = h["FEN"], positionKey(fen) != positionKey(START_FEN) { continue }
    let moves = pgnMainline(game)
    if moves.isEmpty { continue }
    let white = h["White"] ?? "White"
    let black = h["Black"] ?? "Black"
    out.append(ImportedGame(
      id: "\(source.rawValue)_\(h["Site"] ?? "")_\(i)", source: source, white: white, black: black,
      result: game.result, userColor: colorOf(white: white, black: black, username),
      timeControl: h["TimeControl"], date: h["UTCDate"] ?? h["Date"], opening: h["Opening"], moves: moves,
      url: h["Site"].flatMap { $0.hasPrefix("http") ? $0 : nil }))
  }
  return out
}

/// A pasted PGN's games, with the side guessed from a name that only appears in a player's.
public func pastedGames(_ pgn: String, _ username: String) -> [ImportedGame] {
  let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
  let name = trimmed.isEmpty ? "you" : trimmed
  return gamesFromPgn(pgn, name).map { game in
    guard game.userColor == nil else { return game }
    var tagged = game
    let u = name.lowercased()
    tagged.userColor = game.white.lowercased().contains(u) ? .w : game.black.lowercased().contains(u) ? .b : nil
    return tagged
  }
}
