import ChessCore
import Game
import Model
import Testing

/// Filling a recommendation in Growth: the sitting opens on the reply with no answer, offers the
/// book's answers, and Save Line puts the picked one in the Playbook, which drops the recommendation.
@MainActor @Test func growingARecommendationFillsIt() async throws {
  try await headless { app in
    try app.skipTutorial(starter: "classical")
    let gap = try #require(app.recommendations.first)
    try await app.grow(gap)
    #expect(app.screen == .growth)
    #expect(app.moves == gap.line)
    let answer = try #require(app.choices.first)
    #expect(applySan(app.fen!, answer) != nil)

    try await app.move(answer)
    let rep = { app.state.playbooks[gap.playbookId] }
    #expect(rep().flatMap { nodeAtLine($0, gap.line + [answer]) } == nil, "nothing is saved before Save Line")
    app.saveGrowth()
    #expect(rep().flatMap { nodeAtLine($0, gap.line + [answer]) } != nil)
    #expect(!app.recommendations.contains { $0.line == gap.line && $0.color == gap.color })
  }
}

/// Endgames: Practice starts the first ending to learn; giving away the win ends the round as a miss,
/// and resigning the next one counts as a miss too.
@MainActor @Test func endgameRoundsEndOnASlip() async throws {
  try await headless { app in
    try app.skipTutorial(starter: "classical")
    app.openEndgames()
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

/// A move that puts a piece where the opponent takes it for nothing.
private func freeCapture(_ fen: String) -> String? {
  legalMoves(fen).first { move in
    move.piece != .k && move.piece != .p
      && legalMoves(move.after).contains { $0.to == move.to }
      && !legalMoves(move.after).contains { reply in reply.to == move.to && legalMoves(reply.after).contains { $0.to == move.to } }
  }?.san
}

/// Middlegame: one of your lines is played out to a middlegame for you, then the run is yours from there.
@MainActor @Test func middlegameHandsOverAfterYourLine() async throws {
  try await headless { app in
    try app.skipTutorial(starter: "classical")
    await app.openMiddlegame()
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

/// Playing on from where a Growth sitting rests: the engine answers your move, Take back removes the pair,
/// and nothing goes into the Playbook or the history.
@MainActor @Test func playingOnFromALineRecordsNothing() async throws {
  try await headless { app in
    try app.skipTutorial(starter: "classical")
    let gap = try #require(app.recommendations.first { $0.color == .w })
    try await app.grow(gap)
    try await app.move(try #require(app.choices.first))
    let playbooks = app.state.playbooks
    try await app.playOnFromGrowth()
    #expect(app.screen == .playOn)
    let start = try #require(app.fen)

    try #require(fenTurn(start) == .w, "the sitting rests on White's move")

    try await app.move(try #require(goodMove(start)))
    #expect(app.moves.count == 2, "the engine answers")
    await app.undo()
    #expect(app.moves.isEmpty && app.fen == start)
    app.backToTheLine()
    #expect(app.screen == .growth)
    #expect(app.state.playbooks == playbooks && app.state.games.isEmpty)
  }
}
