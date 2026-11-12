import ChessCore
import Foundation
import Model
import Testing

/// A White Smith-Morra you know well, stopping at 3.c3.
private func morra() -> (AppState, String) {
  var state = AppState()
  let id = state.ensurePlaybook(.w)
  state.addLine(id, line("e4 c5 d4 cxd4 c3"), .fixed(.book))
  let fens = walkSan(line("e4 c5 d4 cxd4")).fens
  for _ in 0..<4 {
    state.answered(id, fens[0], "e4", .easy)
    state.answered(id, fens[2], "d4", .easy)
    state.answered(id, fens[4], "c3", .easy)
  }
  return (state, id)
}

@Suite("docs/rules/growth.md") struct GrowthRules {
  /// Rule 2: only prep followed without a miss marks where growing would start.
  @Test func cleanPrepMarksTheHole() throws {
    let tree = openingTree(bookIndex)
    let (state, _) = morra()
    let begun = try #require(startRun(StartOptions(steer: .lines, tree: tree, reps: state.playbookList, node: tree.root, color: .w)))
    let clean = beginSession(begun)
    #expect(prepRanOut(clean, bookIndex).prepEnd == clean.state.run.played)
    var missed = clean
    missed.state = playYours(clean.state, "d4", "e4")
    #expect(prepRanOut(missed, bookIndex).prepEnd == nil)
  }

