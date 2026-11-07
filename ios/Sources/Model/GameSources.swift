import ChessCore
import Foundation

/// The two sites games are fetched from.
public enum GameSite: String, Sendable, CaseIterable {
  case lichess, chesscom

  public var name: String { self == .lichess ? "Lichess" : "Chess.com" }
}

/// The side `username` played, matched exactly (ignoring case).
func colorOf(white: String, black: String, _ username: String) -> Color? {
  let u = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  if white.lowercased() == u { return .w }
  if black.lowercased() == u { return .b }
  return nil
}

/// Turn a site's PGN into games, tagging which side the user had.
/// A game set up from another position is left out: a game's moves are read from the start.
public func gamesFromPgn(_ pgn: String, _ username: String, _ site: GameSite) -> [ImportedGame] {
  var out: [ImportedGame] = []
  for (i, game) in parsePgn(pgn).enumerated() {
    let h = game.headers
    if let fen = h["FEN"], positionKey(fen) != positionKey(START_FEN) { continue }
    let moves = pgnMainline(game)
    if moves.isEmpty { continue }
    let white = h["White"] ?? "White"
    let black = h["Black"] ?? "Black"
    out.append(ImportedGame(
      id: "\(site.rawValue)_\(h["Site"] ?? "")_\(i)", site: site, white: white, black: black,
      result: game.result, userColor: colorOf(white: white, black: black, username),
      date: h["UTCDate"] ?? h["Date"], moves: moves,
      url: h["Site"].flatMap { $0.hasPrefix("http") ? $0 : nil }))
  }
  return out
}
