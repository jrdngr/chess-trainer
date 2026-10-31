import ChessCore
import Foundation
import Model
import Testing

/// spec/cases/functions/autopilot.json, the Autopilot half.
@Test func autopilot() throws {
  let now = 1_790_845_200_000.0
  let r = rep(.w, ["e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d3", "e4 e5 Nf3 Nc6 Bc4 Nf6 d3 Bc5 c3", "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3"])
  let items = allItems([r])
  let index = prepIndex(r)
  let prepAt = { (fen: String) in index[positionKey(fen)] ?? [] }
  func deck(_ ago: (Int) -> Int?, _ stage: CardStage = .review, _ interval: Double = 1) -> [String: Card] {
    var out: [String: Card] = [:]
    for (i, item) in items.enumerated() {
      var card = createCard(item.cardId, item.repertoireId, item.key, item.fen, now)
      card.stage = stage
      card.interval = interval
      if let tested = ago(i) { card.testedRound = 20 - tested }
      card.correct = i % 3
      card.lapses = i % 2
      out[item.cardId] = card
    }
    return out
  }
  let decks = [deck { _ in nil }, deck { _ in 1 }, deck { $0 % 4 == 0 ? 8 : 2 }, deck({ $0 }, .learning)]
  func kinds(_ j: JSON) -> [StartKind] { j.array.map { StartKind(rawValue: $0.string)! } }

  try check("autopilot", [
    "autopilot.chooseStart": { a in
      chooseStart(recent: kinds(a[0]), cold: a[1].number, inside: a[2].numberOrNil, firstTime: a[3].bool).rawValue.json
    },
    "autopilot.startKind": { a in
      startKind(start: Start(rawValue: a[0]["pick"]["start"].string)!, at: a[0]["at"] == .null ? nil : a[0]["at"].strings).rawValue.json
    },
    "autopilot.splitItems": { a in
      let split = splitItems(items, a[0].int)
      return obj(["wayIn": split.wayIn.map(\.cardId), "inside": split.inside.map(\.cardId)])
    },
    "autopilot.coldNeed": { a in coldNeed(splitItems(items, a[0].int).wayIn, decks[a[1].int], a[2].int).json },
    "autopilot.insideStart": { a in
      insideStart(splitItems(items, a[0].int).inside, decks[a[1].int], accuracy: a[2].numberOrNil, round: a[3].int, now: now)
        .map { obj(["item": $0.item.cardId, "need": $0.need]) } ?? .null
    },
    "recommend.missingPrep": { missingPrep($0[0].numberOrNil).json },
    "autopilot.prepDepth": { a in prepDepth(line(a[0].string), color(a[1]), prepAt, a[2].int).json },
  ], only: ["autopilot.chooseStart", "autopilot.startKind", "autopilot.splitItems", "autopilot.coldNeed", "autopilot.insideStart", "recommend.missingPrep", "autopilot.prepDepth"])
}

/// spec/cases/functions/recommend.json
@Test func recommendations() throws {
  let tree = openingTree(bookIndex)
  let t = 1_790_845_200_000.0
  func focuses(_ j: JSON) -> [Focus] { j.array.map { Focus(rawValue: $0.string)! } }
  func candidate(_ j: JSON) -> Candidate {
    Candidate(
      focus: Focus(rawValue: j["focus"].string)!, openingId: j["openingId"].string, color: color(j["color"]),
      need: j["need"].number, work: j["work"].int, lastAt: j["lastAt"].numberOrNil, starred: j.object["starred"]?.bool ?? false,
      level: j["level"].int)
  }
  func cand(_ c: Candidate) -> JSON {
    obj(["focus": c.focus.rawValue, "openingId": c.openingId, "color": c.color.rawValue, "need": c.need, "work": c.work,
         "lastAt": c.lastAt, "starred": c.starred, "level": c.level, "score": c.score])
  }
  func repOf(_ c: Color, _ lines: [String]) -> Repertoire {
    var out = rep(c, [])
    for l in lines { out = addLine(out, line(l), .fixed(.book)).rep }
    for id in out.nodes.keys { out.nodes[id]!.addedAt = t - 10 * DAY }
    return out
  }
  func recommendIn(_ s: JSON) -> JSON {
    let reps = [repOf(.w, s["white"].strings), repOf(.b, s["black"].strings)].filter { !$0.rootChildren.isEmpty }
    var cards: [String: Card] = [:]
    for item in allItems(reps) {
      guard let rule = s["cards"].array.first(where: { item.pathSans.joined(separator: " ").hasPrefix($0["prefix"].string) || $0["prefix"].string.isEmpty }) else {
        continue
      }
      var card = createCard(item.cardId, item.repertoireId, item.key, item.fen, t - DAY)
      card.stage = .review
      card.interval = 3
      card.due = rule["due"].bool ? t - 1 : t + 5 * DAY
      cards[item.cardId] = card
    }
    let selection = Selection(color: ColorChoice(rawValue: s["selection"]["color"].string)!, opening: s["selection"]["opening"].string)
    let played = s["played"].strings
    var score = EMPTY_SCORE
    for (i, l) in played.enumerated() {
      score = recordRound(score, tree, RoundRecord(
        mode: .run, openingId: selection.opening, color: .w, answered: 1, correct: 1, perfect: false,
        at: t - 3_600_000 - Double(played.count - 1 - i) * DAY, line: line(l)))
    }
    let repairs = (s.object["slipped"]?.strings ?? []).map { l -> RepairRef in
      let path = line(l)
      return RepairRef(kind: "offprep", color: path.count % 2 == 0 ? .w : .b, fen: walkSan(path).fens.last!)
    }
    var input = RecommendInput(
      tree: tree, selection: selection, reps: reps, cards: cards, repairs: repairs, score: score,
      starred: s["starred"].strings, newPerSession: 8, recentFocuses: focuses(s["recentFocuses"]))
    input.recentSteered = s["recentSteered"].array.map(\.bool)
    input.seen = Seen(at: score.seen, round: score.lineRounds)
    input.now = t
    guard let pick = recommend(input) else { return .null }
    return obj(["focus": pick.focus.rawValue, "opening": pick.opening.id, "color": pick.color.rawValue, "start": pick.start.rawValue])
  }

  try check("recommend", [
    "recommend.saturate": { saturate($0[0].number, $0[1].number).json },
    "recommend.reviewNeed": { reviewNeed($0[0].int, $0[1].int, $0[2].int).json },
    "recommend.testNeed": { testNeed($0[0].int, $0[1].bool, $0[2].number).json },
    "recommend.narrowingBar": { narrowingBar($0[0].int).json },
    "recommend.effectiveLevel": { effectiveLevel($0[0].int, $0[1].bool).json },
    "recommend.recentCount": { recentCount(focuses($0[0]), Focus(rawValue: $0[1].string)!).json },
    "recommend.steeredRecently": { steeredRecently($0[0].array.map(\.bool)).json },
    "recommend.rank": { a in .array(rank(a[0].array.map(candidate), focuses(a[1])).map(cand)) },
    "recommend.recommend": { recommendIn($0[0]) },
  ])
}
