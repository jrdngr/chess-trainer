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

/// "I know my openings" with a starter set lands on Home with that set's openings, one Playbook per side.
@MainActor @Test func knowingYourOpeningsSeedsTheStarterSet() async throws {
  try await headless(everything: false) { app in
    try app.knowMyOpenings(starter: "classical")
    #expect(app.screen == .home)
    #expect(app.state.playbookList.count == 2)
  }
}

/// A first game's tips come at their triggers, one at a time, and each shows once:
/// the flashcards at the start, the prep bar after a prep move, pawns for the finished prep,
/// and the ✓ on the first book move past it.
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
    #expect(Array(shown.prefix(4)) == [.flashCards, .prepBar, .pawns, .prepDone], "finishing the prep pays pawns first")
    #expect(app.state.settings.seenTips.isSuperset(of: [.flashCards, .prepBar, .prepDone]))

    try await app.next()
    #expect(app.run?.tip == nil, "the flashcards tip has shown")
  }
}
