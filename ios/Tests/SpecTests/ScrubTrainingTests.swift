import ChessCore
import Model
import Testing

/// Easy on a card relearning after a lapse never schedules it sooner than Good would.
@Test func easyAfterALapseKeepsTheInterval() {
  var card = createCard("id", "rep", "key", "fen", 0)
  card.stage = .review
  card.interval = 40
  card.testedRound = 0
  let lapsed = review(card, .again, round: 40)
  #expect(lapsed.stage == .learning)
  #expect(lapsed.interval == 20)

  let easy = review(lapsed, .easy, round: 42)
  let good = review(lapsed, .good, round: 42)
  #expect(easy.stage == .review)
  #expect(good.stage == .review)
  #expect(good.interval == 20)
  #expect(easy.interval == 20)
}
