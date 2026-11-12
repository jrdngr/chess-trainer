import ChessCore
import Model
import Testing

private func near(_ got: [Double], _ want: [Double]) -> Bool {
  got.count == want.count && zip(got, want).allSatisfy { abs($0 - $1) < 1e-12 }
}

/// The cap on lifted moves never pulls a prepared reply below its book share.
@Test func theFloorOnlyLifts() {
  // Six prepared replies under the floor: the five below 10% rise to it, the one at 10% keeps it.
  let capped = withFloor([30, 25, 10, 9, 8, 7, 6, 5], [false, false, true, true, true, true, true, true])
  #expect(near(capped, [0.3 * 0.4 / 0.55, 0.25 * 0.4 / 0.55, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1]))
  #expect(abs(capped.reduce(0, +) - 1) < 1e-12)

  // Eight prepared replies the cap cannot lift together all keep their book share.
  let even = withFloor([10, 10, 10, 10, 10, 10, 10, 10, 20], [true, true, true, true, true, true, true, true, false])
  #expect(near(even, [0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.2]))
}

/// After a lapse, Good walks the relearning steps, not the learning steps.
@Test func aLapsedCardRelearnsInOneStep() {
  var card = createCard("id", "rep", "key", "fen", 0)
  card.stage = .review
  card.interval = 40
  card.due = 0
  let lapsed = review(card, .again, 0)
  #expect(lapsed.delay == 10 * MINUTE)

  let hard = review(lapsed.card, .hard, lapsed.card.due)
  #expect(hard.card.stage == .learning)
  #expect(hard.delay == 10 * MINUTE)

  let good = review(lapsed.card, .good, lapsed.card.due).card
  #expect(good.stage == .review)
  #expect(good.interval == 20)

  let fresh = review(createCard("id", "rep", "key", "fen", 0), .good, 0).card
  #expect(fresh.stage == .learning)
}

