import Foundation
import Model
import Testing

/// The Stats page's grid and daily accuracy series.
private func noon(_ key: String) -> Double {
  let p = key.split(separator: "-").map { Int($0)! }
  let date = Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!
  return date.timeIntervalSince1970 * 1000
}

private func history() -> NodeStats {
  var s = NodeStats()
  s.days["2026-10-26"] = DayTally(answered: 4, correct: 3, rounds: 2)
  s.days["2026-10-29"] = DayTally(answered: 0, correct: 0, rounds: 1)
  s.days["2026-11-01"] = DayTally(answered: 5, correct: 5, rounds: 6)
  return s
}

@Test func activityGridRunsFromMondayToToday() {
  // 2026-11-04 is a Wednesday: two full weeks back plus Monday to Wednesday.
  let grid = activityGrid(history(), weeks: 3, noon("2026-11-04"))
  #expect(grid.count == 17)
  #expect(grid.first?.key == "2026-10-19")
  #expect(grid.last?.key == "2026-11-04")
  #expect(grid.first { $0.key == "2026-11-01" }?.value == 6)
}

@Test func heatLevelScalesToTheBusiestDay() {
  #expect(heatLevel(0, 6) == 0)
  #expect(heatLevel(1, 6) == 1)
  #expect(heatLevel(3, 6) == 2)
  #expect(heatLevel(6, 6) == 4)
  #expect(heatLevel(2, 0) == 0)
}

@Test func dailyAccuracySkipsDaysWithNothingAnswered() {
  let points = dailyAccuracy(history(), 10, noon("2026-11-04"))
  #expect(points.map(\.key) == ["2026-10-26", "2026-11-01"])
  #expect(points.map(\.value) == [0.75, 1])
}
