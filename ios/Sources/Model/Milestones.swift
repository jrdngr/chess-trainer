import Foundation
import Shared

/// Milestones: goals reached once and kept, `src/model/milestones.ts`. Every
/// one is read from what the app already records, so whatever was done
/// before they existed counts.

public enum MilestoneKind: String, Sendable, Codable { case streak, survival, tier, breadth, rounds }

public struct Milestone: Equatable, Sendable {
  public var id: String
  public var kind: MilestoneKind
  /// The badge's name: "7 days", "Mastered", "1k rounds".
  public var label: String
  public var target: Double
  /// How far along you are, in the target's units. Earned at `value >= target`.
  public var value: Double
  /// For a tier milestone, the tier's color.
  public var color: String?
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

/// The highest an opening's rating has ever stood: its end-of-day ratings and where it is now.
public func peakRating(_ stats: NodeStats) -> Double {
  if stats.rated == 0 { return 0 }
  var peak = stats.rating
  for day in stats.days.values { if let r = day.rating, r > peak { peak = r } }
  return peak
}

/// The second rung of the tree: a family such as the Sicilian, under its first move.
private func familyOf(_ tree: OpeningTree, _ id: String) -> String? {
  ancestorsOf(tree, id).first { $0.depth == 2 }?.id
}

private let FAMILIAR = TIERS.first { $0.name == "Familiar" }!.at
private let STREAKS = [3, 7, 30]
private let SURVIVALS = [10, 20, 30]
private let BREADTHS = [3, 5, 10]
private let ROUNDS = [100, 500, 1000, 5000]

private func roundsLabel(_ n: Int) -> String { n >= 1000 ? "\(n / 1000)k rounds" : "\(n) rounds" }

/// Every milestone with how far along it is. Breadth counts families (a
/// Najdorf and the Sicilian above it are one), so one good line cannot earn
/// it three times over.
public func milestones(_ score: ScoreState, _ survival: SurvivalRecord, _ tree: OpeningTree) -> [Milestone] {
  let streak = Double(longestStreak(score.global))
  let best = Double(survival.global.best)
  let rounds = Double(ACTIVITY_MODES.reduce(0) { $0 + (score.global.byMode[$1]?.rounds ?? 0) })

  var peak = 0.0
  var familiar = Set<String>()
  for (id, stats) in score.nodes where tree.byId.has(id) {
    let top = peakRating(stats)
    peak = max(peak, top)
    if top >= FAMILIAR, let family = familyOf(tree, id) { familiar.insert(family) }
  }

  return STREAKS.map { Milestone(id: "streak-\($0)", kind: .streak, label: "\($0) days", target: Double($0), value: streak) }
    + SURVIVALS.map { Milestone(id: "survival-\($0)", kind: .survival, label: "\($0) moves", target: Double($0), value: best) }
    + TIERS.filter { $0.at >= FAMILIAR }.map {
      Milestone(id: "tier-\($0.name.lowercased())", kind: .tier, label: $0.name, target: $0.at, value: peak, color: $0.color)
    }
    + BREADTHS.map { Milestone(id: "breadth-\($0)", kind: .breadth, label: "\($0) Familiar", target: Double($0), value: Double(familiar.count)) }
    + ROUNDS.map { Milestone(id: "rounds-\($0)", kind: .rounds, label: roundsLabel($0), target: Double($0), value: rounds) }
}

public func earned(_ milestone: Milestone) -> Bool { milestone.value >= milestone.target }

/// How close an unearned milestone is, 0...1.
public func progress(_ milestone: Milestone) -> Double { max(0, min(1, milestone.value / milestone.target)) }

/// The unearned milestones closest to done, first. Ties keep the list's own order.
public func nextUp(_ list: [Milestone], _ count: Int) -> [Milestone] {
  Array(list.filter { !earned($0) }.jsSorted { progress($1) - progress($0) }.prefix(count))
}
