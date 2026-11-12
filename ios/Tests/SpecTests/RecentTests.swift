import Foundation
import Model
import Testing

private func game(_ picked: String, _ color: ColorChoice = .w, at: Double) -> GameRecord {
  GameRecord(
    id: "g\(at)", mode: .run, at: at, color: .w, picked: Selection(color: color, opening: picked),
    opening: picked, moves: ["e4"], result: "*", termination: "blunder")
}

/// Recent reads single openings from the game history, newest first, once each.
@Test func recentReadsPicksFromGames() {
  let games = [
    game("sicilian", .b, at: 5),
    game(LEGACY_ANY_FAVORITE, at: 4),
    game(ANY_OPENING, at: 3),
    game("alapin", at: 2),
    game("sicilian", .w, at: 1),
  ]
  #expect(recentPicks(games) == [
    RecentPick(opening: "sicilian", color: .b, at: 5),
    RecentPick(opening: "alapin", color: .w, at: 2),
  ])
}

/// The quick tiles skip a favorite by its own id: the lines under it still show.
@Test func quickRecentSkipsOnlyTheFavoriteItself() {
  let recent = ["sicilian", "alapin", "e4", "caro", "london", "scotch"].enumerated().map {
    RecentPick(opening: $1, color: .w, at: Double(10 - $0))
  }
  let shown = quickRecent(recent, skipping: ["sicilian", "e4"])
  #expect(shown.map(\.opening) == ["alapin", "caro", "london", "scotch"])
}

/// The full list falls under Today, Yesterday, This week, then month names.
@Test func recentGroupsByDay() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
  let day = 86_400_000.0
  // 2026-11-04 12:00 UTC.
  let now = 1_793_793_600_000.0
  let recent = [
    RecentPick(opening: "a", color: .w, at: now - 1000),
    RecentPick(opening: "b", color: .w, at: now - day),
    RecentPick(opening: "c", color: .w, at: now - 3 * day),
    RecentPick(opening: "d", color: .w, at: now - 10 * day),
    RecentPick(opening: "e", color: .w, at: now - 12 * day),
    RecentPick(opening: "f", color: .w, at: now - 380 * day),
  ]
  let groups = recentGroups(recent, now: now, calendar: calendar)
  #expect(groups.map(\.label) == ["Today", "Yesterday", "This week", "October", "October 2025"])
  #expect(groups[3].picks.map(\.opening) == ["d", "e"])
}
