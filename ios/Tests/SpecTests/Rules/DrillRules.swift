import ChessCore
import Foundation
import Model
import Testing

/// Cards for a playbook's moves, each last asked in run `tested`, still being learned.
private func asked(_ items: [TrainingItem], _ tested: Int) -> [String: Card] {
  var out: [String: Card] = [:]
  for item in items {
    var card = createCard(item.cardId, item.playbookId, item.key, item.fen, 0)
    card.stage = .learning
    card.testedRound = tested
    out[item.cardId] = card
  }
  return out
}

@Suite("docs/rules/drill.md") struct DrillRules {

  /// Rule 1: the moves to the start are played for you, and the board opens on your move.
  @Test func startsAtOneOfYourMovesPlayedForYou() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    state.addLine(state.ensurePlaybook(.b), line("d4 d5 c4 e6 Nc3 Nf6"), .fixed(.book))
    let selection = Selection(color: .b, opening: try #require(tree.byId["d4 d5 c4 e6"]).id)
    let round = try #require(nextRound(state, tree, selection, AutoHistory()))
    let at = try #require(round.at)
    let begun = try #require(startRun(runOptions(round, state, tree, selection, seed: 1)))
    #expect(begun.state.run.played == at)
    #expect(fenTurn(begun.state.run.fen) == .b)
  }

  /// Rule 2: the move most due starts; a move never asked beats any asked one.
  @Test func mostDueStarts() throws {
    let items = allItems([rep(.b, ["d4 d5 c4 e6 Nc3 Nf6"])])
    #expect(items.map(\.pathSans.count) == [1, 3, 5])
    var cards = asked(items, 10)
    cards[items[1].cardId]!.testedRound = 8
    #expect(drillStart(items, cards, accuracy: nil, round: 11)?.item.cardId == items[1].cardId)
    cards[items[2].cardId] = nil
    #expect(drillStart(items, cards, accuracy: nil, round: 11)?.item.cardId == items[2].cardId)
  }

  /// Rule 3: with nothing due, the weakest move while prep misses, else the one closest to due.
  @Test func nothingDueWeakestWhilePrepMisses() throws {
    let items = allItems([rep(.b, ["d4 d5 c4 e6 Nc3 Nf6"])])
    var cards = asked(items, 10)
    cards[items[0].cardId]!.lapses = 2
    cards[items[2].cardId]!.testedRound = 9
    #expect(drillStart(items, cards, accuracy: 0.9, round: 10)?.item.cardId == items[0].cardId)
    #expect(drillStart(items, cards, accuracy: 0.97, round: 10)?.item.cardId == items[2].cardId)
    #expect(drillStart(items, cards, accuracy: nil, round: 10)?.item.cardId == items[2].cardId)
  }

  /// Rule 4: White's first move is never the start, even never asked; Black's first answer can be.
  @Test func neverWhitesFirstMove() {
    let white = allItems([rep(.w, ["e4 e5 Nf3"])])
    #expect(drillStart(white, [:], accuracy: nil, round: 0)?.item.pathSans == line("e4 e5"))
    #expect(drillStart(allItems([rep(.w, ["e4"])]), [:], accuracy: nil, round: 0) == nil)
    #expect(drillStart(allItems([rep(.b, ["e4 e5"])]), [:], accuracy: nil, round: 0)?.item.pathSans == line("e4"))
  }

