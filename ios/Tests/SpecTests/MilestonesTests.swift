import Foundation
import Model
import Shared
import Testing

/// The milestone functions in Golden/cases/functions/home.json.
@Test func milestonesOnHome() throws {
  func stats(_ days: [JSON]) -> NodeStats {
    var s = NodeStats()
    for d in days {
      let rounds = d[1].int
      s.days[d[0].string] = DayTally(answered: rounds * 5, correct: rounds * 4, rounds: rounds)
    }
    return s
  }

  /// A profile's record in short: global days, Run best, rounds by mode.
  func profile(_ p: JSON) -> (ScoreState, RunRecord) {
    var score = ScoreState()
    score.global = stats(p["days"].array)
    for (mode, n) in p["rounds"].object { score.global.byMode[ActivityMode(rawValue: mode)!]?.rounds = n.int }
    var run = RunRecord()
    run.global.best = p["best"].int
    return (score, run)
  }

  func short(_ m: Milestone) -> String {
    "\(m.id) \(m.label) \(JS.string(m.value))/\(JS.string(m.target))"
  }

  try check("home", [
    "milestones.longestStreak": { longestStreak(stats($0[0].array)).json },
    "milestones.milestones": { a in
      let (score, run) = profile(a[0])
      return milestones(score, run).map(short).json
    },
    "milestones.nextUp": { a in
      let (score, run) = profile(a[0])
      let list = milestones(score, run)
      return obj([
        "earned": list.filter(earned).map(\.id).json,
        "next": nextUp(list.filter { $0.kind != .streak }, a[1].int).map { "\($0.id) \(JS.toFixed(progress($0), 3))" }.json,
      ])
    },
  ], only: ["milestones.longestStreak", "milestones.milestones", "milestones.nextUp"])
}
