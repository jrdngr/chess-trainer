import ChessCore
import Foundation
import Model
import Shared
import Testing

private func fixed4(_ x: Double) -> Double { Double(JS.toFixed(x, 4))! }

/// spec/cases/functions/draw.json
@Test func draw() throws {
  let index = bookIndex
  let tree = openingTree(index)
  let now = 1_793_448_000_000.0  // 2026-10-31T12:00:00Z
  let white = rep(.w, [
    "e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O", "e4 e5 Nf3 Nc6 Bb5 Nf6 O-O", "e4 e5 Nf3 d6 d4",
    "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3", "e4 c5 Nf3 Nc6 d4 cxd4 Nxd4", "e4 c5 Nf3 e6 d4 cxd4 Nxd4",
    "e4 e6 d4 d5 Nc3", "e4 e6 d4 d5 e5", "e4 c6 d4 d5 e5 Bf5 Nf3",
  ])
  let black = rep(.b, [
    "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6", "e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 Nf6", "e4 c5 Nc3 Nc6", "e4 c5 c3 Nf6",
    "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6", "d4 Nf6 c4 g6 Nf3 Bg7 g3 O-O", "d4 Nf6 Nf3 g6",
  ])
  let reps = [white, black]
  func repFor(_ c: Color) -> Repertoire { c == .w ? white : black }
  func lineOf(_ r: Repertoire, _ tip: String) -> String { leafLines(r).first { $0.tipId == tip }!.sans.joined(separator: " ") }
  func node(_ id: String) -> OpeningNode { nodeById(tree, id) }
  func seenOf(_ rounds: [JSON]) -> Seen {
    var at: [String: Int] = [:]
    for r in rounds { at = markSeen(at, line(r[0].string), r[1].int) }
    return Seen(at: at, round: 10)
  }
  func choice(_ j: JSON) -> ColorChoice { ColorChoice(rawValue: j.string)! }
  func start(_ steer: SurvivalSteer, _ lean: Steer?, _ c: ColorChoice, _ at: OpeningNode, toward: OpeningNode? = nil, enter: Bool = false, seed: Int, seen: Seen? = nil) -> SurvivalStart {
    var opts = StartOptions(steer: steer, tree: tree, reps: reps, node: at, color: c)
    opts.lean = lean
    opts.toward = toward
    opts.enter = enter
    opts.seed = Double(seed)
    opts.seen = seen
    return Env.at(now) { startSurvival(opts)! }
  }
  func counts(_ keys: [String]) -> JSON {
    var out: [String: Int] = [:]
    for k in keys { out[k, default: 0] += 1 }
    return out.json
  }

  try check("draw", [
    "openingRun.lineOdds": { a in
      let c = color(a[0])
      let r = repFor(c)
      let eligible = a[1] == .null ? nil : Set(a[1].strings.map { nodeAtLine(r, line($0))!.id })
      var out: [String: JSON] = [:]
      for (id, p) in lineOdds(r, c, index, eligible).entries { out[lineOf(r, id)] = fixed4(p).json }
      return .object(out)
    },
    "survival.startSurvival (draw)": { a in
      let steer = SurvivalSteer(rawValue: a[0].string)!
      let lean = a[1].stringOrNil.map { Steer(rawValue: $0)! }
      let at = node(a[3].string)
      return (1...12).map { seed -> String in
        let s = start(steer, lean, choice(a[2]), at, toward: at, enter: a[4].bool, seed: seed).state.run
        return "\(s.color.rawValue) [\(s.played.joined(separator: " "))] \(s.target.joined(separator: " "))"
      }.json
    },
    "survival.startSurvival (shares)": { a in
      let plies = a[1].int
      return counts((1...400).map { seed in
        start(.lines, .popular, choice(a[0]), tree.root, seed: seed).state.run.target.prefix(plies).joined(separator: " ")
      })
    },
    "survival.startSurvival (fresh)": { a in
      let seen = seenOf(a[0].array)
      return (1...12).map { seed in
        start(.lines, .popular, .w, node("e4 e5"), seed: seed, seen: seen).state.run.target.joined(separator: " ")
      }.json
    },
    "openingRun.opponentReply": { a in
      let c = color(a[0])
      let source = regionSource(tree, node(a[2].string), repFor(c), c)
      var base = start(.lines, .popular, choice(a[0]), node(a[2].string), seed: 1).state.run
      let played = line(a[1].string)
      base.target = []
      base.played = played
      base.fen = walkSan(played).fens.last!
      let rand = mulberry32(7)
      return counts((1...300).map { _ in opponentReply(source, base, rand).played.last ?? "(none)" })
    },
    "openingRun.wayIn": { wayIn(tree, node($0[0].string), line($0[1].string)).json },
    "openingRun.weaknessFromCards": { a in
      let key = positionKey("rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2")
      var cards: [String: Card] = [:]
      if a[0] != .null {
        var card = createCard(cardId("rep_w", key), "rep_w", key, "", now + DAY)
        let over = a[0].object
        if let v = over["stage"] { card.stage = CardStage(rawValue: v.string)! }
        if let v = over["ease"] { card.ease = v.number }
        if let v = over["lapses"] { card.lapses = v.int }
        if let v = over["correct"] { card.correct = v.int }
        if let v = over["incorrect"] { card.incorrect = v.int }
        if let v = over["due"] { card.due = v.number }
        cards[card.id] = card
      }
      let slips = a[1].int > 0 ? [Slip(kind: "offprep", repertoireId: "rep_w", key: key, games: a[1].int)] : []
      return fixed4Three(weaknessFromCards(cards, slips, now)("rep_w", key)).json
    },
    "openingRun.lineWeakness": { a in
      let values = a[0].numbers
      return lineWeakness("r", values.indices.map(String.init), { _, k in values[Int(k)!] }).json
    },
    "openingRun.judgeByEval": { a in encoded(judgeByEval(color(a[0]), a[1].number, a[2].number)) },
    "openingRun.clock": { a in
      let mode = ClockMode(rawValue: a[0].string)!
      return obj(["seconds": clockSeconds(mode), "label": clockLabel(mode)])
    },
    "openingRun.resolveColor": { a in
      let roll = a[1].number
      return resolveColor(choice(a[0]), { roll }).rawValue.json
    },
    "freshness.staleness": { a in
      let seen = Seen(at: a[0] == .null ? [:] : ["k": a[0].int], round: 10)
      return fixed4(staleness(seen, "k")).json
    },
    "freshness.lineParts": { a in
      let p = lineParts(white, nodeAtLine(white, line(a[0].string))!.id)
      return obj(["head": p.head.count, "tail": p.tail.count])
    },
    "freshness.lineStaleness": { a in
      let seen = seenOf(a[1].array)
      let tip = nodeAtLine(white, line(a[0].string))!.id
      return obj(["stale": fixed4(lineStaleness(seen, white, tip)), "justRun": justRun(seen, white, tip)])
    },
    "evalDelta.whiteCp": { whiteCp(cp: $0[0].numberOrNil, mate: $0[1].numberOrNil).json },
    "evalDelta.deltaFor": { a in
      let d = deltaFor(color(a[0]), a[1].number, a[2].number)
      return obj(["delta": d, "shown": formatDelta(d), "tone": deltaTone(d).rawValue])
    },
    "evalDelta.order": { a in
      let moves = a[0].array.map { (san: $0[0].string, share: $0[1].number, delta: $0[2].numberOrNil) }
      let delta = { (san: String) in moves.first { $0.san == san }!.delta }
      return obj([
        "engine": byDelta(moves, san: \.san, share: \.share, delta).map(\.san),
        "share": byShare(moves, san: \.san, share: \.share, delta).map(\.san),
      ])
    },
    "autopilotPrefs.autopilotModes": { encoded(autopilotModes(AutopilotPrefs(moveScores: $0[0].bool, boardGlow: $0[1].bool))) },
  ])
}

private func fixed4Three(_ x: Double) -> Double { Double(JS.toFixed(x, 3))! }
