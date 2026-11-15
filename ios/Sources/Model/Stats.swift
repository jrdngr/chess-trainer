import Foundation
import Shared

/// Stats: the numbers behind one opening, or the whole game, shaped for a
/// chart. Everything reads the per-day tallies the
/// record keeps and folds them into series; nothing is stored twice.

public struct DayPoint: Equatable, Sendable {
  /// Start of the day, local time.
  public var at: Double
  public var key: String
  public var value: Double
}

/// Midnight, local time, `back` days before `now`.
/// Steps back by calendar days, so a day that daylight saving makes 23 hours long is not skipped.
private func dayStart(_ now: Double, _ back: Int) -> Double {
  let calendar = Calendar.current
  let today = calendar.startOfDay(for: Date(timeIntervalSince1970: now / 1000))
  let day = calendar.date(byAdding: .day, value: -back, to: today) ?? today
  return day.timeIntervalSince1970 * 1000
}

/// Accuracy over the window, smoothed: each day is the share of the answers
/// over the seven days ending there that were right. Days with nothing to
/// average over are left out rather than drawn as zero.
public func rollingAccuracy(_ stats: NodeStats, _ days: Int, _ now: Double = Env.now(), _ window: Int = 7) -> [DayPoint] {
  var out: [DayPoint] = []
  for back in stride(from: days - 1, through: 0, by: -1) {
    var answered = 0
    var correct = 0
    for w in 0..<window {
      guard let day = stats.days[dayKey(dayStart(now, back + w))] else { continue }
      answered += day.answered
      correct += day.correct
    }
    if answered == 0 { continue }
    let at = dayStart(now, back)
    out.append(DayPoint(at: at, key: dayKey(at), value: Double(correct) / Double(answered)))
  }
  return out
}

/// Rounds in the last `days` days.
public func recentRounds(_ stats: NodeStats, _ days: Int, _ now: Double = Env.now()) -> Int {
  stride(from: days - 1, through: 0, by: -1).reduce(0) { $0 + (stats.days[dayKey(dayStart(now, $1))]?.rounds ?? 0) }
}

/// Ticks for an axis: a few round numbers that cover the range.
public func niceTicks(_ max: Double, _ count: Double = 3) -> [Double] {
  if max <= 0 { return [0] }
  let rough = max / count
  let magnitude = pow(10, floor(log10(rough)))
  let step = [1.0, 2, 5, 10].map { $0 * magnitude }.first { $0 >= rough } ?? magnitude * 10
  var out: [Double] = []
  var tick = 0.0
  while tick <= max + step * 0.999 {
    out.append(tick)
    tick += step
  }
  return out
}
