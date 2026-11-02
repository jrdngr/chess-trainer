import ChessCore
import Foundation
import Model
import Testing

/// Golden/cases/scenarios/drill.json: each sitting replayed call by call
/// through the Swift drill controllers. The cards are kept here as the store
/// keeps them, and what the screen works out (the follow-up, the item, the
/// next draw) is worked out here and checked against the recorded call.

private let NOW = 1_790_845_200_000.0

private func drillFile() throws -> JSON {
  try JSON.parse(Data(contentsOf: Cases.golden.appendingPathComponent("cases/scenarios/drill.json")))
}

private func pattern(_ p: [Int]) -> JSON { p.count == 1 ? p[0].json : p.json }

private func mistakeJSON(_ m: Mistake) -> JSON {
  obj(["source": m.source.rawValue, "repertoireId": m.repertoireId, "key": m.key, "fen": m.fen, "path": m.path, "played": m.played, "expected": m.expected])
}

private func roundJSON(_ r: RoundRecord?) -> JSON {
  guard let r else { return .null }
  var o = encoded(r).object
  o["at"] = nil
  return .object(o)
}

private func options(_ j: JSON) -> DrillOptions {
  DrillOptions(mode: SessionMode(rawValue: j["mode"].string)!, maxNew: j["maxNew"].int, weakFirst: j["weakFirst"].bool)
}

/// A move the position does not want: the first quiet one that is legal and not prepared.
private func wrongMove(_ fen: String, _ right: [String]) -> LegalMove {
  let san = ["a3", "h3", "a6", "h6", "a4", "h4", "a5", "h5"].first { !right.contains($0) && applySan(fen, $0) != nil }!
  return applySan(fen, san)!
}

private func check(_ name: String, _ i: Int, _ fn: String, _ what: String, _ got: JSON, _ want: JSON) -> Bool {
  if matches(got, want) { return true }
  Issue.record("\(name) step \(i) \(fn) \(what)\n  expected \(want)\n  got      \(got)")
  return false
}

@Test func drillPositionScenarios() throws {
  let file = try drillFile()
  var replayed = 0
  var expected = 0
  for scenario in file["scenarios"].array where scenario["name"].string.hasPrefix("positions") {
    let name = scenario["name"].string
    let setup = scenario["setup"]
    expected += scenario["steps"].array.count
    let r = rep(color(setup["rep"]["color"]), setup["rep"]["lines"].strings)
    let items = allItems([r])
    let rand = mulberry32(UInt32(setup["picker"].int))
    let followLine = setup["followLine"].bool
    var clock = NOW
    var cards: [String: Card] = [:]
    var state = DrillState(queue: [])

    func summary(_ s: DrillState) -> JSON {
      let last = s.last.map { l in obj(["item": l.item.cardId, "grade": l.grade.rawValue, "played": l.played, "before": encoded(l.before)]) }
      return obj([
        "index": s.index, "asking": current(s)?.cardId, "queue": s.queue.map(\.cardId), "phase": s.phase.rawValue,
        "played": s.played?.san, "stats": obj(["answered": s.stats.answered, "correct": s.stats.correct]),
        "last": last ?? .null, "cards": cards.count, "round": roundJSON(drillRound(s, "", at: 0)),
      ])
    }
    func effectJSON(_ e: DrillEffect) -> JSON {
      switch e {
      case .record(let line, let c, let correct): return obj(["kind": "record", "line": line, "color": c.rawValue, "correct": correct])
      case .buzz(let p): return obj(["kind": "buzz", "pattern": pattern(p)])
      case .grade(let item, let g, let played, let correct):
        return obj(["kind": "grade", "item": item.cardId, "grade": g.rawValue, "played": played, "correct": correct])
      case .regrade(let item, let before, let g, let played):
        return obj(["kind": "regrade", "item": item.cardId, "before": encoded(before), "grade": g.rawValue, "played": played])
      case .mistake(let m): return obj(["kind": "mistake", "mistake": mistakeJSON(m)])
      case .flash(let next): return obj(["kind": "flash", "next": next?.cardId])
      }
    }
    /// What the store does with a grade.
    func store(_ e: DrillEffect) {
      if case .grade(let item, let g, _, _) = e {
        let card = cards[item.cardId] ?? createCard(item.cardId, item.repertoireId, item.key, item.fen, clock)
        cards[item.cardId] = review(card, g, clock).card
      }
      if case .regrade(let item, let before, let g, _) = e { cards[item.cardId] = review(before, g, clock).card }
    }

    for (i, step) in scenario["steps"].array.enumerated() {
      let call = step["call"]
      let fn = call["fn"].string
      var effects: [DrillEffect] = []
      switch fn {
      case "beginDrill":
        state = Env.at(clock) { beginDrill(items, cards, options(call["opts"]), clock) }
      case "refill":
        #expect(call["now"].number == clock, "\(name) step \(i): refill's clock")
        state = refill(state, items, cards, options(call["opts"]), rand, clock)
      case "continueAfterWrong": state = continueAfterWrong(state)
      case "regradeLast": (state, effects) = regradeLast(state, Grade(rawValue: call["grade"].string)!)
      case "advance":
        let extra = call["extra"].stringOrNil.flatMap { id in items.first { $0.cardId == id } }
        state = advance(state, extra)
      case "answer":
        clock += 1000
        let item = try #require(current(state), "\(name) step \(i): nothing to ask")
        let san = call["san"].string
        let move = applySan(item.fen, san) ?? wrongMove(item.fen, item.expected.map { $0.san })
        let followUp = followLine ? followUpFor(item, items, r) : nil
        _ = check(name, i, fn, "followUp", followUp?.cardId.json ?? .null, call["followUp"])
        _ = check(name, i, fn, "card", cards[item.cardId].map(encoded) ?? .null, call["card"])
        (state, effects) = Env.at(clock) { answer(state, move, call["took"].number, cards[item.cardId], followUp) }
      default: Issue.record("\(name): unknown call \(fn)")
      }
      guard check(name, i, fn, "effects", JSON.array(effects.map(effectJSON)), step["effects"]) else { break }
      effects.forEach(store)
      guard check(name, i, fn, "state", summary(state), step["after"]) else { break }
      replayed += 1
    }
  }
  #expect(replayed == expected)
}

