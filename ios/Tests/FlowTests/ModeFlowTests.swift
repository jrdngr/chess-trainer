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

/// Endgames: a stalemate you give ends a Win round as "Stalemate", not as a result given away.
@MainActor @Test func aStalemateYouGiveIsStalemate() async throws {
  try await headless { app in
    onboard(app)
    try app.openEndgames()
    app.store.update { $0.endgames.save(SavedEndgame(id: "stale", fen: "k7/8/1K6/8/8/8/8/2Q5 w - - 0 1", goal: .win, name: "Test", at: 0)) }
    let id = try #require(app.state.endgames.entries.first { $0.fen?.hasPrefix("k7/8/1K6") == true }).id
    try await app.playEnding(id)
    try await app.move("Qc7")
    let game = try #require(app.endgame?.game)
    #expect(game.outcome == .failure(text: "Stalemate"))
  }
}

/// Endgames: only a queen counts as queening: a rook promotion plays on.
@MainActor @Test func onlyAQueenIsQueened() async throws {
  try await headless { app in
    onboard(app)
    try app.openEndgames()
    app.store.update { $0.endgames.save(SavedEndgame(id: "rook", fen: "7k/4P3/8/8/8/8/8/K7 w - - 0 1", goal: .win, name: "Test", at: 0)) }
    let id = try #require(app.state.endgames.entries.first { $0.fen?.hasPrefix("7k/4P3") == true }).id
    try await app.playEnding(id)
    try await app.move("e8=R+")
    #expect(app.endgame?.game?.outcome == nil)
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

/// Middlegame: Next on a run still in play ends it where it stands and records it before the next begins.
@MainActor @Test func middlegameNextRecordsTheRunInPlay() async throws {
  try await headless { app in
    onboard(app)
    try await app.openMiddlegame()
    let games = app.state.games.count
    let ended = app.state.middlegame
    #expect(app.run?.finish == nil)
    try await app.next()
    #expect(app.state.games.count == games + 1)
    #expect(app.state.middlegame != ended)
  }
}