  /// Rule 6: a gap run with none of your moves on the gap's line before the reply starts from move one and grows there.
  @Test func gapRunWithNothingOnItsLineGrowsFromMoveOne() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    let id = state.ensurePlaybook(.w)
    state.addLine(id, line("e4 e5 Nf3"), .fixed(.book))
    for _ in 0..<4 { state.answered(id, START_FEN, "e4", .easy) }
    let selection = Selection(color: .w, opening: ANY_OPENING)
    let after = lastAddedAt(state.playbookList) + 1
    for i in 0..<5 {
      state.recordGame(GameRecord(
        id: "g\(i)", mode: .play, at: after + Double(i), color: .w, picked: selection, opening: selection.opening, moves: ["e4"],
        result: "*", termination: "ended"))
    }
    let gap = try #require(steerGap(state, tree, selection))
    #expect(gap.path == line("e4"))
    let round = try #require(nextRound(state, tree, selection, AutoHistory()))
    #expect(round.at == nil)
    #expect(round.aim == gap.line)
    #expect(round.grow == gap)
  }

  /// Rule 5: with nothing of yours past White's move 1, Drill starts at move one and grows
  /// at the opening's gap, whatever the line's need.
  @Test func drillWithNothingToStartAtGrowsFromMoveOne() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    state.addLine(state.ensurePlaybook(.w), line("e4"), .fixed(.book))
    let round = try #require(nextRound(state, tree, Selection(color: .w, opening: ANY_OPENING), AutoHistory()))
    #expect(round.at == nil)
    let grow = try #require(round.grow)
    #expect(grow.hole.path == line("e4"))
    #expect(round.aim == grow.line)
  }

  /// Rule 6: once runs since the last new move pass the pace on a well known line,
  /// the next run heads for its gap and follows it to the reply.
  @Test func dueRunSteersToTheGap() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    let id = state.ensurePlaybook(.w)
    state.addLine(id, line("e4 c5 d4 cxd4 c3"), .fixed(.book))
    let fens = walkSan(line("e4 c5 d4 cxd4")).fens
    for _ in 0..<4 {
      state.answered(id, fens[0], "e4", .easy)
      state.answered(id, fens[2], "d4", .easy)
      state.answered(id, fens[4], "c3", .easy)
    }
    let selection = Selection(color: .w, opening: tree.byId["e4 c5 d4"]!.id)
    let quiet = try #require(nextRound(state, tree, selection, AutoHistory()))
    #expect(quiet.aim == nil)
    let after = lastAddedAt(state.playbookList) + 1
    for i in 0..<5 {
      state.recordGame(GameRecord(
        id: "g\(i)", mode: .play, at: after + Double(i), color: .w, picked: selection, opening: selection.opening, moves: ["e4"],
        result: "*", termination: "ended"))
    }
    #expect(runsSinceAdded(state.games, state.playbookList) == 5)
    let due = try #require(nextRound(state, tree, selection, AutoHistory()))
    #expect(due.aim == line("e4 c5 d4 cxd4 c3 dxc3"))
    // It starts at one of your moves on the gap's line, not from move one.
    let at = try #require(due.at)
    #expect([line("e4 c5"), line("e4 c5 d4 cxd4")].contains(at))
    let begun = try #require(startRun(runOptions(due, state, tree, selection, seed: 1)))
    #expect(begun.state.run.target == line("e4 c5 d4 cxd4 c3 dxc3"))
    let hole = try #require(growAtHole(state, tree, selection, color: .w, line: line("e4 c5 d4 cxd4 c3 dxc3")))
    #expect(hole.yes)
    #expect(hole.gap.kind == .tooShort)
  }


  /// Rules 1 and 2: with a move of yours to start at, Drill starts there, even with a prep that ends at the
  /// opening's own position.
  @Test func drillStartsAtOneOfYourMoves() throws {
    let tree = openingTree(bookIndex)
    var state = AppState()
    let id = state.ensurePlaybook(.b)
    state.addLine(id, line("d4 d5 c4 e6"), .fixed(.book))
    let opening = try #require(tree.byId["d4 d5 c4 e6"])
    let selection = Selection(color: .b, opening: opening.id)
    let first = try #require(nextRound(state, tree, selection, AutoHistory()))
    #expect([line("d4"), line("d4 d5 c4")].contains(first.at ?? []))
    for _ in 0..<4 {
      state.score = recordRound(
        state.score, tree,
        RoundRecord(mode: .run, openingId: opening.id, color: .b, answered: 2, correct: 2, perfect: true, at: Env.now()))
      let later = try #require(nextRound(state, tree, selection, AutoHistory()))
      #expect([line("d4"), line("d4 d5 c4")].contains(later.at ?? []))
    }
  }

}
