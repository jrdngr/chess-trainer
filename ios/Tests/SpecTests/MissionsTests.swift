import ChessCore
import Foundation
import Model
import Testing

extension Earned {
  var json: JSON {
    obj([
      "points": points,
      "moment": moment.map { obj(["found": $0.found, "bonus": $0.bonus]) } ?? .null,
      "mission": mission.map { obj(["kind": $0.kind.rawValue, "result": $0.result.rawValue, "bonus": $0.bonus]) } ?? .null,
      "combo": combo,
    ])
  }
}

/// spec/cases/functions/missions.json
@Test func missions() throws {
  func prefs(_ j: JSON) -> ExtrasPrefs {
    ExtrasPrefs(moments: j["moments"].bool, missions: j["missions"].bool, combo: j["combo"].bool)
  }
  try check("missions", [
    "survival.missionFor": { a in encoded(missionFor(color(a[0]), a[1].number, a.count > 2 ? a[2].stringOrNil : nil)) },
    "survival.planMission": { a in planMission(a[0].string, color(a[1]), a[2].number).map(encoded) ?? .null },
    "survival.missionText": { missionText($0[0].decoded(Mission.self)).json },
    "survival.stepMission": { a in
      let s = stepMission(a[0].decoded(Mission.self), color(a[1]), a[2].number, a.count > 3 ? a[3].stringOrNil : nil)
      return obj(["mission": encoded(s.mission), "result": s.result?.rawValue])
    },
    "survival.judgedExtras": { a in
      let m = a[3]
      let move = JudgedMove(lost: m["lost"].number, after: m["after"].number, moment: m["moment"].bool, found: m["found"].bool, fen: m["fen"].stringOrNil)
      let r = judgedExtras(a[0].decoded(Extras.self), prefs(a[1]), color(a[2]), move)
      return obj(["extras": encoded(r.extras), "earned": r.earned.json])
    },
    "survival.prepExtras": { encoded(prepExtras($0[0].decoded(Extras.self))) },
    "survival.firstMission": { a in
      encoded(firstMission(a[0].decoded(Extras.self), missions: a[1]["missions"].bool, color(a[2]), a[3].number, a.count > 4 ? a[4].stringOrNil : nil))
    },
  ])
}

/// spec/cases/functions/lenses.json
@Test func lenses() throws {
  func walk(_ text: String) -> [String] {
    var fens = [START_FEN]
    for san in line(text) { fens.append(applySan(fens.last!, san)!.after) }
    return fens
  }
  let games: [String: String] = [
    "start": "",
    "isolated queen pawn": "e4 c6 d4 d5 exd5 cxd5 c4 Nf6 Nc3 e6 Nf3 Be7 cxd5 Nxd5",
    "carlsbad": "d4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5 c6 e3 Be7 Bd3 Nbd7",
    "stonewall": "d4 e6 c4 f5 g3 Nf6 Bg2 d5 Nf3 c6 O-O Bd6",
    "king's indian": "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nc6 d5 Ne7",
    "maroczy": "e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 g6 c4 Bg7 Be3 Nf6 Nc3 d6",
    "french advance": "e4 e6 d4 d5 e5 c5 c3 Nc6 Nf3 Qb6",
    "english attack": "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5 Nb3 Be6 f3 Be7 Qd2 O-O O-O-O Nbd7 g4",
    "a trap": "e4 e5 Nf3 Nc6 Bc4 Nd4 Nxe5 Qg5 Nxf7 Qxg2",
    "caro advance": "e4 c6 d4 d5 e5 Bf5 Nf3 e6 Be2 c5",
    "hedgehog": "c4 c5 Nf3 Nf6 Nc3 e6 g3 b6 Bg2 Bb7 O-O Be7 d4 cxd4 Qxd4 d6 Rd1 a6 b3 Nbd7 e4 Qc7",
  ]
  func fenOf(_ name: String) -> String { walk(games[name]!).last! }
  func prevOf(_ name: String) -> String? { let w = walk(games[name]!); return w.count > 1 ? w[w.count - 2] : nil }
  func short(_ m: LensMarks) -> JSON {
    var out: [String: JSON] = [:]
    if let c = m.caption { out["caption"] = .string(c) }
    if m.ghost == true { out["ghost"] = .bool(true) }
    func put(_ key: String, _ list: [String]?, sort: Bool = true) {
      guard let list, !list.isEmpty else { return }
      out[key] = (sort ? list.sorted() : list).json
    }
    put("tints", m.tints?.map { "\($0.square):\($0.color.rawValue):\($0.strength)" })
    put("tags", m.tags?.map { "\($0.square):\($0.tone)" })
    put("dots", m.dots)
    put("rings", m.rings?.map { "\($0.square):\($0.tone)" })
    put("stars", m.stars?.map { "\($0.square):\($0.side.rawValue)" })
    put("zone", m.zone)
    put("pips", m.pips?.map { "\($0.square):\($0.attackers)/\($0.defenders)" })
    put("shields", m.shields?.map { "\($0.square):\($0.grade.rawValue)" }, sort: false)
    put("emptyPawns", m.emptyPawns)
    put("lines", m.lines?.map { "\($0.from)-\($0.to)" }, sort: false)
    put("arrows", m.arrows?.map { "\($0.from)-\($0.to):\($0.tone)" }, sort: false)
    return .object(out)
  }
  try check("lenses", [
    "boardHints.lensMarks": { a in short(lensMarks(LensKind(rawValue: a[1].string)!, fenOf(a[0].string), color(a[2]), prevOf(a[0].string))) },
    "boardHints.spaceCount": { a in let s = spaceCount(fenOf(a[0].string), color(a[1])); return obj(["mine": s.mine, "theirs": s.theirs]) },
    "boardHints.kingReport": { a in
      kingReport(fenOf(a[0].string), color(a[1])).map { obj(["square": $0.square, "score": $0.score, "grade": $0.grade.rawValue]) } ?? .null
    },
    "boardHints.breakCandidates": { a in
      asMover(fenOf(a[0].string), color(a[1])).map { breakCandidates($0, color(a[1])).json } ?? .null
    },
    "boardHints.newlyLoose": { a in
      let before = walk(a[0].string).last!
      let move = applySan(before, a[1].string)!
      return newlyLoose(before, move.after, fenTurn(before), from: move.from, to: move.to).json
    },
    "structures.structureOf": { structureOf(fenOf($0[0].string)).map(structureLabel)?.json ?? .null },
    "structures.planFor": { a in
      let template = STRUCTURE_TEMPLATES.first { $0.id == a[0].string }!
      return planFor(Structure(template: template, a: color(a[1])), color(a[2])).map { s in
        s.text + (s.goals.map { " [" + $0.map { "\($0.piece.rawValue)\($0.to)" }.joined(separator: " ") + "]" } ?? "")
      }.json
    },
    "boardHints.goalRoute": { a in
      goalRoute(fenOf(a[0].string), color(a[1]), Goal(piece: PieceType(rawValue: a[2].string)!, to: a[3].string)).done.json
    },
    "cashOut.pickTrade": { a in
      let fen = walk("d4 d5 c4 e6 Nc3 Nf6 Bg5 Be7").last!
      return pickTrade(fen, a[0].array.map { $0.decoded(EngineLine.self) }, color(a[1])).map(encoded) ?? .null
    },
  ])
}
