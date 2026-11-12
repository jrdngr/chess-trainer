import Foundation
import Model
import Shared
import Testing

/// The milestone functions in Golden/cases/functions/home.json.
@Test func milestonesOnHome() throws {
  let tree = openingTree(bookIndex)

  func stats(_ days: [JSON], rating: Double = 0, rated: Int? = nil) -> NodeStats {
    var s = NodeStats()
    s.rating = rating
    s.rated = rated ?? (days.contains { $0[2] != .null } ? 10 : 0)
    for d in days {
      let rounds = d[1].int
      s.days[d[0].string] = DayTally(answered: rounds * 5, correct: rounds * 4, rounds: rounds, rating: d[2].numberOrNil)
    }
    return s
  }

  /// A profile's record in short: global days, each opening's rated days and rating now, Survival best, rounds by mode.
  func profile(_ p: JSON) -> (ScoreState, SurvivalRecord) {
    var score = ScoreState()
    score.global = stats(p["days"].array, rating: 0, rated: 0)
    for (mode, n) in p["rounds"].object { score.global.byMode[ActivityMode(rawValue: mode)!]?.rounds = n.int }
    for (id, entry) in p["openings"].object { score.nodes[id] = stats(entry[0].array, rating: entry[1].number) }
    var survival = SurvivalRecord()
    survival.global.best = p["best"].int
    return (score, survival)
  }

  func short(_ m: Milestone) -> String {
    "\(m.id) \(m.label) \(JS.string(m.value))/\(JS.string(m.target))\(m.color.map { " \($0)" } ?? "")"
  }

  try check("home", [
    "milestones.longestStreak": { longestStreak(stats($0[0].array, rating: 0, rated: 0)).json },
    "milestones.peakRating": { peakRating(stats($0[0].array, rating: $0[1].number)).json },
    "milestones.milestones": { a in
      let (score, survival) = profile(a[0])
      return milestones(score, survival, tree).map(short).json
    },
    "milestones.nextUp": { a in
      let (score, survival) = profile(a[0])
      let list = milestones(score, survival, tree)
      return obj([
        "earned": list.filter(earned).map(\.id).json,
        "next": nextUp(list.filter { $0.kind != .streak }, a[1].int).map { "\($0.id) \(JS.toFixed(progress($0), 3))" }.json,
      ])
    },
  ], only: ["milestones.longestStreak", "milestones.peakRating", "milestones.milestones", "milestones.nextUp"])
}
