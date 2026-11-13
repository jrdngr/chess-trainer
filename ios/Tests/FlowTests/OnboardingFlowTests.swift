import ChessCore
import Game
import Model
import Testing

/// A new player from first launch: the welcome, the tutorial's games in order, then Play on their own.
@MainActor @Test func tutorialPlaysItsGamesThenHandsOverToPlay() async throws {
  try await headless { app in
    #expect(app.screen == .welcome)
    await app.recommendOpenings()
    #expect(app.screen == .play)
    var numbers: [Int] = []
    for _ in 0..<(TUTORIAL_GAMES + 2) {
      guard let run = app.run, let game = run.tutorialGame else { break }
      numbers.append(game.number)
      #expect(run.run.played.count <= 1, "a tutorial game starts from move one")
      try await playTutorialGame(app)
      #expect(app.run?.finish != nil)
      try await app.next()
    }
    #expect(numbers == Array(1...TUTORIAL_GAMES))
    #expect(app.run?.round != nil, "after the tutorial, rounds are Play's own")
  }
}

/// A tutorial game ended by a blunder stays on its board: the blunder tip, then a tip pointing at the X to go Home.
/// Every tutorial game where you can blunder does this, not only the one whose tips teach blunders.
@MainActor @Test(arguments: [3, 4, 5]) func tutorialBlunderPointsAtTheX(game number: Int) async throws {
  try await headless { app in
    await app.recommendOpenings()
    for _ in 1..<number {
      try await playTutorialGame(app)
      try await app.next()
    }
    let run = try #require(app.run)
    #expect(run.tutorialGame?.number == number)
    for _ in 0..<40 {
      if run.tip != nil { run.dismissTip() }
      if run.fill != nil, let answer = app.choices.first {
        try await app.move(answer)
        continue
      }
      guard run.live, let move = run.expected ?? run.prepNow.first else { break }
      try await app.move(move)
    }
    if run.tip != nil { run.dismissTip() }
    try await app.move(try #require(freeCapture(run.run.fen)))
    guard case .blunder = try #require(run.finish).how else {
      Issue.record("hanging a piece didn't end the game")
      return
    }
    #expect(run.tip == .blunder)
    run.dismissTip()
    #expect(run.tip == .goHome)
  }
}

/// Plays a tutorial game as it asks: its forced moves, the answers it offers while adding, then ends it when cued.
@MainActor private func playTutorialGame(_ app: HeadlessApp) async throws {
  for _ in 0..<60 {
    guard let run = app.run, run.live else { return }
    if run.tip != nil { run.dismissTip() }
    if run.endCued || run.nextRunShown { return await app.endRound() }
    if run.fill != nil, let answer = app.choices.first {
      try await app.move(answer)
    } else if let move = run.expected ?? run.prepNow.first ?? run.shownMove {
      try await app.move(move)
    } else {
      // Past the line: play on with a sound move until the game cues its end.
      try await app.move(try #require(goodMove(run.run.fen)))
    }
  }
  Issue.record("the tutorial game never ended")
}

/// Skipping the tutorial with a starter set lands on Home with that set's openings, one Playbook per side.
@MainActor @Test func skippingTheTutorialSeedsTheStarterSet() async throws {
  try await headless { app in
    try app.skipTutorial(starter: "classical")
    #expect(app.screen == .home)
    #expect(app.state.settings.tutorial == nil)
    let white = try #require(app.state.playbookList.first { $0.color == .w })
    #expect(nodeAtLine(white, ["e4", "e5", "Nf3", "Nc6", "Bc4"]) != nil)
    #expect(app.recommendations.isEmpty == false, "a starter set leaves replies to fill")
  }
}
