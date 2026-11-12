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

/// Golden/cases/functions/missions.json
@Test func missions() throws {
  func prefs(_ j: JSON) -> ExtrasPrefs {
    ExtrasPrefs(moments: j["moments"].bool, missions: j["missions"].bool, combo: j["combo"].bool)
  }
  try check("missions", [
    "survival.missionFor": { a in encoded(missionFor(color(a[0]), a[1].number, a.count > 2 ? a[2].stringOrNil : nil)) },
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
  ], only: ["survival.missionFor", "survival.stepMission", "survival.judgedExtras", "survival.prepExtras"])
  // firstMission no longer matches the web: the first mission comes from the
  // eval even where the pawns form a plan. Its own tests are below.
}

/// Where the prep runs out in an isolated queen pawn, the first mission is
/// still the eval's, never Follow the plan.
@Test func firstMissionIgnoresThePlan() {
  var fen = START_FEN
  for san in "e4 c6 d4 d5 exd5 cxd5 c4 Nf6 Nc3 e6 Nf3 Be7 cxd5 Nxd5".split(separator: " ") { fen = applySan(fen, String(san))!.after }
  #expect(structureOf(fen) != nil)
  #expect(firstMission(Extras(), missions: true, .w, 30, fen).mission?.kind == .lead)
  #expect(firstMission(Extras(), missions: true, .w, 150, fen).mission?.kind == .edge)
}

/// The goal card counts down your moves; Keep your edge counts the moves held.
@Test func missionTurnsLeftCountsDown() {
  #expect(missionTurnsLeft(Mission(kind: .convert, moves: 2)) == CONVERT_WINDOW - 2)
  #expect(missionTurnsLeft(Mission(kind: .lead, moves: 5)) == MISSION_WINDOW - 5)
  #expect(missionTurnsLeft(Mission(kind: .edge, moves: 7, held: 4)) == EDGE_MOVES - 4)
}

/// Convert it: a trade settles on the opponent's recapture, and a capture on your last turn
/// waits for their reply.
@Test func convertSettlesOnTheRecapture() {
  func walk(_ text: String) -> String {
    var fen = START_FEN
    for san in line(text) { fen = applySan(fen, san)!.after }
    return fen
  }
  let set = Mission(kind: .convert, moves: 5, pieces: PieceCount(mine: 7, theirs: 7))
  let captured = walk("e4 e5 Nf3 Nc6 Bb5 a6 Bxc6")
  let lastTurn = stepMission(set, .w, 250, captured)
  #expect(lastTurn.result == nil)
  #expect(missionTurnsLeft(lastTurn.mission) == 0)
  #expect(stepMission(set, .w, 150, captured).result == .failed)

  #expect(theirMoveMission(lastTurn.mission, .w, 250, walk("e4 e5 Nf3 Nc6 Bb5 a6 Bxc6 dxc6")) == .done)
  #expect(theirMoveMission(lastTurn.mission, .w, 250, walk("e4 e5 Nf3 Nc6 Bb5 a6 Bxc6 Nf6")) == .failed)

  // Mid-window, the recapture credits at once; any other reply leaves the mission running.
  let early = Mission(kind: .convert, moves: 2, pieces: PieceCount(mine: 7, theirs: 7))
  #expect(theirMoveMission(early, .w, 250, walk("e4 e5 Nf3 Nc6 Bb5 a6 Bxc6 Nf6")) == nil)
  var extras = Extras()
  extras.mission = early
  let settled = theirExtras(extras, .w, 250, walk("e4 e5 Nf3 Nc6 Bb5 a6 Bxc6 dxc6"))
  #expect(settled.earned?.mission?.result == .done)
  #expect(settled.extras.points == MISSION_BONUS)
  #expect(settled.extras.missions.done == 1)
  #expect(settled.extras.mission == nil)
  #expect(settled.extras.missionBreak == MISSION_BREAK)
}

/// Golden/cases/functions/lenses.json
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
    if let k = m.safety { out["safety"] = .string("\(k.mine.rawValue)/\(k.theirs.rawValue)") }
    if m.ghost == true { out["ghost"] = .bool(true) }
    func put(_ key: String, _ list: [String]?, sort: Bool = true) {
      guard let list, !list.isEmpty else { return }
      out[key] = (sort ? list.sorted() : list).json
    }
    put("tints", m.tints?.map { "\($0.square):\($0.color.rawValue):\($0.strength)" })
    put("tags", m.tags?.map { "\($0.square):\($0.tone)" })
    put("dots", m.dots)
    put("rings", m.rings?.map { "\($0.square):\($0.tone)" })
    put("badges", m.badges)
    put("zone", m.zone)
    put("pips", m.pips?.map { "\($0.square):\($0.attackers)/\($0.defenders)" })
    put("shields", m.shields?.map { "\($0.square):\($0.grade.rawValue)" }, sort: false)
    put("emptyPawns", m.emptyPawns)
    put("lines", m.lines?.map { "\($0.from)-\($0.to)" }, sort: false)
    put("arrows", m.arrows?.map { "\($0.from)-\($0.to):\($0.tone)" }, sort: false)
    put("letters", m.letters?.map { "\($0.square):\($0.text)" })
    put("boxes", m.boxes?.map { "\($0.from)-\($0.to)" })
    put("guides", m.guides?.map { "\($0.from)-\($0.to):\($0.tone)" }, sort: false)
    return .object(out)
  }
  try check("lenses", [
    "boardHints.lensMarks": { a in short(lensMarks(LensKind(rawValue: a[1].string)!, fenOf(a[0].string), color(a[2]), prevOf(a[0].string))) },
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
    "boardHints.goalRoute": { a in
      goalRoute(fenOf(a[0].string), color(a[1]), Goal(piece: PieceType(rawValue: a[2].string)!, to: a[3].string)).done.json
    },
  ])
}
