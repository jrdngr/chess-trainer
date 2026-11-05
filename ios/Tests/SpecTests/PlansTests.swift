import ChessCore
import Foundation
import Model
import Testing

private func walk(_ text: String) -> [String] {
  var fens = [START_FEN]
  for san in line(text) { fens.append(applySan(fens.last!, san)!.after) }
  return fens
}

private func at(_ text: String) -> String { walk(text).last! }

private func mark(_ step: PlanStep, _ fen: String, _ me: ChessCore.Color) -> StepMark? {
  markOf(step, fen, PlanFacts(fen), me: me, a: .w)
}

/// The Smith-Morra position that once kept the Yugoslav plan after White castled short.
@Test func castledShortDragonIsClassical() {
  let fen = "r1bqk2r/pp2ppbp/2np2p1/8/4P1n1/2PBBN2/PP1N1PPP/R2QR1K1 w kq - 0 11"
  let plan = planOf(fen, .w)!
  #expect(plan.key == "dragon:w:classical")
  #expect(plan.label == "Dragon · Classical")
  #expect(plan.headline == "Knight to d5")
  #expect(plan.steps.map(\.text) == [
    "Knight to d5 trades a key defender", "Push f4–f5 for kingside space", "Watch for ...Rxc3, the exchange sacrifice",
  ])
}

@Test(arguments: [
  ("e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6 Be3 Bg7 f3 O-O Qd2 Nc6", ChessCore.Color.w, "dragon:w:yugoslav"),
  ("e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6 Be2 Bg7 O-O O-O", .b, "dragon:w:classical"),
  ("e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 e6", .w, "scheveningen:w:keres"),
  ("e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 e6 Be2 Be7 O-O", .w, "scheveningen:w:classical"),
  ("d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nc6 d5 Ne7", .b, "kid-chain:w:storm"),
  ("d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 d5", .b, "kid-chain:w:queenside"),
  ("d4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5 c6 Qc2 Be7 e3 Nbd7 Bd3 O-O", .w, "carlsbad:w:minority"),
  ("d4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5 c6 Qc2 Be7 e3 Nbd7 Bd3 O-O Nge2 Re8 O-O-O", .w, "carlsbad:w:kingside"),
])
func variantFollowsTheKings(moves: String, me: ChessCore.Color, key: String) {
  #expect(planOf(at(moves), me)?.key == key)
}

@Test func isolatedPawnPlanTurnsOnTheQueens() {
  #expect(planOf("r2q1rk1/pp3ppp/4bn2/8/3P4/2N2N2/PP3PPP/R2Q1RK1 w - - 0 1", .w)?.key == "iqp:w:attack")
  let ending = planOf("r4rk1/pp3ppp/4bn2/8/3P4/2N2N2/PP3PPP/R4RK1 w - - 0 1", .w)!
  #expect(ending.key == "iqp:w:ending")
  #expect(ending.headline == "Trade off the weak pawn")
}

/// A step whose need is gone is not offered: the Carlsbad minority attack needs a b-pawn.
@Test func stepsNeedTheirPieces() {
  let fen = at("d4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5 c6 Qc2 Be7 e3 Nbd7 Bd3 O-O")
  #expect(planOf(fen, .w)!.steps.first?.text.hasPrefix("Minority attack") == true)
  let noBPawn = fen.replacingOccurrences(of: "PPQ2PPP", with: "P1Q2PPP")
  #expect(planOf(noBPawn, .w)!.steps.first?.text.hasPrefix("Minority attack") == false)
}

@Test func castleMarks() {
  let castled = at("e4 e5 Nf3 Nc6 Bc4 Bc5 O-O")
  #expect(mark(PlanStep(text: "", check: .castle(long: false)), castled, .w) == .done)
  #expect(mark(PlanStep(text: "", check: .castle(long: true)), castled, .w) == .gone)
  #expect(mark(PlanStep(text: "", check: .castle(long: false)), castled, .b) == nil)
  #expect(mark(PlanStep(text: "", check: .castle(long: false)), at("e4 e5 Ke2"), .w) == .gone)
}

@Test func tradeAndBishopMarks() {
  let fen = at("e4 e5 Nf3 Nc6 Bb5 a6 Bxc6 dxc6")
  #expect(mark(PlanStep(text: "", check: .trade(light: true)), fen, .w) == .gone)
  #expect(mark(PlanStep(text: "", check: .trade(light: true)), fen, .b) == .done)
  #expect(mark(PlanStep(text: "", check: .trade(light: false)), fen, .w) == nil)
  #expect(mark(PlanStep(text: "", check: .keepBishop(light: true)), fen, .w) == .gone)
  #expect(mark(PlanStep(text: "", check: .keepBishop(light: true)), fen, .b) == nil)
}

