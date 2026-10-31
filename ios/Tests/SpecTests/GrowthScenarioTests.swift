import ChessCore
import Foundation
import Model
import Testing

/// spec/cases/scenarios/growth.json: each sitting replayed through the Swift
/// GrowthController. The opponent's replies and the next batch are worked
/// out here, as the screen would, and checked against the recorded calls.
@Test func growthScenarios() throws {
  let index = bookIndex
  let tree = openingTree(index)
  let file = try JSON.parse(Data(contentsOf: Cases.root.appendingPathComponent("spec/cases/scenarios/growth.json")))
  var replayed = 0
  for scenario in file["scenarios"].array {
    let name = scenario["name"].string
    let setup = scenario["setup"]
    var live = rep(color(setup["rep"]["color"]), setup["rep"]["lines"].strings)
    let start = live
    let find = setup["find"]
    let maxPly = find["maxPly"].int
    let rows = growthRows([start], index, GrowthOptions(minShare: find["minShare"].number, maxPly: maxPly))
    let row = try #require(rows.first { $0.id == setup["row"]["id"].string }, "\(name): no row")
    var session = beginGrowth(start, row, setup["fromStart"].bool ? nil : nil)

    func runJSON(_ run: GrowthRun) -> JSON {
      obj(["path": run.path, "fen": run.fen, "hole": run.hole.map(holeJSON) ?? .null, "targets": run.targets.sorted()])
    }
    func sessionJSON(_ s: GrowthSession) -> JSON {
      let round = growthRound(s, tree, tree.root, allowanceOf(s, maxPly), at: 0).map { r -> JSON in
        var o = encoded(r).object
        o["at"] = nil
        return .object(o)
      } ?? .null
      return obj([
        "phase": s.phase.rawValue, "run": runJSON(s.run), "wrong": s.wrong, "added": s.added,
        "batch": s.batch.map { obj(["base": $0.base, "allowance": $0.allowance]) } ?? .null,
        "answer": s.answer?.san,
        "history": JSON.array(s.history.map { obj(["path": $0.run.path, "batch": $0.batch.map { b in obj(["base": b.base, "allowance": b.allowance]) } ?? .null, "san": $0.san]) }),
        "edge": s.edge, "saved": live.nodes.count, "round": round,
      ])
    }
    func effectJSON(_ e: GrowthEffect) -> JSON {
      switch e {
      case .addLine(let l): return obj(["kind": "addLine", "line": l])
      case .removeLine(let id): return obj(["kind": "removeLine", "line": pathTo(live, id).map(\.san)])
      case .log(let kind, let c, let l, let picked, let offered, let all):
        let event = kind == "growth-pick"
          ? obj(["kind": kind, "via": "growth", "color": c.rawValue, "line": l, "picked": picked, "offered": offered])
          : obj(["kind": kind, "via": "growth", "color": c.rawValue, "line": l, "all": all])
        return obj(["kind": "log", "event": event])
      case .buzz(let p): return obj(["kind": "buzz", "pattern": p])
      case .toast(let t): return obj(["kind": "toast", "text": t])
      case .edgeFlash: return obj(["kind": "edgeFlash"])
      }
    }

    for (i, step) in scenario["steps"].array.enumerated() {
      let call = step["call"]
      var effects: [GrowthEffect] = []
      switch call["fn"].string {
      case "measureBatch": session = measureBatch(session, call["maxPly"].int)
      case "choose": (session, effects) = choose(session, call["san"].string, call["allowance"].int, call["offered"].strings)
      case "theyReply":
        let hole = nextHole(index, session.run) ?? nil
        #expect(matches(hole.map(holeJSON) ?? .null, call["hole"]), "\(name) step \(i): their reply")
        session = theyReply(session, hole)
      case "anotherBatch":
        let more = try #require(resumeAdding(start, index, session.run), "\(name) step \(i): nothing more")
        #expect(matches(runJSON(more), call["more"]), "\(name) step \(i): the next batch")
        (session, effects) = anotherBatch(session, start, more)
      case "undo": (session, effects) = undo(session, live, all: call["all"].bool)
      case "stop": session = stop(session)
      case "reachedEdge": (session, effects) = reachedEdge(session)
      case "walk": (session, effects) = walk(session, start, call["san"].string)
      case "opponentWalks": session = opponentWalks(session, start, index, GrowthOptions(minShare: find["minShare"].number, maxPly: maxPly))
      case "nothingPrepared": session = nothingPrepared(session, call["prepared"].int)
      default: Issue.record("\(name): unknown call \(call["fn"].string)")
      }
      let gotEffects = JSON.array(effects.map(effectJSON))
      for effect in effects {
        if case .addLine(let l) = effect { live = addLine(live, l, .each(growthSource(index))).rep }
        if case .removeLine(let id) = effect { live = pruneLine(live, id) }
      }
      if !matches(gotEffects, step["effects"]) {
        Issue.record("\(name) step \(i) \(call["fn"].string) effects\n  expected \(step["effects"])\n  got      \(gotEffects)")
        break
      }
      let after = sessionJSON(session)
      if !matches(after, step["after"]) {
        Issue.record("\(name) step \(i) \(call["fn"].string) session\n  expected \(step["after"])\n  got      \(after)")
        break
      }
      replayed += 1
    }
  }
  #expect(replayed == file["scenarios"].array.reduce(0) { $0 + $1["steps"].array.count })
}
