import ChessCore
import Foundation
import Model
import Shared
import Testing

/// The fixtures of `tools.cases.ts`.
private enum Tools {
  static let AT = 1_790_845_200_000.0  // 2026-10-01T09:00:00Z

  /// A tree with its moves added at `AT`, and engine losses on the last move of some lines.
  static func rep(_ color: Color, _ lines: [String], lost: [String: Double] = [:]) -> Repertoire {
    var out = createRepertoire(color == .w ? "White" : "Black", color, "rep_\(color.rawValue)")
    for l in lines { out = Env.at(AT) { addLine(out, line(l), .fixed(.seed)).rep } }
    for (l, cp) in lost { out.nodes[nodeAtLine(out, line(l))!.id]!.lost = cp }
    return out
  }

  static func game(_ id: String, _ moves: String, _ result: String, _ userColor: Color) -> ImportedGame {
    ImportedGame(
      id: id, source: .lichess, white: userColor == .w ? "me" : "them", black: userColor == .b ? "me" : "them",
      result: result, userColor: userColor, date: "2026-09-01", moves: line(moves))
  }

  /// Black games: the Najdorf prepared; English Attack, a slip at move 6, and an unprepared 2.c3.
  static let GAMES = [
    game("g1", "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5 Nb3 Be6", "0-1", .b),
    game("g2", "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e6 f3 b5", "1-0", .b),
    game("g3", "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e6 g4 h6", "1-0", .b),
    game("g4", "e4 c5 c3 Nf6 e5 Nd5 d4 cxd4", "1/2-1/2", .b),
    game("g5", "e4 c5 c3 Nf6 e5 Nd5 Nf3 Nc6", "1-0", .b),
    game("g6", "e4 c5 c3 d5 exd5 Qxd5 d4 Nf6", "0-1", .b),
    game("g7", "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6", "1-0", .b),
    game("g8", "d4 Nf6 c4 g6 Nc3 Bg7 e4 O-O", "1-0", .b),
    game("g9", "e4 e5 Nf3 Nc6 Bb5 a6", "1-0", .w),
  ]
  static let BLACK = rep(.b, [
    "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5 Nb3 Be6",
    "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O",
  ])

  static func mistake(_ l: String, _ played: String, _ expected: String, _ at: Double) -> Mistake {
    let fen = after(l)
    return Mistake(
      id: "\(BLACK.id)#x", at: at, source: .drill, repertoireId: BLACK.id, key: positionKey(fen), fen: fen,
      path: line(l), played: played, expected: expected)
  }

  /// One opening's per-day stats: [day, rounds, answered, correct, rating or nil].
  static func stats(_ days: [(String, Int, Int, Int, Double?)], rating: Double = 0) -> NodeStats {
    var s = emptyNodeStats()
    s.rating = rating
    s.rated = days.contains { $0.4 != nil } ? 20 : 0
    for d in days { s.days[d.0] = DayTally(answered: d.2, correct: d.3, rounds: d.1, rating: d.4) }
    return s
  }

  static let HISTORY = stats([
    ("2026-10-20", 2, 10, 8, 120),
    ("2026-10-22", 1, 6, 3, 110),
    ("2026-10-25", 3, 14, 12, 160),
    ("2026-10-29", 1, 5, 5, nil),
    ("2026-10-30", 2, 9, 6, 175),
  ], rating: 175)

  static let SCORE: ScoreState = {
    var s = EMPTY_SCORE
    s.nodes = [
      "e4 c5": stats([("2026-10-30", 5, 20, 15, 300)], rating: 300),
      "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6": stats([("2026-10-30", 3, 12, 10, 420)], rating: 420),
      "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6": stats([("2026-10-28", 1, 5, 2, 90)], rating: 90),
      "e4 c5 Nf3 Nc6": stats([("2026-09-01", 4, 12, 9, 200)], rating: 200),
      "d4 Nf6 c4 g6 Nc3": stats([("2026-10-29", 2, 8, 6, 260)], rating: 260),
    ]
    return s
  }()

