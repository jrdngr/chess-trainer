import ChessCore
import Game
import Model
import Testing

/// Endgames: Practice starts the first ending to learn; giving away the win ends the round as a miss,
/// and resigning the next one counts as a miss too.
@MainActor @Test func endgameRoundsEndOnASlip() async throws {
  try await headless { app in
    onboard(app)
    try app.openEndgames()
    try await app.practice()
    let game = try #require(app.endgame?.game)
    #expect(game.phase == .playing && game.myTurn)
    let rounds = app.state.endgames.rounds

    let hang = try #require(freeCapture(game.fen))
    try await app.move(hang)
    guard case .failure = try #require(game.outcome) else {
      Issue.record("giving the queen away didn't end the round")
      return
    }
    #expect(game.phase == .over)
    #expect(app.state.endgames.rounds == rounds + 1)
  }
}

/// Middlegame: one of your lines is played out to a middlegame for you, then the run is yours from there.
@MainActor @Test func middlegameHandsOverAfterYourLine() async throws {
  try await headless { app in
    onboard(app)
    try await app.openMiddlegame()
    #expect(app.screen == .middlegame)
    let run = try #require(app.run)
    let handoff = try #require(run.handoff)
    #expect(run.intro == .done)
    #expect(run.run.played == handoff.line)
    let rep = try #require(app.state.playbookList.first { $0.color == run.run.color })
    let yours = Array(handoff.line.prefix(handoff.prep))
    #expect(!yours.isEmpty && nodeAtLine(rep, yours) != nil, "the handoff starts with a line from your Playbook")
    #expect(run.myTurn && run.live)
  }
}