  /// Rules 3 and 4: the hole's answer turns yes once the pace reaches 1 on a known line.
  @Test func holeAnswersYesOncePaceIsDue() throws {
    let tree = openingTree(bookIndex)
    var (state, _) = morra()
    let selection = Selection(color: .w, opening: try #require(tree.byId["e4 c5 d4"]).id)
    let hole = line("e4 c5 d4 cxd4 c3 dxc3")
    #expect(growAtHole(state, tree, selection, color: .w, line: hole)?.yes == false)
    let after = lastAddedAt(state.playbookList) + 1
    for i in 0..<3 {
      state.recordGame(GameRecord(
        id: "g\(i)", mode: .play, at: after + Double(i), color: .w, picked: selection, opening: "", moves: ["e4"],
        result: "*", termination: "ended"))
    }
    state.recordGame(GameRecord(
      id: "m", mode: .middlegame, at: after + 9, color: .w, picked: selection, opening: "", moves: ["e4"],
      result: "*", termination: "ended"))
    #expect(runsSinceAdded(state.games, state.playbookList) == 3)
    #expect(pace(runs: 3, size: 3) == 1)
    let found = try #require(growAtHole(state, tree, selection, color: .w, line: hole))
    #expect(found.yes && found.gap.line == hole)
  }

  /// Rule 5: a position's mastery is right answers, weighted toward fast ones.
  @Test func positionMasteryWeighsSpeed() {
    var card = createCard("c", "p", "k", START_FEN, 0)
    #expect(positionMastery(nil) == 0 && positionMastery(card) == 0)
    card.correct = 3
    card.incorrect = 1
    card.ease = 2.5
    #expect(positionMastery(card) == 0.75)
    card.ease = 1.3
    #expect(abs(positionMastery(card) - 0.45) < 1e-9)
  }

  /// Rule 6: g is the gap against the top one, at most 1.
  @Test func gapWeightAgainstTheTop() throws {
    let found = gaps([rep(.w, ["e4 c5 d4 cxd4 c3", "d4 d5 c4"])], bookIndex, tree: openingTree(bookIndex))
    let top = try #require(found.first)
    let last = try #require(found.last)
    #expect(gapWeight(top, top: top) == 1)
    #expect(gapWeight(last, top: top) == last.importance / top.importance)
    #expect(gapWeight(top, top: last) == 1)
  }

  /// Rule 8: a move added mid-run isn't graded and counts in the book's color.
  @Test func addedMovesAreNotGraded() throws {
    let tree = openingTree(bookIndex)
    let (state, _) = morra()
    let begun = try #require(startRun(StartOptions(steer: .lines, tree: tree, reps: state.playbookList, node: tree.root, color: .w)))
    var session = beginSession(begun)
    session.state.run.fen = START_FEN
    session.state.run.played = []
    let step = playAdded(session, "e4")
    #expect(step.session.answers.isEmpty && step.session.state.misses.isEmpty)
    #expect(step.session.bookTo == 1)
  }

  /// Rule 1: 1.d4 Nf6 is answered by more than half of strong players, so with 1.d4
  /// d5 2.c4 and the Smith-Morra kept, it leads the list. A line that stops
  /// (the Morra after 3.c3) is one gap, at its most played reply.
  @Test func gapsRankByReachAndShare() throws {
    let tree = openingTree(bookIndex)
    let found = gaps([rep(.w, ["e4 c5 d4 cxd4 c3", "d4 d5 c4"])], bookIndex, tree: tree)
    let first = try #require(found.first)
    #expect(first.line == line("d4 Nf6"))
    #expect(first.kind == .noAnswer)
    let morra = found.filter { $0.path == line("e4 c5 d4 cxd4 c3") }
    #expect(morra.count == 1)
    #expect(morra.first?.hole.san == "dxc3")
    #expect(morra.first?.kind == .tooShort)
    #expect(morra.first.map { $0.missing >= 1 } == true)
    // Every gap is common enough at its position.
    #expect(found.allSatisfy { $0.share >= GAP_SHARE })
    // And met often enough to be worth recommending.
    #expect(found.allSatisfy { $0.importance >= GAP_MIN_IMPORTANCE })
    #expect(zip(found, found.dropFirst()).allSatisfy { $0.importance >= $1.importance })
  }

  /// Rule 1: Black's first-move replies are breadth; a line that ends on White's
  /// move is depth.
  @Test func blackGapsKinds() {
    let tree = openingTree(bookIndex)
    let found = gaps([rep(.b, ["e4 e5", "d4 d5"])], bookIndex, tree: tree)
    #expect(found.contains { $0.line == line("Nf3") && $0.kind == .noAnswer })
    #expect(found.contains { $0.line == line("e4 e5 Nf3") && $0.kind == .tooShort })
    #expect(!found.contains { $0.line == line("e4 e5 Nf3 Nc6") })
  }

  /// Rule 5: a line's mastery is the average over your moves on it; a move never asked counts as 0.
  @Test func masteryCountsUnaskedAsWeak() {
    var state = AppState()
    let id = state.ensurePlaybook(.w)
    state.addLine(id, line("e4 c5 d4 cxd4 c3"), .fixed(.book))
    let rep = state.playbooks[id]!
    #expect(lineMastery(rep, state.cards, line("e4 c5 d4 cxd4 c3")) == 0)
    #expect(lineMastery(rep, state.cards, []) == 1)
    let fens = walkSan(line("e4 c5 d4 cxd4")).fens
    for _ in 0..<3 {
      state.answered(id, fens[0], "e4", .good)
      state.answered(id, fens[2], "d4", .good)
      state.answered(id, fens[4], "c3", .good)
    }
    let known = lineMastery(state.playbooks[id]!, state.cards, line("e4 c5 d4 cxd4 c3"))
    #expect(known > 0.5)
  }

  /// Rule 7: a fill stops at its size, or where the book stops naming the line.
  @Test func fillStopsAtSizeOrNamedEnd() {
    let morra = line("e4 c5 d4 cxd4 c3 dxc3 Nxc3")
    #expect(!fillEnds(bookIndex, morra, added: 1, size: 3))
    #expect(fillEnds(bookIndex, morra, added: 3, size: 3))
    let end = namedEnd(bookIndex, morra)!
    let past = morra + ["Nc6", "Nf3", "d6", "Bc4", "e6", "O-O", "Nf6", "Qe2"]
    #expect(end.ply <= past.count)
    #expect(fillEnds(bookIndex, past, added: 1, size: 5))
  }

}
