import ChessCore
import Game
import Model
import Testing

/// Welcome's "Recommend some openings": the recommended set goes in, and the first game is
/// Play's own, White on Drill, opening with the flashcards tip.
@MainActor @Test func recommendedOpeningsGoStraightIntoAWhiteGame() async throws {
  try await headless(everything: false) { app in
    #expect(app.screen == .welcome)
    await app.recommendOpenings()
    #expect(app.screen == .play)
    #expect(app.state.settings.onboarded)
    #expect(Set(app.state.playbookList.map(\.color)) == [.w, .b], "the set holds a White opening and Black's answers")
    let run = try #require(app.run)
    #expect(run.run.color == .w)
    #expect(run.round?.free == false)
    #expect(run.tip == .flashCards)
  }
}

/// Welcome's "Choose my openings": a family for each of the three slots goes in, and the first game starts.
@MainActor @Test func choosingYourOpeningsFillsThreeSlots() async throws {
  try await headless(everything: false) { app in
    await #expect(throws: HeadlessApp.Failure.self) { try await app.chooseOpenings(["london", "najdorf"]) }
    await #expect(throws: HeadlessApp.Failure.self) { try await app.chooseOpenings(["london", "najdorf", "french"]) }
    await #expect(throws: HeadlessApp.Failure.self) { try await app.chooseOpenings(["najdorf", "london", "slav"]) }
    try await app.chooseOpenings(["london", "najdorf", "slav"])
    #expect(app.screen == .play)
    #expect(app.state.ownedFamilies(.w).map(\.id) == ["london"])
    #expect(app.state.ownedFamilies(.b).map(\.id) == ["najdorf", "slav"])
  }
}

/// A first game's tips come at their triggers, one at a time, and each shows once:
/// the flashcards at the start, the prep bar after a prep move, pawns for the finished prep,
/// the ✓ on the first book move past it, then Next run.
@MainActor @Test func tipsShowAtTheirTriggersOnce() async throws {
  try await headless(everything: false) { app in
    await app.recommendOpenings()
    var shown: [GameTip] = []
    let note = { if let tip = app.run?.tip, shown.last != tip { shown.append(tip) } }
    note()
    while let run = app.run, run.live, let san = run.prepNow.first {
      try await app.move(san)
      note()
    }
    // Past the prep, the book's most played move pops with a ✓.
    let fen = try #require(app.fen)
    try await app.move(try #require(bookChoices(app.index, fen).first?.san))
    note()
    // The next move past the prep, with Next run showing.
    let past = try #require(app.fen)
    try await app.move(try #require(bookChoices(app.index, past).first?.san ?? legalMoves(past).first?.san))
    note()
    #expect(Array(shown.prefix(5)) == [.flashCards, .prepBar, .pawns, .prepDone, .nextRun], "finishing the prep pays pawns first")
    #expect(app.state.settings.seenTips.isSuperset(of: [.flashCards, .prepBar, .prepDone]))

    try await app.next()
    #expect(app.run?.tip == nil, "the flashcards tip has shown")
  }
}

/// A Play game ended by hand, not Next run, leaves its moves to look back on: the analysis tip shows, once.
@MainActor @Test func aGameEndedByHandShowsTheAnalysisTip() async throws {
  try await headless(everything: false) { app in
    await app.recommendOpenings()
    app.store.update { $0.settings.seenTips = Set(GameTip.allCases).subtracting([.analysis]) }
    try await app.move(try #require(app.run?.prepNow.first))
    await app.endRound()
    #expect(app.run?.tip == .analysis)
    #expect(app.state.settings.seen(.analysis))
  }
}
