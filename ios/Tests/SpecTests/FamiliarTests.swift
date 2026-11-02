import ChessCore
import Foundation
import Model
import Testing

/// A White Playbook of g3 systems and a Queen's Gambit; a Black one of ...e6 and ...d5.
private let TREES: [String: (color: Color, lines: [String])] = [
  "white": (.w, [
    "d4 Nf6 c4 e6 g3 d5 Bg2 Be7 Nf3",
    "d4 Nf6 c4 e6 g3 Bb4+ Bd2 Be7 Bg2",
    "c4 e5 Nc3 Nf6 g3 d5 cxd5 Nxd5 Bg2",
    "c4 c5 Nf3 Nc6 g3 g6 Bg2",
    "d4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5",
    "d4 d5 c4 c6 Nf3 Nf6 Nc3 dxc4 a4",
  ]),
  "black": (.b, [
    "d4 d5 c4 e6 cxd5 exd5 Nc3 Nf6 Nf3 c6",
    "d4 d5 c4 e6 Nc3 Nf6 Bg5 Be7",
    "d4 d5 c4 e6 Nf3 Nf6 g3 Be7",
    "e4 e6 d4 d5 Nc3 Nf6",
    "e4 e6 d4 d5 e5 c5",
  ]),
]

private let PREFS: [String: NudgePrefs] = [
  "transposition": NudgePrefs(priority: .transposition, pawns: false),
  "habit": NudgePrefs(priority: .habit, pawns: false),
  "pawns": NudgePrefs(priority: .transposition, pawns: true),
]

private let MIN_SHARE = AUTO_GROWTH.minShare
private let OPTS = TidyOptions(prefs: PREFS["transposition"]!, minShare: MIN_SHARE)

private func tree(_ t: JSON) -> Repertoire {
  let found = TREES[t.string]!
  return rep(found.color, found.lines)
}

/// A move as the cases write it: with its tone, pill and reason when nudged.
private func shown(_ moves: [NudgedMove]) -> JSON {
  moves.map { m in m.tone.map { "\(m.san) \($0.rawValue) [\(m.pill!)] \(m.reason!)" } ?? m.san }.json
}

/// A Tidy find without node ids.
private func find(_ f: TidyFind?) -> JSON {
  guard let f else { return .null }
  return obj([
    "path": f.path.joined(separator: " "), "mine": f.mine, "suggestion": f.suggestion, "kind": f.kind.rawValue,
    "tone": f.tone.rawValue, "offBook": f.offBook, "reason": f.reason, "against": f.against, "removes": f.removes,
  ])
}

private func candidates(_ fen: String) -> [NudgeCandidate] {
  popularReplies(bookIndex, fen, MIN_SHARE).map { NudgeCandidate(san: $0.san, share: $0.share) }
}

/// Golden/cases/functions/familiar.json
@Test func familiar() throws {
  let index = bookIndex
  let openings = openingTree(index)

  try check("familiar", [
    "nudge.sameMove": { sameMove($0[0].string).json },
    "nudge.reachable": { reachable(after($0[0].string), after($0[1].string)).json },
    "kin.kinOf": { kinOf($0[0].string).sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }.json },
    "kin.KIN_SETS": { a in
      let set = KIN_SETS[a[0].int]
      return obj(["name": set.name, "families": set.families, "short": set.families.map(shortFamily)])
    },
    "nudge.nudgeArrows": { a in
      let fen = after(a[1].string)
      return shown(nudgeArrows(
        tree(a[0]), index, line(a[1].string), fen, movesToDraw(index, fen), candidates(fen), PREFS[a[2].string]!, MIN_SHARE))
    },
    "nudge.nudgeArrows (append)": { a in
      let fen = after(a[1].string)
      let r = tree(a[0])
      let path = line(a[1].string)
      let prefs = PREFS["transposition"]!
      let extra = familiarOffBook(r, index, path, fen, prefs, MIN_SHARE)
      let offered = candidates(fen) + extra.map { NudgeCandidate(san: $0, share: 0) }
      return shown(nudgeArrows(r, index, path, fen, movesToDraw(index, fen), offered, prefs, MIN_SHARE, Set(extra), true))
    },
    "nudge.familiarOffBook": { a in
      familiarOffBook(
        tree(a[0]), index, line(a[1].string), after(a[1].string), PREFS["transposition"]!, MIN_SHARE,
        habitsOnly: a[2].bool
      ).json
    },
    "answerArrows.roleArrows": { a in
      let fen = after(a[0].string)
      let listed = a[2].bool
        ? popularReplies(index, fen, 0).map { ListedAnswer(san: $0.san) }
        : popularReplies(index, fen, 1).map { ListedAnswer(san: $0.san, share: $0.share) }
      let deltas = a[1]
      return roleArrows(fen, listed) { san in deltas == .null ? nil : deltas[san].numberOrNil }
        .map { "\($0.san) \($0.role.rawValue)" }.json
    },
    "tidy.scan": { a in
      let r = tree(a[0])
      let todo = tidyPositions([r], openings, openings.root)
      let finds = sortFinds(todo.compactMap { findAt(r, index, $0.node, OPTS) })
      return obj(["positions": todo.count, "finds": JSON.array(finds.map(find))])
    },
    "tidy.offPrepHint": { a in
      find(offPrepHint(tree(a[0]), index, after(a[1].string), a[2].string, a[3].string, OPTS))
    },
    "tidy.switchMove": { a in
      let r = tree(a[0])
      guard let node = nodeAtLine(r, line(a[1].string)), let out = switchMove(r, node.id, a[2].string) else { return .null }
      return leafLines(out).map { $0.sans.joined(separator: " ") }.json
    },
    "tidy.moveLabel": { moveLabel($0[0].int, $0[1].string).json },
  ])
}
