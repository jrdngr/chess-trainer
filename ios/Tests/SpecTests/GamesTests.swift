import ChessCore
import Foundation
import Model
import Testing

private func game(_ id: String, at: Double, moves: [String] = ["e4", "e5"]) -> GameRecord {
  GameRecord(
    id: id, mode: .freePlay, at: at, color: .w, picked: Selection(color: .w, opening: ""), opening: "",
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
  #expect(outcome(.blunder(played: "Qh5", best: nil, lost: 300, line: [], slip: nil), .w) == ["*", "blunder"])
}

/// A games export holds each game, newest first, with only the events logged in it, in the order they happened.
@Test func gamesExportCarriesEachGamesEvents() throws {
  let games = [game("b", at: 2), game("a", at: 1), game("quiet", at: 0)]
  let events = [
    AppEvent(kind: "move", game: "a", san: "e4", lost: 0),
    AppEvent(kind: "settings", text: "moments on"),
    AppEvent(kind: "move", game: "b", san: "d4", lost: 181),
    AppEvent(kind: "eval", game: "a", before: 30),
    AppEvent(kind: "move", game: "gone", san: "c4"),
  ]
  let export = GamesExport(exportedAt: "2026-11-23", games: games, events: events)
  #expect(export.games.map(\.game.id) == ["b", "a", "quiet"])
  #expect(export.games[0].events == [events[2]])
  #expect(export.games[1].events == [events[0], events[3]])
  #expect(export.games[2].events.isEmpty)
  let json = try JSONSerialization.jsonObject(with: exportJson(export)) as? [String: Any]
  #expect(json?["format"] as? String == "chess-playbook-games")
}

/// A save from before the history loads with none; the history survives a
/// save, and Recent reads from it.
@Test func gameHistoryLoadsAndSaves() throws {
  let old = try JSONDecoder().decode(AppState.self, from: Data(#"{"settings":{"onboarded":true},"recent":[]}"#.utf8))
  #expect(old.games.isEmpty)
  var state = AppState()
  state.recordGame(GameRecord(
    id: "r1", mode: .play, at: 7, color: .b, picked: Selection(color: .b, opening: "caro"),
    opening: "caro", moves: ["e4", "c6"], result: "*", termination: "ended"))
  #expect(state.recent == [RecentPick(opening: "caro", color: .b, at: 7)])
  let data = try JSONEncoder().encode(state)
  #expect(try JSONDecoder().decode(AppState.self, from: data) == state)
}