@Test func fileMarks() {
  let fen = "4k3/8/8/8/8/8/4P3/3RK3 w - - 0 1"
  #expect(mark(PlanStep(text: "", check: .file("d")), fen, .w) == .done)
  #expect(mark(PlanStep(text: "", check: .file("e")), fen, .w) == .gone)
  #expect(mark(PlanStep(text: "", check: .file("c")), fen, .w) == nil)
}

@Test func goalMarks() {
  let fen = at("d4 e5 dxe5")
  #expect(mark(PlanStep(text: "", goals: [Goal(piece: .p, to: "e5")]), fen, .w) == .done)
  #expect(mark(PlanStep(text: "", goals: [Goal(piece: .p, to: "d5")]), fen, .w) == .gone)
  #expect(mark(PlanStep(text: "", goals: [Goal(piece: .p, to: "e6")]), fen, .w) == nil)
  #expect(mark(PlanStep(text: "", goals: [Goal(piece: .q, to: "d5")]), "4k3/8/8/8/8/8/8/4K3 w - - 0 1", .w) == .gone)
  #expect(mark(PlanStep(text: "", needs: [.queens]), "4k3/8/8/8/8/8/8/4K3 w - - 0 1", .w) == .gone)
}

/// Castling short ends the Yugoslav plan with its castle-long step crossed, and the Classical plan takes over.
@Test func trailKeepsTheMarksOfAPlanThatLeft() {
  let trail = planTrail(walk("e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6 Be2 Bg7 O-O O-O"), .w)
  #expect(trail.current?.plan.key == "dragon:w:classical")
  let yugoslav = trail.earlier.first { $0.plan.key == "dragon:w:yugoslav" }
  #expect(yugoslav?.marks == [nil, .gone, nil])
  #expect(trail.earlier.first?.plan.key == "dragon:w:yugoslav")
}

/// A tick stays when the piece moves on.
@Test func trailTicksStick() {
  let moves = "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6 Be2 Bg7 O-O O-O Nd5 Nc6 Nxf6+ Bxf6"
  let trail = planTrail(walk(moves), .w)
  #expect(trail.current?.plan.key == "dragon:w:classical")
  #expect(trail.current?.marks.first == .done)
}

@Test func genericPlans() {
  let start = planOf(START_FEN, .b)!
  #expect(start.key == "generic:castle")
  #expect(start.steps.map(\.text) == ["Castle short: ...O-O"])
  let passer = planOf("4k3/8/8/3P4/8/8/2P5/4K3 w - - 0 1", .w)!
  #expect(passer.key == "generic:passer")
  #expect(passer.label == "Your passed pawn")
  #expect(passer.steps.first?.goals == [Goal(piece: .p, to: "d6")])
  #expect(planOf("4k3/2ppp3/8/8/8/8/2PPP3/4K3 w - - 0 1", .w) == nil)
}

@Test func firstMoves() {
  let fen = at("e4 e5 Nf3 Nc6 Bc4 Bc5")
  #expect(firstMove(PlanStep(text: "", check: .castle(long: false)), fen, .w) == "e1g1")
  #expect(firstMove(PlanStep(text: "", check: .castle(long: true)), fen, .w) == nil)
  #expect(firstMove(PlanStep(text: "", goals: [Goal(piece: .p, to: "d4")]), fen, .w) == "d2d4")
  #expect(firstMove(PlanStep(text: "", goals: [Goal(piece: .p, to: "d5")]), fen, .w) == "d2d3")
  #expect(firstMove(PlanStep(text: "", goals: [Goal(piece: .n, to: "d5")]), fen, .w) == "b1c3")
  #expect(firstMove(PlanStep(text: "", goals: [Goal(piece: .n, to: "d5")]), fen, .b) == nil)
}

/// A plan only takes over on your turn: one that fits only while they are to move never shows.
@Test func planChangesOnlyOnYourTurn() {
  let fens = walk("e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be2 Nc6 O-O e6")
  #expect(planOf(fens[fens.count - 2], .w)?.key.hasPrefix("generic:") == true)
  let trail = planTrail(fens, .w)
  #expect(trail.current?.plan.key == "scheveningen:w:classical")
  #expect(trail.earlier.first?.plan.key == "generic:castle")
  #expect(trail.earlier.first?.marks.first == .done)
  // Their turn: the plan stays, its marks move on.
  let waiting = planTrail(Array(fens.dropLast()), .w)
  #expect(waiting.current?.plan.key == "generic:castle")
  #expect(waiting.current?.marks.first == .done)
}
