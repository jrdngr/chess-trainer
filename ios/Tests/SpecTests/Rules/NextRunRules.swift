import ChessCore
import Foundation
import Model
import Testing

/// A Black Playbook with a deep Najdorf and a short Queen's Gambit Declined, after three Test runs.
private func najdorf() -> (AppState, AutoHistory) {
  var state = AppState()
  let id = state.ensurePlaybook(.b)
  state.addLine(id, line("e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5"), .fixed(.book))
  state.addLine(id, line("d4 d5 c4 e6"), .fixed(.book))
  var history = AutoHistory()
  history.focuses = [.test, .test, .test]
  return (state, history)
}

/// Play runs on a selection since anything was added.
private func playRuns(_ state: inout AppState, _ selection: Selection, _ count: Int) {
  let after = lastAddedAt(state.playbookList) + 1
  for i in 0..<count {
    state.recordGame(GameRecord(
      id: "g\(i)", mode: .play, at: after + Double(i), color: .w, picked: selection, opening: selection.opening, moves: ["e4"],
      result: "*", termination: "ended"))
  }
}

@Suite("docs/rules/next-run.md") struct NextRunRules {
  /// Rule 1: a first game with nothing saved is White from move one, in no opening yet.
  @Test func firstGameIsWhiteFromMoveOne() {
    let tree = openingTree(bookIndex)
    let round = firstGameRound(tree)
    #expect(round.pick.color == .w && round.pick.opening.id == ANY_OPENING)
    #expect(round.at == nil && round.grow == nil)
  }

