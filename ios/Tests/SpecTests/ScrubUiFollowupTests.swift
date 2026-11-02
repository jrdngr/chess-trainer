import Foundation
import Model
import Testing

/// Chess.com's PGN gives "Chess.com" as the site for every game, so each
/// game is told apart by the URL the archive lists for it.
@Test func chesscomGamesTakeTheirIdFromTheirUrl() async throws {
  let base = "https://api.chess.com/pub/player/tester/games"
  let pgn = "[Site \"Chess.com\"]\n[White \"Tester\"]\n[Black \"x\"]\n\n1. e4 e5 *"
  let games: [[String: String]] = [
    ["pgn": pgn, "url": "https://www.chess.com/game/live/1", "rules": "chess"],
    ["pgn": pgn, "url": "https://www.chess.com/game/live/2", "rules": "chess"],
    ["pgn": pgn, "rules": "chess"],
  ]
  let month = String(decoding: try JSONSerialization.data(withJSONObject: ["games": games]), as: UTF8.self)
  let routes: [String: String] = [
    "\(base)/archives": "{\"archives\":[\"\(base)/2026/10\"]}",
    "\(base)/2026/10": month,
  ]
  let get: HTTPGet = { url, _ in
    guard let body = routes[url.absoluteString] else { return (404, Data()) }
    return (200, Data(body.utf8))
  }
  guard case .ok(let fetched) = await fetchGames(.chesscom, "tester", max: 10, get: get) else {
    Issue.record("expected games")
    return
  }
  #expect(fetched.map(\.id) == [
    "chesscom_https://www.chess.com/game/live/1",
    "chesscom_https://www.chess.com/game/live/2",
    "chesscom_Chess.com_0",
  ])
}
