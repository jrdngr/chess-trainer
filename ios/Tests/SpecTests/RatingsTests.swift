import Foundation
import Model
import Testing

extension RatingMove: JSONable {
  var json: JSON {
    obj(["id": id, "ext": ext ? true : nil, "before": before, "after": after, "promotion": promotion])
  }
}

/// spec/cases/functions/ratings.json
@Test func ratings() throws {
  let tree = openingTree(bookIndex)
  let at = 1_790_845_200_000.0

  func run(_ answers: [JSON], _ ended: String?) -> JSON {
    var state = EMPTY_SCORE
    var earlier: [MoveResult] = []
    var steps: [JSON] = []
    for (i, answer) in answers.enumerated() {
      let kind = answer["kind"].stringOrNil
      let result = MoveResult(
        mode: .survival, line: line(answer["line"].string), color: .w, correct: answer["correct"].bool,
        rated: kind != "mistake", ext: kind == "ext" || kind == "mistake", at: at + Double(i) * 1000)
      let applied = applyResult(state, tree, result, earlier)
      state = applied.state
      earlier.append(result)
      steps.append(applied.moves.json)
    }
    var settled: JSON = .null
    if let ended {
      let done = settleRun(state, tree, earlier, line(ended))
      state = done.state
      settled = done.moves.json
    }
    let ratings = state.nodes.mapValues { s in
      obj(["rating": s.rating, "rated": s.rated, "extRating": s.extRating, "extRated": s.extRated, "answered": s.answered, "correct": s.correct])
    }
    return obj(["steps": JSON.array(steps), "settled": settled, "ratings": ratings])
  }

  try check("ratings", [
    "scoring.expectedAccuracy": { expectedAccuracy($0[0].number).json },
    "scoring.ratingAfter": { ratingAfter($0[0].number, $0[1].bool).json },
    "scoring.ratingAfter (walked)": { a in
      var rating = a[0].number
      return a[1].array.map { rating = ratingAfter(rating, $0.bool); return rating }.json
    },
    "scoring.creditedNodes": { creditedNodes(tree, line($0[0].string)).json },
    "scoring.applyResult (a run)": { run($0[0].array, $0[1].stringOrNil) },
    "scoring.rankOf": { encoded(rankOf($0[0].number, $0[1].int)) },
  ])
}

/// Noon on a local day, as the cases build their "now".
private func noon(_ key: String) -> Double {
  let p = key.split(separator: "-").map { Int($0)! }
  let date = Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!
  return date.timeIntervalSince1970 * 1000
}

private func stats(_ days: [JSON], rating: Double = 0, rated: Int? = nil) -> NodeStats {
  var s = emptyNodeStats()
  s.rating = rating
  s.rated = rated ?? (days.contains { $0[2] != .null } ? 10 : 0)
  for d in days {
    let rounds = d[1].int
    s.days[d[0].string] = DayTally(answered: rounds * 5, correct: rounds * 4, rounds: rounds, rating: d[2].numberOrNil)
  }
  return s
}

/// The scoring functions in spec/cases/functions/home.json and autopilot.json.
@Test func scoringOnHome() throws {
  try check("home", [
    "scoring.streak": { streak(stats($0[0].array, rated: 0), noon($0[1].string)).json },
    "scoring.ratingChange": { ratingChange(stats($0[0].array, rating: $0[1].number), 7, noon($0[2].string)).json },
    "scoring.ratingOn": { a in
      let days: [JSON] = [.array([.string("2026-10-01"), .number(1), .number(120)]), .array([.string("2026-10-03"), .number(1), .null]), .array([.string("2026-10-05"), .number(1), .number(90)])]
      return ratingOn(stats(days), a[0].string).json
    },
  ], only: ["scoring.streak", "scoring.ratingChange", "scoring.ratingOn"])

  try check("autopilot", [
    "scoring.recordStart": { a in
      var state = EMPTY_SCORE
      state.starts = a[0].array.map { StartKind(rawValue: $0.string)! }
      return recordStart(state, StartKind(rawValue: a[1].string)!).starts.map(\.rawValue).json
    },
    "srs.runNeed": { a in runNeed(a[0].decoded(Card.self), a[1].int, 1_790_845_200_000).json },
  ], only: ["scoring.recordStart", "srs.runNeed"])
}
