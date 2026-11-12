import ChessCore
import Model
import Testing
@testable import Engine

/// A step whose first move drops a piece waits; a sound one does not.
@Test func planChecksHoldBackALosingFirstMove() async {
  let fen = walkSan(["e4", "e5", "Nf3", "Nc6"]).fens.last!
  let steps = [
    PlanStep(text: "Knight to e5", goals: [Goal(piece: .n, to: "e5")]),
    PlanStep(text: "Knight to c3", goals: [Goal(piece: .n, to: "c3")]),
  ]
  #expect(firstMove(steps[0], fen, .w) == "f3e5")
  #expect(await PlanChecks.notYet(CaissaEngine(), fen, .w, steps, open: [true, true]) == [0])
}
