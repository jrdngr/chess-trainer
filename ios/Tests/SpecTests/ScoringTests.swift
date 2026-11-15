import Foundation
import Model
import Testing

/// Golden/cases/functions/scoring.json
@Test func scoring() throws {
  let tree = openingTree(bookIndex)
  let at = 1_790_845_200_000.0

  /// Each answer counted in turn; what every opening holds after.
  func run(_ answers: [JSON]) -> JSON {
    var state = ScoreState()
    for (i, answer) in answers.enumerated() {
      let result = MoveResult(
        mode: .run, line: line(answer["line"].string), color: .w, correct: answer["correct"].bool,
        rated: true, at: at + Double(i) * 1000)
      state = applyResult(state, tree, result)
    }
    return state.nodes.mapValues { obj(["answered": $0.answered, "correct": $0.correct]) }.json
  }

  try check("scoring", [
    "scoring.creditedNodes": { creditedNodes(tree, line($0[0].string)).json },
    "scoring.applyResult (a run)": { run($0[0].array) },
  ])
}

/// Noon on a local day, as the cases build their "now".
private func noon(_ key: String) -> Double {
  let p = key.split(separator: "-").map { Int($0)! }
  let date = Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!
  return date.timeIntervalSince1970 * 1000
}

private func stats(_ days: [JSON]) -> NodeStats {
  var s = NodeStats()
  for d in days {
    let rounds = d[1].int
    s.days[d[0].string] = DayTally(answered: rounds * 5, correct: rounds * 4, rounds: rounds)
  }
  return s
}

/// The scoring functions in Golden/cases/functions/home.json and play.json.
@Test func scoringOnHome() throws {
  try check("home", [
    "scoring.streak": { streak(stats($0[0].array), noon($0[1].string)).json },
  ], only: ["scoring.streak"])

  try check("play", [
    "srs.runNeed": { a in runNeed(a[0].decoded(Card.self), a[1].int).json },
  ], only: ["srs.runNeed"])
}

/// Just after midnight following the 23-hour day daylight saving starts on,
/// the streak still counts that day.
@Test func streakAcrossSpringForward() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
  let days: [JSON] = ["2026-03-07", "2026-03-08", "2026-03-09"].map { .array([.string($0), .number(1), .null]) }
  let justAfterMidnight = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 0, minute: 30)))
  #expect(streak(stats(days), justAfterMidnight.timeIntervalSince1970 * 1000, calendar: calendar) == 3)
}