/// A tree's node ids, written as `@` and the line to the node, as the file writes them.
private func noIds(_ r: Repertoire, _ j: JSON) -> JSON {
  let ids = r.nodes.keys.sorted { $0.count > $1.count }
  func fix(_ s: String) -> String {
    ids.reduce(s) { out, id in
      out.contains(id) ? out.replacingOccurrences(of: id, with: "@" + pathTo(r, id).map(\.san).joined(separator: " ")) : out
    }
  }
  switch j {
  case .string(let s): return .string(fix(s))
  case .array(let a): return .array(a.map { noIds(r, $0) })
  case .object(let o): return .object(o.mapValues { noIds(r, $0) })
  default: return j
  }
}

private func lineJSON(_ l: DrillLine) -> JSON {
  obj(["repertoireId": l.repertoireId, "color": l.color.rawValue, "tipId": l.tipId, "sans": l.sans])
}

@Test func drillLineScenarios() throws {
  typealias L = LineDrillController
  let file = try drillFile()
  let index = bookIndex
  let tree = openingTree(index)
  var replayed = 0
  var expected = 0
  for scenario in file["scenarios"].array where scenario["name"].string.hasPrefix("lines") {
    let name = scenario["name"].string
    let setup = scenario["setup"]
    expected += scenario["steps"].array.count
    let side = color(setup["rep"]["color"])
    let r = rep(side, setup["rep"]["lines"].strings)
    let items = allItems([r])
    let rand = mulberry32(UInt32(setup["picker"].int))
    let lean = LineLean(rawValue: setup["lean"].string)!
    var clock = NOW
    var lineCards: [String: LineCard] = [:]
    var mistakes = Set<String>()
    var pending: (before: LineCard, grade: Grade)?
    var state = L.begin([])

    func draw(_ avoid: Set<String>? = nil) -> [DrillLine] {
      drawLines(DrawOptions(
        rep: r, tree: tree, region: tree.root, index: index, lean: lean, cards: lineCards, avoid: avoid,
        count: setup["count"].int, rand: rand, now: clock))
    }
    func fenAt(_ s: LineDrillState) -> String {
      s.line!.sans.prefix(s.ply).reduce(START_FEN) { applySan($0, $1)!.after }
    }
    func summary(_ s: LineDrillState) -> JSON {
      obj([
        "group": s.group, "at": s.at, "batch": s.batch.map { $0.sans.joined(separator: " ") }, "line": s.line?.sans,
        "ply": s.ply, "phase": s.phase.rawValue, "played": s.played?.san, "misses": s.misses, "times": s.times,
        "graded": s.graded.map { obj(["before": encoded($0.before), "grade": $0.grade.rawValue]) } ?? .null,
        "finished": s.finished,
      ])
    }
    func effectJSON(_ e: LineEffect) -> JSON {
      switch e {
      case .record(let line, let correct): return obj(["kind": "record", "line": line, "correct": correct])
      case .buzz(let p): return obj(["kind": "buzz", "pattern": pattern(p)])
      case .clearMistake(let id): return obj(["kind": "clearMistake", "id": id])
      case .mistake(let m): return obj(["kind": "mistake", "mistake": mistakeJSON(m)])
      case .flash: return obj(["kind": "flash"])
      case .round(let round): return obj(["kind": "round", "round": roundJSON(round)])
      case .gradeLine(let rid, let tip, let g, let before):
        return obj(["kind": "gradeLine", "repertoireId": rid, "tipId": tip, "grade": g.rawValue, "before": before.map(encoded)])
      }
    }
    func store(_ e: LineEffect) {
      switch e {
      case .mistake(let m): mistakes.insert("\(m.repertoireId)#\(m.key)")
      case .clearMistake(let id): mistakes.remove(id)
      case .gradeLine(let rid, let tip, let g, let before):
        let id = lineCardId(rid, tip)
        let from = before ?? lineCards[id] ?? createLineCard(rid, tip, clock)
        lineCards[id] = review(from, g, clock).card
        if before == nil { pending = (from, g) }
      default: break
      }
    }

    for (i, step) in scenario["steps"].array.enumerated() {
      let call = step["call"]
      let fn = call["fn"].string
      var effects: [LineEffect] = []
      switch fn {
      case "beginLines":
        let drawn = draw()
        _ = check(name, i, fn, "lines", noIds(r, JSON.array(drawn.map(lineJSON))), call["lines"])
        state = L.begin(drawn)
      case "theirMove": state = L.theirMove(state, side)
      case "lineDone": (state, effects) = L.lineDone(state, side, tree, tree.root, at: 0)
      case "carryOn": state = L.carryOn(state)
      case "graded":
        let got = try #require(pending, "\(name) step \(i): nothing graded")
        _ = check(name, i, fn, "before", noIds(r, encoded(got.before)), call["before"])
        state = L.graded(state, got.before, got.grade)
        pending = nil
      case "regrade": (state, effects) = L.regrade(state, Grade(rawValue: call["grade"].string)!)
      case "nextLine":
        let fresh = L.needsDraw(state) ? draw(Set(state.batch.map(\.tipId))) : nil
        _ = check(name, i, fn, "fresh", noIds(r, fresh.map { JSON.array($0.map(lineJSON)) } ?? .null), call["fresh"])
        state = L.nextLine(state, fresh)
      case "answer":
        clock += 1000
        let fen = fenAt(state)
        let item = items.first { $0.key == positionKey(fen) }
        _ = check(name, i, fn, "item", item?.cardId.json ?? .null, call["item"])
        _ = check(name, i, fn, "mistakeIds", mistakes.sorted().json, call["mistakeIds"])
        let move = applySan(fen, call["san"].string) ?? wrongMove(fen, item?.expected.map { $0.san } ?? [])
        (state, effects) = L.answer(state, side, move, call["took"].number, r, item, Array(mistakes))
      default: Issue.record("\(name): unknown call \(fn)")
      }
      guard check(name, i, fn, "effects", noIds(r, JSON.array(effects.map(effectJSON))), step["effects"]) else { break }
      guard check(name, i, fn, "state", noIds(r, summary(state)), step["after"]) else { break }
      effects.forEach(store)
      replayed += 1
    }
  }
  #expect(replayed == expected)
}

