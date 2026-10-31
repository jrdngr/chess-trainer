import ChessCore
import Foundation
import Model
import Testing

func after(_ text: String) -> String {
  line(text).reduce(START_FEN) { applySan($0, $1)!.after }
}

func rep(_ color: Color, _ lines: [String]) -> Repertoire {
  var out = createRepertoire(color == .w ? "White" : "Black", color, "rep_\(color.rawValue)")
  for l in lines { out = addLine(out, line(l), .fixed(.seed)).rep }
  return out
}

/// A tree arg: `{ color, lines }`.
func rep(_ j: JSON) -> Repertoire {
  rep(Color(rawValue: j["color"].string)!, j["lines"].strings)
}

/// A tree written without its node ids.
private func shape(_ r: Repertoire) -> JSON {
  obj([
    "lines": leafLines(r).map { $0.sans.joined(separator: " ") },
    "positions": JSON.array(decisionPoints(r).map { point in
      obj(["path": point.pathSans.joined(separator: " "), "options": point.options.map { $0.san + ($0.preferred ? "*" : "") }])
    }),
    "items": allItems([r]).count,
  ])
}

private func listed(_ o: DerivedOpening) -> JSON {
  obj([
    "name": o.name, "eco": o.eco, "path": o.path.joined(separator: " "), "moves": o.moves, "removes": o.removes,
    "lines": o.lines, "depth": o.depth, "variations": JSON.array(o.variations.map(listed)), "nested": (o.nested ?? []).count,
  ])
}

/// spec/cases/functions/playbook.json
@Test func playbook() throws {
  let index = bookIndex
  func mistake(_ key: String, _ played: String) -> Mistake {
    Mistake(source: .drill, repertoireId: "rep_w", key: key, fen: "", path: [], played: played, expected: "e4")
  }

  try check("playbook", [
    "repertoire.shape": { shape(rep($0[0])) },
    "repertoire.pruneLine": { a in
      let r = rep(a[0])
      let node = nodeAtLine(r, line(a[1].string))!
      return obj(["removed": pruneCount(r, node.id), "left": shape(pruneLine(r, node.id))["lines"]])
    },
    "openings.familiesIn": { .array(familiesIn(rep($0[0]), index).map(listed)) },
    "openings.openingsIn": { .array(openingsIn(rep($0[0]), index).map(listed)) },
    "openings.linesOf": { a in
      let r = rep(a[0])
      return .array(familiesIn(r, index).map { o in
        obj(["family": o.name, "lines": JSON.array(linesOf(r, o, index).map { l in
          obj(["path": l.path.joined(separator: " "), "name": l.name, "split": l.split, "removes": l.removes])
        })])
      })
    },
    "extensions.moveKind": { a in moveKind(index, after(a[0].string), a[1].string, a[2].numberOrNil).rawValue.json },
    "extensions.lineKinds": { a in lineKinds(index, line(a[0].string), Color(rawValue: a[1].string)!).map(\.rawValue).json },
    "extensions.bookLength": { a in bookLength(lineKinds(index, line(a[0].string), Color(rawValue: a[1].string)!)).json },
    "extensions.movedBy": { movedBy($0[0].int, Color(rawValue: $0[1].string)!).json },
    "prepFloor.withFloor": { withFloor($0[0].numbers, $0[1].array.map(\.bool)).json },
    "moveSource.sourceLabel": { sourceLabel($0[0].stringOrNil.map { MoveSource(rawValue: $0)! }).json },
    "moveSource.growthSource": { a in growthSource(index)(after(a[0].string), a[1].string).rawValue.json },
    "mistakes.addMistake": { a in
      var log: [Mistake] = []
      var at = 1_790_845_200_000.0
      let all = a[0].array.map { entry -> [String] in
        at += 1000
        log = Env.at(at) { addMistake(log, mistake(entry[0].string, entry[1].string)) }
        return log.map { "\($0.key):\($0.played)" }
      }
      return a.count > 1 ? all.last!.count.json : all.json
    },
    "mistakes.recentMistakes": { a in
      var b = mistake("b", "h3")
      b.repertoireId = "rep_b"
      var log = [mistake("a", "h3"), b, mistake("c", "h3")]
      for (i, (id, at)) in [("rep_w#a", 3.0), ("rep_b#b", 2), ("rep_w#c", 5)].enumerated() {
        log[i].id = id
        log[i].at = at
      }
      return recentMistakes(log, a[0].stringOrNil).map(\.id).json
    },
  ])
}
