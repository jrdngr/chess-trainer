import ChessCore
import Foundation
import Model
import Shared
import Testing

/// The fixtures of `tools.cases.ts`.
private enum Tools {
  static let AT = 1_790_845_200_000.0  // 2026-10-01T09:00:00Z

  /// A tree with its moves added at `AT`.
  static func rep(_ color: Color, _ lines: [String]) -> Playbook {
    var out = createPlaybook(color == .w ? "White" : "Black", color, "rep_\(color.rawValue)")
    for l in lines { out = Env.at(AT) { addLine(out, line(l), .fixed(.seed)).rep } }
    return out
  }

  static let BLACK = rep(.b, [
    "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5 Nb3 Be6",
    "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O",
  ])

  static func mistake(_ l: String, _ played: String, _ expected: String, _ at: Double) -> Mistake {
    let fen = after(l)
    return Mistake(
      id: "\(BLACK.id)#x", at: at, source: .drill, playbookId: BLACK.id, key: positionKey(fen), fen: fen,
      path: line(l), played: played, expected: expected)
  }

  /// One opening's per-day stats: [day, rounds, answered, correct].
  static func stats(_ days: [(String, Int, Int, Int)]) -> NodeStats {
    var s = NodeStats()
    for d in days { s.days[d.0] = DayTally(answered: d.2, correct: d.3, rounds: d.1) }
    return s
  }

  static let HISTORY = stats([
    ("2026-10-20", 2, 10, 8),
    ("2026-10-22", 1, 6, 3),
    ("2026-10-25", 3, 14, 12),
    ("2026-10-29", 1, 5, 5),
    ("2026-10-30", 2, 9, 6),
  ])

  static let SCORE: ScoreState = {
    var s = ScoreState()
    s.nodes = [
      "e4 c5": stats([("2026-10-30", 5, 20, 15)]),
      "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6": stats([("2026-10-30", 3, 12, 10)]),
      "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6": stats([("2026-10-28", 1, 5, 2)]),
      "e4 c5 Nf3 Nc6": stats([("2026-09-01", 4, 12, 9)]),
      "d4 Nf6 c4 g6 Nc3": stats([("2026-10-29", 2, 8, 6)]),
    ]
    return s
  }()
}

/// Noon on a local day, as the cases build their "now".
private func noon(_ key: String) -> Double {
  let p = key.split(separator: "-").map { Int($0)! }
  let date = Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!
  return date.timeIntervalSince1970 * 1000
}


/// Golden/cases/functions/tools.json
@Test func tools() throws {
  let index = bookIndex
  let tree = openingTree(index)
  let T = Tools.self

  func repairs(_ withMistakes: Bool) -> JSON {
    let mistakes = withMistakes
      ? [T.mistake("d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3", "c5", "O-O", T.AT),
         T.mistake("e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3", "e6", "e5", T.AT + 1)]
      : []
    return buildRepairs([T.BLACK], mistakes).map { r in
      "\(r.source.rawValue) \(r.path.joined(separator: " ")) played \(r.played) expected \(r.expected)"
    }.json
  }

  func series(_ days: Int, _ today: String) -> JSON {
    let now = noon(today)
    return obj([
      "accuracy": rollingAccuracy(T.HISTORY, days, now).map { JS.toFixed($0.value, 3) },
      "recent": recentRounds(T.HISTORY, days, now),
    ])
  }

  func styles(_ l: String) -> JSON {
    let choices = bookChoices(index, after(l))
    var picks: [Style: String] = [:]
    for s in STYLES { picks[s.id] = stylePick(index, tree, line(l), choices, s.id) }
    return obj([
      "picks": JSON.object(Dictionary(uniqueKeysWithValues: Style.allCases.map { ($0.rawValue, picks[$0].json) })),
      "shown": shownStyles(picks, .popular).map(\.rawValue),
      "arrows": arrowChoices(choices, picks[.gambit] ?? picks[.fianchetto]).map(\.san),
    ])
  }

  try check("tools", [
    "repair.buildRepairs": { repairs($0[0].bool) },
    "stats.series": { series($0[0].int, $0[1].string) },
    "stats.niceTicks": { niceTicks($0[0].number).json },
    "boardBuilder.bookChoices": { a in
      bookChoices(index, after(a[0].string)).map { "\($0.san) \(JS.toFixed($0.share, 3))" }.json
    },
    "boardBuilder.stylePick": { styles($0[0].string) },
    "boardBuilder.goals": { a in goals(after(a[0].string), color(a[1])).map { "\($0.label): \($0.value)" }.json },
  ])
}
