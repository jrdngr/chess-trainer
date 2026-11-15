import Foundation
import Shared

/// Milestones: goals reached once and kept. Every
/// one is read from what the app already records, so whatever was done
/// before they existed counts.

public enum MilestoneKind: String, Sendable, Codable { case streak, run, rounds }

public struct Milestone: Equatable, Sendable {
  public var id: String
  public var kind: MilestoneKind
  /// The badge's name: "7 days", "1k rounds".
  public var label: String
  public var target: Double
  /// How far along you are, in the target's units. Earned at `value >= target`.
  public var value: Double
}

/// Days in a row with a round, the longest run of them ever.
public func longestStreak(_ stats: NodeStats) -> Int {
  let day = 86_400_000.0
  let played = stats.days.filter { $0.value.rounds > 0 }.map(\.key).sorted()
  var best = 0
  var run = 0
  var previous: String?
  for key in played {
    // A day's noon, so a daylight-saving shift cannot skip or repeat a day.
    let p = key.split(separator: "-").map { Int($0)! }
    let noon = Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!
    let yesterday = dayKey(noon.timeIntervalSince1970 * 1000 - day)
    run = previous == yesterday ? run + 1 : 1
    best = max(best, run)
    previous = key
  }
  return best
}

private let STREAKS = [3, 7, 30]
private let RUN_MILESTONES = [10, 20, 30]
private let ROUNDS = [100, 500, 1000, 5000]

private func roundsLabel(_ n: Int) -> String { n >= 1000 ? "\(n / 1000)k rounds" : "\(n) rounds" }

/// Every milestone with how far along it is.
public func milestones(_ score: ScoreState, _ run: RunRecord) -> [Milestone] {
  let streak = Double(longestStreak(score.global))
  let best = Double(run.global.best)
  let rounds = Double(ACTIVITY_MODES.reduce(0) { $0 + (score.global.byMode[$1]?.rounds ?? 0) })

  return STREAKS.map { Milestone(id: "streak-\($0)", kind: .streak, label: "\($0) days", target: Double($0), value: streak) }
    + RUN_MILESTONES.map { Milestone(id: "run-\($0)", kind: .run, label: "\($0) moves", target: Double($0), value: best) }
    + ROUNDS.map { Milestone(id: "rounds-\($0)", kind: .rounds, label: roundsLabel($0), target: Double($0), value: rounds) }
}

public func earned(_ milestone: Milestone) -> Bool { milestone.value >= milestone.target }

/// How close an unearned milestone is, 0...1.
public func progress(_ milestone: Milestone) -> Double { max(0, min(1, milestone.value / milestone.target)) }

/// The unearned milestones closest to done, first. Ties keep the list's own order.
public func nextUp(_ list: [Milestone], _ count: Int) -> [Milestone] {
  Array(list.filter { !earned($0) }.jsSorted { progress($1) - progress($0) }.prefix(count))
}
