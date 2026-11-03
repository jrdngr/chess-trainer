import Foundation
import Shared

/// Series for the Stats page's charts that the plain day series do not cover:
/// the activity grid, and accuracy one day at a time.

/// Every day from the Monday `weeks - 1` weeks back through today, oldest
/// first, each with the rounds played. The grid draws it a week to a column,
/// so the last column stops at today.
public func activityGrid(_ stats: NodeStats, weeks: Int, _ now: Double = Env.now(), calendar: Calendar = .current) -> [DayPoint] {
  let today = calendar.startOfDay(for: Date(timeIntervalSince1970: now / 1000))
  let sinceMonday = (calendar.component(.weekday, from: today) + 5) % 7
  let count = (weeks - 1) * 7 + sinceMonday + 1
  return stride(from: count - 1, through: 0, by: -1).map { back in
    let day = calendar.date(byAdding: .day, value: -back, to: today) ?? today
    let at = day.timeIntervalSince1970 * 1000
    let key = dayKey(at, calendar)
    return DayPoint(at: at, key: key, value: Double(stats.days[key]?.rounds ?? 0))
  }
}

/// How dark a day's square is, 0 for none up to 4 for the busiest day shown.
public func heatLevel(_ rounds: Double, _ top: Double) -> Int {
  if rounds <= 0 || top <= 0 { return 0 }
  return min(4, max(1, Int((rounds / top * 4).rounded(.up))))
}

/// Each day's own share of right answers, over the last `days` days. Days
/// with nothing answered are left out.
public func dailyAccuracy(_ stats: NodeStats, _ days: Int, _ now: Double = Env.now(), calendar: Calendar = .current) -> [DayPoint] {
  let today = calendar.startOfDay(for: Date(timeIntervalSince1970: now / 1000))
  return stride(from: days - 1, through: 0, by: -1).compactMap { back in
    let day = calendar.date(byAdding: .day, value: -back, to: today) ?? today
    let at = day.timeIntervalSince1970 * 1000
    let key = dayKey(at, calendar)
    guard let tally = stats.days[key], tally.answered > 0 else { return nil }
    return DayPoint(at: at, key: key, value: Double(tally.correct) / Double(tally.answered))
  }
}