  /// Rule 3: a new move is due once Play runs since the last addition reach Moves per fill.
  @Test func newMoveDueAfterMovesPerFillRuns() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    let id = state.ensurePlaybook(.w)
    state.addLine(id, line("e4 e5 Nf3"), .fixed(.book))
    for _ in 0..<4 { state.answered(id, START_FEN, "e4", .easy) }
    let selection = Selection(color: .w, opening: ANY_OPENING)
    #expect(state.settings.movesPerFill == 3)
    playRuns(&state, selection, 2)
    #expect(steerGap(state, tree, selection) == nil)
    playRuns(&state, selection, 3)
    #expect(steerGap(state, tree, selection) != nil)
  }

  /// Rule 4: Review for each opening at or below the selection with a move of yours, Test for the selection only.
  @Test func reviewBelowTestOnlyOnTheSelection() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    let id = state.ensurePlaybook(.b)
    state.addLine(id, line("d4 d5 c4 e6 Nc3 Nf6"), .fixed(.book))
    state.addLine(id, line("d4 d5 c4 c6 Nf3 Nf6"), .fixed(.book))
    let gambit = try #require(tree.byId["d4 d5 c4"])
    let selection = Selection(color: .b, opening: gambit.id)
    let found = candidates(recommendInput(state, tree, selection, AutoHistory()))
    #expect(found.filter { $0.focus == .test }.map(\.openingId) == [gambit.id])
    let reviews = Set(found.filter { $0.focus == .review }.map(\.openingId))
    #expect(reviews.contains(gambit.id) && reviews.contains("d4 d5 c4 e6") && reviews.contains("d4 d5 c4 c6"))
    #expect(found.allSatisfy { $0.need > 0 && $0.color == .b })
  }

  /// Rule 5: Review's need, from due and new positions.
  @Test func reviewNeedFromDueAndNew() {
    #expect(reviewNeed(24, 0, 8) == 0.45)
    #expect(reviewNeed(0, 4, 8) == 0.25)
    #expect(reviewNeed(0, 100, 8) == reviewNeed(0, 8, 8))
    #expect(reviewNeed(0, 0, 8) == 0)
  }

  /// Rule 5: a position your own games went off prep at is due.
  @Test func offPrepSlipsAreDue() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    let id = state.ensurePlaybook(.b)
    state.addLine(id, line("d4 d5 c4 e6"), .fixed(.book))
    for fen in walkSan(line("d4 d5 c4")).fens where fenTurn(fen) == .b {
      let san = fen == walkSan(line("d4")).fens[1] ? "d5" : "e6"
      state.answered(id, fen, san, .good)
    }
    let selection = Selection(color: .b, opening: ANY_OPENING)
    var input = recommendInput(state, tree, selection, AutoHistory())
    #expect(!candidates(input).contains { $0.focus == .review })
    input.repairs = [RepairRef(kind: "offprep", color: .b, fen: walkSan(line("d4 d5 c4")).fens[3])]
    #expect(candidates(input).contains { $0.focus == .review })
  }

  /// Rule 6: Test's need, from moves added and how long the stalest line was left.
  @Test func testNeedFromAddedAndLeft() {
    #expect(testNeed(0, true, 1) == 0.4)
    #expect(testNeed(0, false, 1) == 0.55)
    #expect(abs(testNeed(10, true, 1) - 0.6) < 1e-9)
    #expect(abs(testNeed(10, true, 0) - 0.6 * TEST_FLOOR) < 1e-9)
  }

  /// Rule 6: Test reads the old Play mode's runs, so a Play run changes nothing it weighs.
  @Test func testNeedIgnoresPlayRuns() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    state.addLine(state.ensurePlaybook(.b), line("d4 d5 c4 e6"), .fixed(.book))
    let selection = Selection(color: .b, opening: try #require(tree.byId["d4 d5 c4 e6"]).id)
    let before = candidates(recommendInput(state, tree, selection, AutoHistory())).first { $0.focus == .test }
    state.score = recordRound(
      state.score, tree,
      RoundRecord(mode: .run, openingId: selection.opening, color: .b, answered: 2, correct: 2, perfect: true, at: Env.now()))
    let after = candidates(recommendInput(state, tree, selection, AutoHistory())).first { $0.focus == .test }
    #expect(before?.need == after?.need && after?.lastAt == nil)
  }

  /// Rule 7: the score, and the brake on a focus played recently.
  @Test func scoreWeighsFreshnessDepthAndBrake() {
    let old = Candidate(focus: .review, openingId: "a", color: .w, need: 0.5, work: 1, lastAt: 1, level: 1)
    let new = Candidate(focus: .test, openingId: "b", color: .w, need: 0.5, work: 1, lastAt: 2, level: 0)
    let ranked = rank([old, new], [.test])
    #expect(ranked.first { $0.openingId == "a" }!.score == 0.5 * 3 * 0.6)
    #expect(ranked.first { $0.openingId == "b" }!.score == 0.5 * 1 * 0.5)
    #expect(ranked.map(\.openingId) == ["a", "b"])
  }

  /// Rule 8: a winning Review narrows into the variation holding most of its work.
  @Test func reviewNarrows() throws {
    #expect(narrowingBar(1) == 0.5)
    #expect(narrowingBar(2) == 2.0 / 3)
    let tree = openingTree(bookIndex)
    let (state, history) = najdorf()
    let pick = try #require(recommend(recommendInput(state, tree, Selection(color: .b, opening: ANY_OPENING), history)))
    #expect(pick.focus == .review)
    #expect(pick.opening.depth >= 2 && pick.opening.sans.starts(with: line("e4 c5")))
  }

  /// Rule 9: after a steered run the next picks stay on the selection.
  @Test func steeringPauses() throws {
    let tree = openingTree(bookIndex)
    var (state, history) = najdorf()
    state.settings.start = .drill
    history.steered = [true, false]
    let pick = try #require(recommend(recommendInput(state, tree, Selection(color: .b, opening: ANY_OPENING), history)))
    #expect(pick.opening.id == ANY_OPENING)
    history.steered = [true, false, false, false]
    let later = try #require(recommend(recommendInput(state, tree, Selection(color: .b, opening: ANY_OPENING), history)))
    #expect(later.opening.id != ANY_OPENING)
  }

  /// Rules 9 and 10: each run adds its focus and whether it was steered; Freeform never counts as steered.
  @Test func sessionRemembersRuns() throws {
    let tree = openingTree(bookIndex)
    let selection = Selection(color: .b, opening: ANY_OPENING)
    let deep = deepestNodeWithin(tree, tree.root, line("e4 c5 Nf3 d6"))
    var drill = firstGameRound(tree)
    drill.pick = Recommendation(focus: .review, opening: deep, color: .b)
    var free = drill
    free.free = true
    let history = afterRound(afterRound(AutoHistory(), drill, selection), free, selection)
    #expect(history.focuses == [.review, .review])
    #expect(history.steered == [true, false])
  }

  /// Rule 11: on Either the recommendation picks the side; a picked side is kept.
  @Test func eitherTakesTheRecommendedSide() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    state.addLine(state.ensurePlaybook(.b), line("e4 c5 Nf3 d6"), .fixed(.book))
    state.addLine(state.ensurePlaybook(.b), line("d4 d5 c4 e6"), .fixed(.book))
    #expect(nextRound(state, tree, Selection(color: .either, opening: ANY_OPENING), AutoHistory())?.pick.color == .b)
    #expect(nextRound(state, tree, Selection(color: .w, opening: ANY_OPENING), AutoHistory()) == nil)
  }

  /// Rule 2: on Any Opening with Black or Either, Black's first runs start at move one
  /// and grow Black's answer to 1.e4, then to 1.d4. A picked opening never does.
  @Test func blacksFirstRunsGrowItsFirstAnswers() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    state.addLine(state.ensurePlaybook(.w), line("e4 e5 Nf3 Nc6 Bb5"), .fixed(.book))
    let qgd = try #require(tree.byId["d4 d5 c4 e6"])
    #expect(blackFirstGap(state, tree, Selection(color: .b, opening: qgd.id)) == nil)
    #expect(blackFirstGap(state, tree, Selection(color: .w, opening: ANY_OPENING)) == nil)
    for color in [ColorChoice.b, .either] {
      let round = try #require(nextRound(state, tree, Selection(color: color, opening: ANY_OPENING), AutoHistory()))
      #expect(round.pick.color == .b && round.at == nil && round.aim == line("e4") && round.grow?.line == line("e4"))
    }
    state.addLine(state.ensurePlaybook(.b), line("e4 e5"), .fixed(.book))
    #expect(nextRound(state, tree, Selection(color: .b, opening: ANY_OPENING), AutoHistory())?.grow?.line == line("d4"))
    state.addLine(state.ensurePlaybook(.b), line("d4 d5"), .fixed(.book))
    #expect(blackFirstGap(state, tree, Selection(color: .b, opening: ANY_OPENING)) == nil)
  }

  /// Rule 3: a Play run never steers to a White first move you have no answer to, nor grows there:
  /// those gaps are Home's Recommendations, not a run's.
  @Test func runsDoNotGrowAtWhitesFirstMove() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    let id = state.ensurePlaybook(.b)
    state.addLine(id, line("e4 e5 Nf3 Nc6"), .fixed(.book))
    state.addLine(id, line("d4 d5 c4 e6"), .fixed(.book))
    let selection = Selection(color: .b, opening: ANY_OPENING)
    let after = lastAddedAt(state.playbookList) + 1
    for i in 0..<12 {
      state.recordGame(GameRecord(
        id: "g\(i)", mode: .play, at: after + Double(i), color: .b, picked: selection, opening: selection.opening, moves: ["e4"],
        result: "*", termination: "ended"))
    }
    let firstMoveGaps = selectionGaps(state, tree, selection).filter { $0.hole.path.isEmpty }
    #expect(firstMoveGaps.contains { $0.hole.san == "c4" })
    if let steered = steerGap(state, tree, selection) { #expect(!steered.hole.path.isEmpty) }
    let atC4 = try #require(growAtHole(state, tree, selection, color: .b, line: line("c4")))
    #expect(!atC4.yes)
  }

}
