import ChessCore
import Foundation
import Model
import Testing

extension MoveResult {
  var json: JSON {
    obj(["mode": mode.rawValue, "line": line, "color": color.rawValue, "correct": correct, "rated": rated, "ext": ext ? true : nil, "at": at])
  }
}

private func endingJSON(_ e: Ending) -> JSON {
  switch e {
  case .blunder(let played, let best, let lost, let reply):
    return obj(["kind": "blunder", "played": played, "best": best, "lost": lost, "reply": reply])
  case .won: return obj(["kind": "won"])
  case .lost: return obj(["kind": "lost"])
  case .draw: return obj(["kind": "draw"])
  case .ended: return obj(["kind": "ended"])
  }
}

private func effectJSON(_ effect: Effect, _ tree: OpeningTree) -> JSON {
  switch effect {
  case .rate(let result, let earlier):
    return obj(["kind": "rate", "result": result.json, "earlier": earlier.count])
  case .answered(let rid, let fen, let san, let grade):
    return obj(["kind": "answered", "repertoireId": rid, "fen": fen, "san": san, "grade": grade.rawValue])
  case .missed(let rid, let fen, let played, let expected):
    return obj(["kind": "missed", "repertoireId": rid, "fen": fen, "played": played, "expected": expected])
  case .buzz(let pattern):
    return obj(["kind": "buzz", "pattern": pattern])
  case .pop(let p):
    return obj(["kind": "pop", "pop": obj([
      "square": p.square, "text": p.text, "tone": p.tone.rawValue,
      "found": p.found ? true : nil, "book": p.book ? true : nil, "ext": p.ext ? true : nil,
    ])])
  case .note(let note):
    return obj(["kind": "note", "note": note.map { obj(["text": $0.text, "tone": $0.tone]) } ?? .null])
  case .miss(let m):
    return obj(["kind": "miss", "miss": obj(["expected": m.expected, "from": m.from, "to": m.to])])
  case .missedBest(let move):
    return obj(["kind": "missedBest", "move": move.map { obj(["from": $0.from, "to": $0.to]) } ?? .null])
  case .finish(let f):
    var round = encoded(runRound(f, tree, at: 0)).object
    round["at"] = nil
    return obj([
      "kind": "finish",
      "finish": obj([
        "how": endingJSON(f.how), "clean": f.clean, "stub": f.stub,
        "ended": obj(["played": f.ended.run.played, "moves": f.ended.moves, "misses": f.ended.misses.count]),
        "answers": f.answers.count,
      ]),
      "round": JSON.object(round),
    ])
  }
}

private func sessionJSON(_ s: RunSession) -> JSON {
  let st = s.state
  return obj([
    "played": st.run.played, "target": st.run.target, "moves": st.moves,
    "misses": JSON.array(st.misses.map { obj(["ply": $0.ply, "fen": $0.fen, "played": $0.played, "expected": $0.expected]) }),
    "extras": encoded(st.extras), "prepStatus": s.prepStatus.rawValue, "prepSeen": s.prepSeen, "bookTo": s.bookTo,
    "bookOver": s.bookOver, "bookMoves": s.bookMoves, "prepEnd": s.prepEnd, "answers": s.answers.count,
    "prepTimes": s.prepTimes, "lastScored": s.lastScored, "evalCp": s.evalCp,
    "ending": s.ending.map(endingJSON) ?? .null, "label": prepLabel(s)?.rawValue, "prep": prepMoves(s),
  ])
}

/// spec/cases/scenarios/survival.json: each run replayed call by call
/// through the Swift controller, its effects and session compared at every step.
@Test func survivalScenarios() throws {
  let index = bookIndex
  let tree = openingTree(index)
  let file = try JSON.parse(Data(contentsOf: Cases.root.appendingPathComponent("spec/cases/scenarios/survival.json")))
  var replayed = 0
  defer { #expect(replayed == file["scenarios"].array.reduce(0) { $0 + $1["steps"].array.count }) }
  for scenario in file["scenarios"].array {
    let name = scenario["name"].string
    let setup = scenario["setup"]
    let reps = setup["reps"].array.map { r -> Repertoire in
      var out = createRepertoire("", color(r["color"]), r["id"].string)
      for l in r["lines"].strings { out = addLine(out, line(l), .fixed(.seed)).rep }
      return out
    }
    let start = setup["start"]
    var opts = StartOptions(
      steer: SurvivalSteer(rawValue: start["steer"].string)!, tree: tree, reps: reps,
      node: nodeById(tree, start["node"].string), color: ColorChoice(rawValue: start["color"].string)!)
    opts.seed = start["seed"].number
    let begun = try #require(startSurvival(opts), "\(name): no run")
    let prefs = setup["prefs"].decoded(SurvivalPrefs.self)
    let kinds = setup["kinds"].object.mapValues { MoveKind(rawValue: $0.string)! }
    let losses = setup["losses"].object.mapValues(\.number)
    let ctx = RunContext(
      index: index, prefs: prefs, autopilot: setup["autopilot"].bool,
      kindOf: { l, san in kinds["\(l.joined(separator: " ")) | \(san)"] ?? .book }, lossOf: { losses[$0] })
    let picker = mulberry32(seed: setup["picker"].number)
    var session = beginSession(begun)

    for (i, step) in scenario["steps"].array.enumerated() {
      let call = step["call"]
      var effects: [Effect] = []
      switch call["fn"].string {
      case "playPrepared":
        let move = try #require(applySan(session.state.run.fen, call["san"].string))
        (session, effects) = playPrepared(session, ctx, move, call["seconds"].number, call["now"].number)
      case "judgedMove":
        let j = call["judgement"]
        let judged = Judgement(
          san: j["san"].string, ok: j["ok"].bool, lost: j["lost"].number, best: j["best"].stringOrNil, before: j["before"].number,
          after: j["after"].number, moment: j["moment"].bool, found: j["found"].bool, reply: j["reply"].stringOrNil)
        (session, effects) = judgedMove(session, ctx, judged, call["seconds"].number, call["now"].number)
      case "bookTurn":
        let turn = try #require(bookTurn(session, index, picker), "\(name) step \(i): the book had no move")
        (session, effects) = turn
      case "engineMove": (session, effects) = engineMove(session, call["san"].string)
      case "endRun": (session, effects) = endRun(session)
      case "prepRanOut": session = prepRanOut(session, index)
      case "closeBook": session = closeBook(session, index)
      case "sawEval": session = sawEval(session, call["cp"].number)
      case "missionFrom": session = missionFrom(session, prefs, call["cp"].number)
      default: Issue.record("\(name): unknown call \(call["fn"].string)")
      }
      let gotEffects = JSON.array(effects.map { effectJSON($0, tree) })
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
}