/// Drill's constants against Golden/constants.json.
@Test func drillConstants() throws {
  let all = try JSON.parse(Data(contentsOf: Cases.golden.appendingPathComponent("constants.json")))
  func expect(_ file: String, _ name: String, _ value: JSON) {
    let want = all["src/model/\(file).ts"][name]
    #expect(want != .null && matches(value, want), "\(file).\(name): \(value) is not \(want)")
  }
  expect("drillController", "BATCH", DRILL_BATCH.json)
  expect("drillController", "REFILL_AT", REFILL_AT.json)
  expect("drillController", "REQUEUE_AFTER", REQUEUE_AFTER.json)
  expect("lineDrill", "LINE_BUDGET", LINE_BUDGET.json)
  expect("lineDrill", "MAX_LINES", MAX_LINES.json)
  expect("modes", "DEFAULT_DRILL", encoded(DEFAULT_DRILL))
  expect("modes", "DRAW_LABELS", Dictionary(uniqueKeysWithValues: DRILL_DRAW_LABELS.map { ($0.key.rawValue, $0.value) }).json)
  expect("modes", "FORM_LABELS", Dictionary(uniqueKeysWithValues: DRILL_FORM_LABELS.map { ($0.key.rawValue, $0.value) }).json)
}

/// A save from before Drill's options takes the defaults, and a partial one keeps what it has.
@Test func drillSettingsDecode() throws {
  let old = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
  #expect(old.drill == DEFAULT_DRILL)
  let partial = try JSONDecoder().decode(Settings.self, from: Data(#"{"drill":{"form":"lines","newPerSession":12}}"#.utf8))
  #expect(partial.drill.form == .lines && partial.drill.newPerSession == 12 && partial.drill.followLine)
}
