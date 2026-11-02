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

/// A correct answer that is not the preferred one follows its own line.
@Test func aCorrectAlternativeFollowsItsOwnLine() throws {
  let r = rep(.w, ["e4 e5 Nf3 Nc6 Bc4", "e4 e5 Bc4 Nf6 d3", "e4 e5 d4"])
  let items = allItems([r])
  let item = try #require(items.first { $0.pathSans == ["e4", "e5"] })
  #expect(expectedSan(item) == "Nf3")
  let viaKnight = try #require(items.first { $0.pathSans == ["e4", "e5", "Nf3", "Nc6"] })
  let viaBishop = try #require(items.first { $0.pathSans == ["e4", "e5", "Bc4", "Nf6"] })

  #expect(followUpFor(item, items, r)?.cardId == viaKnight.cardId)
  #expect(followUpFor(item, items, r, played: "Nf3")?.cardId == viaKnight.cardId)
  #expect(followUpFor(item, items, r, played: "Bc4")?.cardId == viaBishop.cardId)
  // No reply prepared after d4, and h3 is not an answer.
  #expect(followUpFor(item, items, r, played: "d4") == nil)
  #expect(followUpFor(item, items, r, played: "h3") == nil)
}

/// Answers every position in `queue` up to `answers`, then optionally moves on.
private func drilled(_ queue: [TrainingItem], _ answers: Int, thenAdvance: Bool) throws -> DrillState {
  var state = DrillState(queue: queue)
  for i in 0..<answers {
    if i > 0 { state = advance(state) }
    let item = try #require(current(state))
    let san = try #require(expectedSan(item))
    let move = try #require(applySan(item.fen, san))
    state = answer(state, move, 1, nil, nil).state
  }
  return thenAdvance ? advance(state) : state
}

/// A sitting's round is credited to the color of the positions answered.
@Test func aDrillRoundTakesItsColorFromTheAnswers() throws {
  let white = allItems([rep(.w, ["e4 e5 Nf3"])])
  let black = allItems([rep(.b, ["e4 e5 Nf3 Nc6"])])
  try #require(white.count == 2 && black.count == 2)

  // Two Black answers, a White position up next.
  let mostlyBlack = try drilled([black[0], black[1], white[0]], 2, thenAdvance: true)
  #expect(drillRound(mostlyBlack, "")?.color == .b)

  // One each: the first answered decides, whatever comes next.
  let tied = try drilled([black[0], white[0], white[1]], 2, thenAdvance: false)
  #expect(drillRound(tied, "")?.color == .b)

  // Nothing left in the queue.
  let emptied = try drilled([black[0]], 1, thenAdvance: true)
  #expect(current(emptied) == nil)
  #expect(drillRound(emptied, "")?.color == .b)
}
