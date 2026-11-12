import ChessCore
import Foundation
import Model
import Testing

/// Golden/cases/functions/play.json, the Play half.
@Test func play() throws {
  let now = 1_790_845_200_000.0
  let r = rep(.w, ["e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d3", "e4 e5 Nf3 Nc6 Bc4 Nf6 d3 Bc5 c3", "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3"])
  let items = allItems([r])
  let index = prepIndex(r)
  let prepAt = { (fen: String) in index[positionKey(fen)] ?? [] }
  func deck(_ ago: (Int) -> Int?, _ stage: CardStage = .review, _ interval: Double = 3) -> [String: Card] {
    var out: [String: Card] = [:]
    for (i, item) in items.enumerated() {
      var card = createCard(item.cardId, item.playbookId, item.key, item.fen, now)
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

  try check("play", [
    "play.drillStart": { a in
      drillStart(items, decks[a[0].int], accuracy: a[1].numberOrNil, round: a[2].int)
        .map { obj(["item": $0.item.cardId, "need": $0.need]) } ?? .null
    },
    "recommend.missingPrep": { missingPrep($0[0].numberOrNil).json },
    "play.prepDepth": { a in prepDepth(line(a[0].string), color(a[1]), prepAt, a[2].int).json },
  ], only: ["play.drillStart", "recommend.missingPrep", "play.prepDepth"])
}

/// Golden/cases/functions/recommend.json
@Test func recommendations() throws {
  let tree = openingTree(bookIndex)
  let t = 1_790_845_200_000.0
  func focuses(_ j: JSON) -> [Focus] { j.array.map { Focus(rawValue: $0.string)! } }
  func candidate(_ j: JSON) -> Candidate {
    Candidate(
      focus: Focus(rawValue: j["focus"].string)!, openingId: j["openingId"].string, color: color(j["color"]),
      need: j["need"].number, work: j["work"].int, lastAt: j["lastAt"].numberOrNil,
      level: j["level"].int)
  }
  func cand(_ c: Candidate) -> JSON {
    obj(["focus": c.focus.rawValue, "openingId": c.openingId, "color": c.color.rawValue, "need": c.need, "work": c.work,
         "lastAt": c.lastAt, "level": c.level, "score": c.score])
  }
  func repOf(_ c: Color, _ lines: [String]) -> Playbook {
    var out = rep(c, [])
    for l in lines { out = addLine(out, line(l), .fixed(.book)).rep }
    for id in out.nodes.keys { out.nodes[id]!.addedAt = t - 10 * DAY }
    return out
  }
  func recommendIn(_ s: JSON) -> JSON {
    let reps = [repOf(.w, s["white"].strings), repOf(.b, s["black"].strings)].filter { !$0.rootChildren.isEmpty }
    let selection = Selection(color: ColorChoice(rawValue: s["selection"]["color"].string)!, opening: s["selection"]["opening"].string)
    let played = s["played"].strings
    var score = ScoreState()
    for (i, l) in played.enumerated() {
      score = recordRound(score, tree, RoundRecord(
        mode: .run, openingId: selection.opening, color: .w, answered: 1, correct: 1, perfect: false,
        at: t - 3_600_000 - Double(played.count - 1 - i) * DAY, line: line(l)))
    }
    var cards: [String: Card] = [:]
    for item in allItems(reps) {
      guard let rule = s["cards"].array.first(where: { item.pathSans.joined(separator: " ").hasPrefix($0["prefix"].string) || $0["prefix"].string.isEmpty }) else {
        continue
      }
      var card = createCard(item.cardId, item.playbookId, item.key, item.fen, t - DAY)
      card.stage = .review
      card.interval = 9
      card.testedRound = score.lineRounds - (rule["due"].bool ? 9 : 0)
      cards[item.cardId] = card
    }
    let repairs = (s.object["slipped"]?.strings ?? []).map { l -> RepairRef in
      let path = line(l)
      return RepairRef(kind: "offprep", color: path.count % 2 == 0 ? .w : .b, fen: walkSan(path).fens.last!)
    }
    var input = RecommendInput(
      tree: tree, selection: selection, reps: reps, cards: cards, repairs: repairs, score: score,
      newPerSession: 8, recentFocuses: focuses(s["recentFocuses"]))
    input.recentSteered = s["recentSteered"].array.map(\.bool)
    input.seen = Seen(at: score.seen, round: score.lineRounds)
    guard let pick = recommend(input) else { return .null }
    return obj(["focus": pick.focus.rawValue, "opening": pick.opening.id, "color": pick.color.rawValue])
  }

  try check("recommend", [
    "recommend.saturate": { saturate($0[0].number, $0[1].number).json },
    "recommend.reviewNeed": { reviewNeed($0[0].int, $0[1].int, $0[2].int).json },
    "recommend.testNeed": { testNeed($0[0].int, $0[1].bool, $0[2].number).json },
    "recommend.narrowingBar": { narrowingBar($0[0].int).json },
    "recommend.recentCount": { recentCount(focuses($0[0]), Focus(rawValue: $0[1].string)!).json },
    "recommend.steeredRecently": { steeredRecently($0[0].array.map(\.bool)).json },
    "recommend.rank": { a in .array(rank(a[0].array.map(candidate), focuses(a[1])).map(cand)) },
    "recommend.recommend": { recommendIn($0[0]) },
  ])
}

/// Segments count only the player's own moves: a Ruy Lopez played for you (1.e4 e5 2.Nf3 Nc6 3.Bb5) is three of White's moves.
@Test func prepSpanCountsOwnMoves() {
  let ruy = PrepSpan(played: 5, total: 5)
  #expect(ruy.ownMoves(.w) == PrepSpan(played: 3, total: 3))
  #expect(ruy.ownMoves(.b) == PrepSpan(played: 2, total: 2))
  // Prep to 3.Bb5, the book on to 4.Ba4 Nf6 5.O-O, leaving the book after 2...Nc6.
  let booked = PrepSpan(played: 2, total: 5, book: 4)
  #expect(booked.ownMoves(.w) == PrepSpan(played: 1, total: 3, book: 2))
  // A book stretch holding none of Black's moves adds no segment.
  #expect(PrepSpan(played: 0, total: 4, book: 1).ownMoves(.b) == PrepSpan(played: 0, total: 2))
}
