import ChessCore
import Foundation
import Model
import Testing

/// Import: reading PGN, the two sites' responses, and the openings your games
/// seed the Playbook with.

@Test func pgnHeadersAndMainline() throws {
  let pgn = "[Event \"Test\"]\n[White \"A\"]\n[Black \"B\"]\n[Result \"1-0\"]\n\n1. e4 e5 2. Nf3 Nc6 3. Bb5 1-0"
  let game = try #require(parsePgn(pgn).first)
  #expect(game.headers["White"] == "A")
  #expect(game.result == "1-0")
  #expect(pgnMainline(game) == ["e4", "e5", "Nf3", "Nc6", "Bb5"])
}

@Test func pgnVariationsAreSiblings() throws {
  let game = try #require(parsePgn("1. e4 c5 (1... e5 2. Nf3) 2. Nf3 d6").first)
  #expect(game.moves[0].san == "e4")
  #expect(game.moves[0].children.nodes.map(\.san) == ["c5", "e5"])
  #expect(pgnMainline(game) == ["e4", "c5", "Nf3", "d6"])
  let nested = try #require(parsePgn("1. d4 Nf6 2. c4 e6 (2... g6 3. Nc3 d5 (3... Bg7)) 3. Nc3 Bb4").first)
  #expect(pgnMainline(nested) == ["d4", "Nf6", "c4", "e6", "Nc3", "Bb4"])
}

@Test func pgnCommentsNagsAndIllegalMoves() throws {
  let game = try #require(parsePgn("1. e4 {best by test} e5 $1 2. Nf3!? Nc6?!").first)
  #expect(game.moves[0].comment == "best by test")
  #expect(pgnMainline(game) == ["e4", "e5", "Nf3", "Nc6"])
  #expect(pgnMainline(try #require(parsePgn("1. e4 e5 2. Qxf7 Nc6").first)) == ["e4", "e5"])
}

private let twoGames = """
  [Event "One"]
  [Site "https://lichess.org/abc"]
  [White "Tester"]
  [Black "kn1ghtrider"]
  [Result "1-0"]
  [UTCDate "2026.10.01"]

  1. e4 e5 1-0

  [Event "Two"]
  [White "someone"]
  [Black "tester_alt"]
  [Result "0-1"]

  1. d4 d5 0-1
  """

@Test func pgnMultipleGames() {
  let games = parsePgn(twoGames)
  #expect(games.count == 2)
  #expect(games[1].headers["Event"] == "Two")
  #expect(pgnMainline(games[1]) == ["d4", "d5"])
}

@Test func gamesFromPgnTagsYourSide() {
  let games = gamesFromPgn(twoGames, "tester", .lichess)
  #expect(games.map(\.id) == ["lichess_https://lichess.org/abc_0", "lichess__1"])
  #expect(games.map(\.userColor) == [.w, nil])
  #expect(games[0].url == "https://lichess.org/abc")
  #expect(games[0].date == "2026.10.01")
  #expect(games[1].url == nil)
}

/// Saved responses stand in for the network.
private func stub(_ routes: [String: (Int, String)]) -> HTTPGet {
  { url, _ in
    let (status, body) = routes[url.absoluteString] ?? (404, "")
    return (status, Data(body.utf8))
  }
}

@Test func lichessFetch() async {
  let url = "https://lichess.org/api/games/user/tester?max=120&rated=true&perfType=blitz,rapid,classical&clocks=false&evals=false&opening=true"
  guard case .ok(let games) = await fetchGames(.lichess, "tester", max: 120, get: stub([url: (200, twoGames)])) else {
    Issue.record("expected games")
    return
  }
  #expect(games.count == 2 && games[0].site == .lichess)
  guard case .failed(.notFound, let message) = await fetchGames(.lichess, "nobody", get: stub([:])) else {
    Issue.record("expected not found")
    return
  }
  #expect(message == "No Lichess account called \"nobody\".")
  guard case .failed(.rateLimited, _) = await fetchGames(.lichess, "tester", max: 120, get: stub([url: (429, "")])) else {
    Issue.record("expected rate limited")
    return
  }
}

@Test func chesscomFetchReadsNewestMonthsFirst() async throws {
  func month(_ pgns: [(String, String?)]) throws -> String {
    let games = pgns.map { ["pgn": $0.0, "url": "https://www.chess.com/game/live/1", "rules": $0.1 ?? "chess"] }
    return String(decoding: try JSONSerialization.data(withJSONObject: ["games": games]), as: UTF8.self)
  }
  let base = "https://api.chess.com/pub/player/tester/games"
  let one = "[White \"Tester\"]\n[Black \"x\"]\n\n1. e4 e5 *"
  let two = "[White \"x\"]\n[Black \"Tester\"]\n\n1. d4 d5 *"
  let routes: [String: (Int, String)] = [
    "\(base)/archives": (200, "{\"archives\":[\"\(base)/2026/09\",\"\(base)/2026/10\"]}"),
    "\(base)/2026/10": (200, try month([(two, nil), (one, "chess960")])),
    "\(base)/2026/09": (200, try month([(one, nil)])),
  ]
  guard case .ok(let games) = await fetchGames(.chesscom, "Tester", max: 1, get: stub(routes)) else {
    Issue.record("expected games")
    return
  }
  // The newest month's standard game, cut to `max`; the variant is left out.
  #expect(games.map(\.moves) == [["d4", "d5"]])
  #expect(games[0].userColor == .b && games[0].url == "https://www.chess.com/game/live/1")
  guard case .ok(let all) = await fetchGames(.chesscom, "tester", max: 10, get: stub(routes)) else { return }
  #expect(all.map(\.moves) == [["d4", "d5"], ["e4", "e5"]])
}

