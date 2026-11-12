import Game
import Model
import Testing

/// What a session changes is saved: a relaunch on the same storage picks up where it left off.
@MainActor @Test func aRelaunchKeepsTheSave() async throws {
  let storage = MemoryStorage()
  let before = try await HeadlessApp.run(book: BOOK, storage: storage) { app in
    try app.skipTutorial(starter: "classical")
    await app.openPlay()
    await app.endRound()
    return app.state
  }
  #expect(before.games.count == 1)
  try await HeadlessApp.run(book: BOOK, storage: storage) { app in
    #expect(app.screen == .home)
    #expect(app.state.games == before.games)
    #expect(app.state.playbooks == before.playbooks)
  }
}

/// Profiles keep their own saves: a new one starts fresh, and switching back finds the first as it was.
@MainActor @Test func profilesKeepTheirOwnSaves() async throws {
  try await headless { app in
    try app.skipTutorial(starter: "classical")
    let first = app.store.profiles.active
    let playbooks = app.state.playbooks
    app.store.createProfile("Second")
    #expect(app.screen == .welcome)
    #expect(app.state.playbookList.isEmpty)
    app.store.switchProfile(first)
    #expect(app.screen == .home)
    #expect(app.state.playbooks == playbooks)
  }
}

/// The same seed plays the same game: a headless run replays exactly.
@MainActor @Test func theSameSeedReplaysTheSameGame() async throws {
  func game(_ seed: UInt32) async throws -> [String] {
    try await HeadlessApp.run(book: BOOK, seed: seed) { app in
      try app.skipTutorial(starter: "classical")
      try app.select(side: .b, start: .freeform)
      await app.openPlay()
      for _ in 0..<12 {
        guard let run = app.run, run.live, let move = run.prepNow.first ?? goodMove(run.run.fen) else { break }
        try await app.move(move)
      }
      return app.moves
    }
  }
  let first = try await game(7)
  #expect(first.count > 6)
  #expect(try await game(7) == first)
}
