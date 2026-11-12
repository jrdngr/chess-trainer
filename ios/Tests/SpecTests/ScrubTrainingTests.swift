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

/// Undo after the run stopped at the edge of the book takes the edge back too.
@Test func undoAtTheEdgeOfTheBookClearsTheEdge() throws {
  let start = rep(.b, ["d4 Nf6 c4 g6 Nc3 Bg7 e4 d6"])
  let rows = growthRows([start], bookIndex, GrowthOptions(minShare: 1, maxPly: 18))
  let row = try #require(rows.first { $0.id == "rep_b#King's Pawn Game" })
  var session = measureBatch(beginGrowth(start, row), 18)
  (session, _) = choose(session, "c5", 8, ["c5"])
  #expect(session.phase == .answered)
  (session, _) = reachedEdge(session)
  #expect(session.edge)
  (session, _) = undo(session, start)
  #expect(session.phase == .hole)
  #expect(!session.edge)
}
