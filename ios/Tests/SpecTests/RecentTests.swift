import Foundation
import Model
import Testing

private func pick(_ id: String, _ color: ColorChoice = .w) -> Selection { Selection(color: color, opening: id) }

/// Recent keeps single openings only, newest first, once each, and at most RECENT_CAP of them.
@Test func recentKeepsPicksNewestFirst() {
  var recent: [RecentPick] = []
  recent = notePick(recent, pick("sicilian", .b), at: 1)
  recent = notePick(recent, pick("alapin"), at: 2)
  recent = notePick(recent, pick(ANY_OPENING), at: 3)
  recent = notePick(recent, pick(ANY_FAVORITE), at: 4)
  recent = notePick(recent, pick("sicilian", .b), at: 5)
  #expect(recent.map(\.opening) == ["sicilian", "alapin"])
  #expect(recent[0].at == 5)
  #expect(recent[0].color == .b)

  for i in 0..<(RECENT_CAP + 5) { recent = notePick(recent, pick("o\(i)"), at: Double(10 + i)) }
  #expect(recent.count == RECENT_CAP)
  #expect(recent.first?.opening == "o\(RECENT_CAP + 4)")
  #expect(!recent.contains { $0.opening == "sicilian" || $0.opening == "o0" })
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

/// A save from before Recent loads with none, and Recent survives a save.
@Test func recentLoadsAndSaves() throws {
  let old = try JSONDecoder().decode(AppState.self, from: Data(#"{"settings":{"onboarded":true}}"#.utf8))
  #expect(old.recent.isEmpty)
  var state = AppState()
  state.settings.selection = Selection(color: .b, opening: "caro")
  state.notePlayed(at: 7)
  #expect(state.recent == [RecentPick(opening: "caro", color: .b, at: 7)])
  let data = try JSONEncoder().encode(state)
  #expect(try JSONDecoder().decode(AppState.self, from: data) == state)
}
