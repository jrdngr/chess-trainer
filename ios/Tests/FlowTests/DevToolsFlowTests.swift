import Foundation
import Game
import Model
import Testing

/// docs/rules/dev-tools.md rule 1: a change from the developer tools logs nothing, settings among it,
/// and pawns added by hand don't touch the streak.
@MainActor @Test func devChangesLogNothing() async throws {
  try await headless(everything: false) { app in
    onboard(app)
    let events = app.state.events
    let streak = app.state.pawnStreak
    app.store.devUpdate {
      $0.devAddPawns(10_000)
      $0.devSetOwned("freeform", true)
      $0.devReplayWelcome()
    }
    #expect(app.state.events == events)
    #expect(app.state.pawnStreak == streak)
    #expect(app.state.pawns == 10_000)

    app.store.devSetOpening("london", owned: true)
    let added = app.state.events
    #expect(added.count > events.count, "an opening put in logs its moves added")
    app.store.devSetOpening("london", owned: false)
    #expect(!app.state.ownsFamily("london"))
    #expect(app.state.events == added, "taking one out logs nothing")
  }
}

/// Rule 8: a build without the developer tools ignores what a build with them left on the device.
@MainActor @Test func aBuildWithoutTheToolsIgnoresDevSettings() async throws {
  let storage = MemoryStorage()
  var kept = DevSettings()
  kept.daysAhead = 3
  kept.ignoreStoreUnlock = true
  try storage.write("dev.json", JSONEncoder().encode(kept))
  let store = AppStore(storage: storage)
  store.devAllowed = false
  await store.load(book: nil)
  #expect(store.dev.daysAhead == 0 && !store.dev.ignoreStoreUnlock)
}

/// Rule 8: the clock's days ahead belong to the device: kept over a relaunch and on every profile.
@MainActor @Test func theClockBelongsToTheDevice() async throws {
  let storage = MemoryStorage()
  try await HeadlessApp.run(book: BOOK, storage: storage) { app in
    app.store.travel(days: 3)
    app.store.createProfile("Second")
    #expect(app.store.dev.daysAhead == 3)
  }
  try await HeadlessApp.run(book: BOOK, storage: storage) { app in
    #expect(app.store.dev.daysAhead == 3)
    app.store.travel(days: -2)
    #expect(app.store.dev.daysAhead == 0)
  }
}

/// Rule 9: with the unlock ignored, one the App Store hands back isn't credited and one bought is;
/// forgetting credited purchases lets a transaction credit again.
@MainActor @Test func theStoreUnlockCanBeIgnored() async throws {
  try await headless(everything: false) { app in
    onboard(app)
    app.store.setDev { $0.ignoreStoreUnlock = true }
    #expect(!app.store.credit(.unlock, transaction: "1", bought: false))
    #expect(!app.state.ownsUnlockItems)
    #expect(app.store.credit(.unlock, transaction: "1", bought: true))
    #expect(app.state.ownsUnlockItems)

    #expect(app.store.credit(.pawns2000, transaction: "2", bought: false), "packs are never ignored")
    #expect(!app.store.credit(.pawns2000, transaction: "2"))
    app.store.devUpdate { $0.credited = [] }
    #expect(app.store.credit(.pawns2000, transaction: "2"))
    #expect(app.state.pawns == 4_000)
  }
}

/// Rule 10: a new profile opens on Welcome; Duplicate copies the profile in use to a new one,
/// which opens, and the original stays as it was.
@MainActor @Test func duplicateCopiesTheProfile() async throws {
  try await headless(everything: false) { app in
    onboard(app)
    app.store.devUpdate { $0.devAddPawns(500) }
    let first = app.store.profiles.active
    let before = app.state
    app.store.duplicateProfile()
    #expect(app.store.profiles.active != first)
    #expect(app.store.profiles.activeProfile.name == "Main copy")
    #expect(app.state == before)

    app.store.devUpdate { $0.devAddPawns(100) }
    app.store.switchProfile(first)
    #expect(app.state.pawns == 500)

    app.store.createProfile("")
    #expect(app.screen == .welcome)
  }
}

/// Rule 11: a save exported and pasted into another profile reads back the same; a paste that
/// isn't a save at this version changes nothing.
@MainActor @Test func aSaveGoesOutAndBackIn() async throws {
  try await headless(everything: false) { app in
    onboard(app)
    app.store.devUpdate { $0.devAddPawns(1_234) }
    let saved = try #require(app.store.exportSave())
    let before = app.state
    app.store.createProfile("Fresh")
    #expect(app.store.importSave(saved))
    #expect(app.state == before)
    #expect(app.screen == .home)

    var old = before
    old.version = SAVE_VERSION - 1
    #expect(!app.store.importSave(try JSONEncoder().encode(old)))
    #expect(!app.store.importSave(Data("not a save".utf8)))
    #expect(app.state == before)
  }
}

/// Rule 12: Replay Welcome opens Welcome on the profile in use and keeps its Playbook.
@MainActor @Test func replayWelcomeKeepsThePlaybook() async throws {
  try await headless(everything: false) { app in
    onboard(app)
    let playbooks = app.state.playbooks
    app.store.devUpdate { $0.devReplayWelcome() }
    #expect(app.screen == .welcome)
    #expect(app.state.playbooks == playbooks)
  }
}