  static let EXT = rep(.b, [
    "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5 Nb3 Be6",
    "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 h5",
    "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Bg5 e6 f4 Qb6",
    "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Bg5 Nbd7",
    "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 h3 e5 Nde2 h5 g3 h4",
    "e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 Nf6 Nc3 d6 Bg5 Qa5",
  ], lost: ["e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Bg5 Nbd7": 120])
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
    return buildRepairs(T.GAMES, [T.BLACK], RepairOptions(mistakes: mistakes)).map { r in
      let played = r.played.map(\.san).joined(separator: ",")
      return "\(r.kind.rawValue) \(r.source.name) \(r.path.joined(separator: " ")) games \(r.games) played \(played) expected \(r.expected.joined(separator: ",")) weight \(JS.toFixed(r.weight, 2))"
    }.json
  }

  func series(_ days: Int, _ today: String) -> JSON {
    let now = noon(today)
    return obj([
      "rounds": dailyRounds(T.HISTORY, days, now).map { "\($0.key):\(JS.string($0.value))" },
      "rating": ratingOverTime(T.HISTORY, days, now).map { JS.string($0.value) },
      "accuracy": rollingAccuracy(T.HISTORY, days, now).map { JS.toFixed($0.value, 3) },
      "recent": recentRounds(T.HISTORY, days, now),
    ])
  }

  func layout(_ extOnly: Bool) -> JSON {
    let kinds = treeKinds(T.EXT, index)
    let root = nodeAtLine(T.EXT, ["e4"])!
    return layoutGraph(T.EXT, index, kinds, root.id, extOnly: extOnly).map { row in
      let from = row.parent.map { "\($0.row).\($0.col)" } ?? "-"
      let cells = row.cells.map { c in
        if c.kind == .move(.book) { return c.label }
        return "\(c.label)(\(c.kind.name)\(c.joinRow.map { " \($0)" } ?? ""))"
      }
      return "\(from) @\(row.start): \(cells.joined(separator: " "))"
    }.json
  }

  func kept(_ keptAt: Double?, _ addedLater: Double) -> JSON {
    var r = T.EXT
    let root = nodeAtLine(r, line("e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Bg5 Nbd7"))!
    for id in r.nodes.keys { r.nodes[id]!.addedAt = 100 }
    r.nodes[root.id]!.keptAt = keptAt
    r.nodes[root.id]!.addedAt = addedLater
    return keptCurrent(r, r.nodes[root.id]!).json
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
    "gameAnalysis.buildPlayerTree": { a in
      let t = buildPlayerTree(T.GAMES, color(a[0]))
      let positions = t.nodes.values.filter { $0.games >= 2 }.map { n in
        let choices = n.choices.isEmpty ? "" : " [" + n.choices.entries.map { "\($0.key):\($0.value)" }.joined(separator: " ") + "]"
        return "\(n.path.joined(separator: " ")) \(n.games)g \(n.wins)/\(n.draws)/\(n.losses)\(choices)"
      }
      return obj(["games": t.games, "positions": positions])
    },
    "gameAnalysis.analyseAgainstRepertoire": { a in
      analyseAgainstRepertoire(buildPlayerTree(T.GAMES, .b), T.BLACK, minGames: a[0].int).map { f in
        let played = f.played.map { "\($0.san):\($0.count)" }.joined(separator: ",")
        return "\(f.kind.rawValue) \(f.path.joined(separator: " ")) games \(f.games) played \(played) expected \(f.expected.joined(separator: ","))"
      }.json
    },
    "gameAnalysis.measureCoverage": { a in
      let c = color(a[0])
      let cov = measureCoverage(T.GAMES.filter { $0.userColor == c }, c == .b ? T.BLACK : T.rep(.w, ["e4 e5 Nf3 Nc6 Bc4"]))
      return obj(["inPrep": cov.inPrep, "outOfPrep": cov.outOfPrep, "averageExitPly": cov.averageExitPly, "games": cov.games])
    },
    "repair.buildRepairs": { repairs($0[0].bool) },
    "stats.series": { series($0[0].int, $0[1].string) },
    "stats.favouriteness": { a in
      guard let f = favouriteness(tree, T.SCORE, a[0].string, 30, noon("2026-10-31")) else { return .null }
      return obj(["rank": f.rank, "of": f.of, "parent": f.parent?.id, "siblings": f.siblings.map { "\($0.node.id):\($0.rounds)" }])
    },
    "stats.ladders": { a in
      let starred = a[0].strings
      return obj([
        "favorites": starredOpenings(tree, T.SCORE, starred).map(\.node.id),
        "rated": ratedOpenings(tree, T.SCORE, starred).map(\.node.id),
      ])
    },
    "stats.niceTicks": { niceTicks($0[0].number).json },
    "extensionGraph.layoutGraph": { layout($0[0].bool) },
    "extensionGraph.extensionRoots": { _ in
      let kinds = treeKinds(T.EXT, index)
      return extensionRoots(T.EXT, kinds).map { n in
        "\(pathTo(T.EXT, n.id).map(\.san).joined(separator: " ")) (\(kinds[n.id]!.rawValue))"
      }.json
    },
    "extensionGraph.orderedKids": { a in
      let kinds = treeKinds(T.EXT, index)
      return orderedKids(T.EXT, index, kinds, nodeAtLine(T.EXT, line(a[0].string))!.id).map(\.san).json
    },
    "extensionGraph.keptCurrent": { kept($0[0].numberOrNil, $0[1].number) },
    "boardBuilder.bookChoices": { a in
      bookChoices(index, after(a[0].string)).map { "\($0.san) \(JS.toFixed($0.share, 3))" }.json
    },
    "boardBuilder.stylePick": { styles($0[0].string) },
    "boardBuilder.goals": { a in goals(after(a[0].string), color(a[1])).map { "\($0.label): \($0.value)" }.json },
  ])
}
