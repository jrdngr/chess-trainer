import ChessCore
import Foundation
import Model
import Testing

private func game(_ id: String, at: Double, moves: [String] = ["e4", "e5"]) -> GameRecord {
  GameRecord(
    id: id, mode: .play, at: at, color: .w, picked: Selection(color: .w, opening: ""), opening: "",
    moves: moves, result: "1-0", termination: "checkmate")
}

/// The history keeps games newest first, drops empty ones, replaces a game
/// ended again, and holds at most GAMES_CAP.
@Test func gameHistoryKeepsNewestGames() {
  var games: [GameRecord] = []
  games = addGame(games, game("a", at: 1))
  games = addGame(games, game("empty", at: 2, moves: []))
  games = addGame(games, game("b", at: 3))
  games = addGame(games, game("a", at: 4, moves: ["e4", "e5", "Nf3"]))
  #expect(games.map(\.id) == ["a", "b"])
  #expect(games[0].moves.count == 3)

  for i in 0..<(GAMES_CAP + 5) { games = addGame(games, game("g\(i)", at: Double(10 + i))) }
  #expect(games.count == GAMES_CAP)
  #expect(games.first?.id == "g\(GAMES_CAP + 4)")
  #expect(!games.contains { $0.id == "a" || $0.id == "g4" })
}

/// Export's scopes: the newest game, the last 24 hours, the last 7 days, everything.
@Test func gameScopesByTime() {
  let day = 86_400_000.0
  let now = 100 * day
  let games = [game("1", at: now - 1000), game("2", at: now - 2 * day), game("3", at: now - 8 * day)]
  #expect(gamesIn(games, .last, now: now).map(\.id) == ["1"])
  #expect(gamesIn(games, .day, now: now).map(\.id) == ["1"])
  #expect(gamesIn(games, .week, now: now).map(\.id) == ["1", "2"])
  #expect(gamesIn(games, .all, now: now).map(\.id) == ["1", "2", "3"])
  #expect(gamesIn([], .last, now: now).isEmpty)
}

private func outcome(_ how: Ending, _ color: ChessCore.Color) -> [String] {
  let o = runOutcome(how, color: color)
  return [o.result, o.termination]
}

/// A run's ending as PGN: only a finished game has a result, from your side.
@Test func runOutcomesAsPgn() {
  #expect(outcome(.won, .b) == ["0-1", "checkmate"])
  #expect(outcome(.lost, .b) == ["1-0", "checkmate"])
  #expect(outcome(.draw, .w) == ["1/2-1/2", "draw"])
  #expect(outcome(.ended, .w) == ["*", "ended"])
  #expect(outcome(.blunder(played: "Qh5", best: nil, lost: 300, reply: nil, slip: nil), .w) == ["*", "blunder"])
}

/// A game as PGN: the tags with you on your side, the app's own tags, then numbered moves and the result.
@Test func gameAsPgn() {
  let tree = openingTree(bookIndex)
  // 2026-11-04 12:00:05 UTC.
  let record = GameRecord(
    id: "x", mode: .survival, at: 1_793_793_605_000, color: .b, picked: Selection(color: .b, opening: ANY_FAVORITE),
    opening: "e4 c5 d4", moves: ["e4", "c5", "d4", "cxd4"], opened: 3, result: "*", termination: "blunder")
  let pgn = gamePgn(record, tree)
  let opening = nodeById(tree, "e4 c5 d4").name
  #expect(pgn == """
    [Event "Chess Playbook Survival"]
    [Site "Chess Playbook"]
    [Date "2026.11.04"]
    [Round "-"]
    [White "Chess Playbook Survival"]
    [Black "You"]
    [Result "*"]
    [UTCTime "12:00:05"]
    [Termination "blunder"]
    [Mode "survival"]
    [Picked "Any Favorite"]
    [Opening "\(opening)"]
    [Opened "3"]

    1. e4 c5 2. d4 cxd4 *

    """)
  let mine = GameRecord(
    id: "y", mode: .play, at: 0, color: .w, picked: Selection(color: .w, opening: ANY_OPENING),
    opening: "", moves: ["e4"], result: "1-0", termination: "resignation")
  let lines = gamePgn(mine, tree).split(separator: "\n")
  #expect(lines.contains("[Picked \"Any Playbook\"]"))
  #expect(!lines.contains { $0.hasPrefix("[Opened") })
  #expect(gamesPgn([record, mine], tree) == gamePgn(record, tree) + "\n" + gamePgn(mine, tree))
}

/// A save from before the history loads with none; the history survives a
/// save, and Recent reads from it.
@Test func gameHistoryLoadsAndSaves() throws {
  let old = try JSONDecoder().decode(AppState.self, from: Data(#"{"settings":{"onboarded":true},"recent":[]}"#.utf8))
  #expect(old.games.isEmpty)
  var state = AppState()
  state.recordGame(GameRecord(
    id: "r1", mode: .autopilot, at: 7, color: .b, picked: Selection(color: .b, opening: "caro"),
    opening: "caro", moves: ["e4", "c6"], result: "*", termination: "ended"))
  #expect(state.recent == [RecentPick(opening: "caro", color: .b, at: 7)])
  let data = try JSONEncoder().encode(state)
  #expect(try JSONDecoder().decode(AppState.self, from: data) == state)
}

/// A game played on Any favorite is kept as picked on Any favorite, not on the
/// favorite it landed on; any other game keeps the opening it was played on.
@Test func pickedKeepsAnyFavorite() {
  let favorite = Selection(color: .w, opening: ANY_FAVORITE)
  let landed = Selection(color: .b, opening: "e4 c5")
  #expect(pickedFor(landed, saved: favorite) == favorite)
  #expect(pickedFor(landed, saved: Selection(color: .w, opening: "e4")) == landed)
}
