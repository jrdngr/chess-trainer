import ChessCore
import Foundation
import Model
import Testing

/// A known card with `interval` runs, last asked in run `tested`.
private func known(_ interval: Double, tested: Int, ease: Double = 2.5) -> Card {
  var card = createCard("c", "p", "k", START_FEN, 0)
  card.stage = .review
  card.interval = interval
  card.ease = ease
  card.testedRound = tested
  return card
}

private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

@Suite("docs/rules/scheduling.md") struct SchedulingRules {
  /// Rule 1: a round that played a line counts a run; a growth sitting doesn't.
  @Test func finishedRunsCount() {
    let tree = openingTree(bookIndex)
    let run = RoundRecord(mode: .run, openingId: "", color: .w, answered: 1, correct: 1, perfect: false, at: 0, line: line("e4 e5"))
    let growth = RoundRecord(mode: .growth, openingId: "", color: .w, answered: 0, correct: 0, perfect: false, at: 0)
    let after = recordRound(recordRound(ScoreState(), tree, run), tree, growth)
    #expect(after.lineRounds == 1)
  }

  /// Rule 2: speed grades a right answer; the first answer a position gets counts as Good.
  @Test func speedGradesAndFirstAnswerIsGood() throws {
    #expect(gradeForTime(2.9) == .easy)
    #expect(gradeForTime(3) == .good)
    #expect(gradeForTime(7.9) == .good)
    #expect(gradeForTime(8) == .hard)
    var state = AppState()
    let id = state.ensurePlaybook(.w)
    state.addLine(id, line("e4"), .fixed(.book))
    state.answered(id, START_FEN, "e4", .easy)
    let card = try #require(state.cards[cardId(id, positionKey(START_FEN))])
    #expect(card.stage == .learning && card.step == 1)
  }

  /// Rule 3: two right answers to learn, one to relearn; Hard holds, Easy graduates.
  @Test func learningSteps() {
    let new = createCard("c", "p", "k", START_FEN, 0)
    let once = review(new, .good, round: 0)
    #expect(once.stage == .learning && once.step == 1)
    let twice = review(once, .good, round: 1)
    #expect(twice.stage == .review && twice.interval == 3)
    #expect(review(new, .hard, round: 0).stage == .learning && review(new, .hard, round: 0).step == 0)
    let easy = review(new, .easy, round: 0)
    #expect(easy.stage == .review && easy.interval == 12)
    var lapsed = new
    lapsed.stage = .learning
    lapsed.lapses = 1
    #expect(review(lapsed, .good, round: 0).stage == .review)
  }

  /// Rule 4: a due known card's interval grows by grade and ease, between 3 and 1095 runs.
  @Test func intervalsGrowInRuns() {
    #expect(review(known(10, tested: 0), .hard, round: 10).interval == 12)
    #expect(review(known(10, tested: 0), .good, round: 10).interval == 25)
    let easy = review(known(10, tested: 0), .easy, round: 10)
    #expect(close(easy.ease, 2.65) && close(easy.interval, 34.45))
    #expect(review(known(1000, tested: 0), .good, round: 1000).interval == 1095)
    #expect(review(known(10, tested: 0, ease: 1.3), .again, round: 10).ease == 1.3)
    #expect(close(review(known(10, tested: 0), .hard, round: 10).ease, 2.35))
  }

  /// Rule 5: a miss halves a known card's interval and sends it back to learning.
  @Test func missHalvesInterval() {
    let missed = review(known(10, tested: 0), .again, round: 10)
    #expect(missed.stage == .learning && missed.interval == 5 && missed.lapses == 1)
    #expect(review(missed, .good, round: 11).interval == 5)
    #expect(review(known(4, tested: 0), .again, round: 4).interval == 3)
  }

  /// Rule 6: asked before it is due, a known card keeps its interval.
  @Test func earlyKeepsInterval() {
    let early = review(known(10, tested: 5), .easy, round: 10)
    #expect(early.interval == 10 && early.testedRound == 10)
  }

  /// Rule 7: need is runs since asked over the gap; never asked is due.
  @Test func needInRuns() {
    var learning = createCard("c", "p", "k", START_FEN, 0)
    #expect(runNeed(learning, 50) == 1)
    learning.testedRound = 10
    #expect(runNeed(learning, 11) == 0.5)
    #expect(runNeed(known(10, tested: 0), 5) == 0.5)
    #expect(runNeed(known(0.4, tested: 0), 2) == 1)
  }

  /// Rule 8: staleness rises over 3 runs; a line's is its tail's tempered by its head's.
  @Test func stalenessOverThreeRuns() {
    let key = positionKey(START_FEN)
    let seen = Seen(at: [key: 4], round: 5)
    #expect(staleness(seen, key) == 1.0 / 3)
    #expect(staleness(seen, "never") == 1)
    #expect(staleness(Seen(at: [key: 5], round: 5), key) == 0)
    let white = rep(.w, ["e4 e5 Nf3", "e4 c5 Nf3"])
    let tip = white.nodes.values.first { $0.san == "Nf3" && pathTo(white, $0.id).map(\.san) == line("e4 e5 Nf3") }!.id
    let fresh = Seen(at: markSeen([:], line("e4"), 5), round: 5)
    #expect(lineStaleness(fresh, white, tip) == 0.5)
    #expect(lineStaleness(NOTHING_SEEN, white, tip) == 1)
  }

  /// Rule 9: weakness from the card and slips in your games.
  @Test func weaknessFromCardsAndSlips() {
    let id = cardId("p", "k")
    var card = known(10, tested: 0, ease: 2.0)
    card.id = id
    card.lapses = 1
    card.correct = 3
    card.incorrect = 1
    let slips = (0..<5).map { _ in Slip(kind: "offprep", playbookId: "p", key: "k", games: 1) }
    let weak = weaknessFromCards([id: card], slips, round: 10)
    #expect(close(weak("p", "k"), 1 + 6 + 1.2 + 1 + 1 + 0.5))
    #expect(weaknessFromCards([:], [], round: 0)("p", "k") == 1.5)
  }
}
