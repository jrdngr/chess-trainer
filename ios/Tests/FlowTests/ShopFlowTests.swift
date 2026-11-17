import ChessCore
import Game
import Model
import Testing

/// A new player starts on White Drill with Any Opening and every feature locked; pawns buy
/// them in the Pawn Shop, each opening the choice it stands for.
@MainActor @Test func aNewPlayerBuysFeaturesInTheShop() async throws {
  try await headless(everything: false) { app in
    try app.knowMyOpenings(starter: "classical")
    #expect(app.state.settings.selection == Selection(color: .w, opening: ANY_OPENING))
    #expect(app.state.settings.start == .drill)
    #expect(app.report().contains("Locked: Side picker"))
    #expect(throws: HeadlessApp.Failure.self) { try app.select(side: .b) }
    #expect(throws: HeadlessApp.Failure.self) { try app.openEndgames() }
    #expect(throws: HeadlessApp.Failure.self) { try app.buy("sidePicker") }

    app.store.update { $0.pawns = 60 }
    #expect(throws: HeadlessApp.Failure.self) { try app.buy("freeform") }
    try app.buy("sidePicker")
    #expect(app.state.pawns == 55)
    #expect(app.store.justUnlocked == .sidePicker, "Home shows it off next")
    try app.select(side: .b)
    #expect(app.state.settings.selection.color == .b)
    try app.select(side: .either)
    #expect(app.state.settings.selection.color == .either)

    try app.buy("openingPicker")
    #expect(app.state.pawns == 5)
    #expect(app.shopReport().contains("Freeform: 120, 115 short"))
    #expect(throws: HeadlessApp.Failure.self) { try app.buy("boards") }
  }
}

/// The Playbook tree: Home names the Next opening, and a locked opening unlocks now for a pawn,
/// which puts it in the Playbook.
@MainActor @Test func unlockingAnOpeningOnTheTree() async throws {
  try await headless { app in
    try app.knowMyOpenings(starter: "classical")
    let next = try #require(app.nextUp)
    #expect(app.report().contains("Next: \(next.name)"))
    func all(_ list: [MapNode]) -> [MapNode] { list.flatMap { [$0] + all($0.children) } }
    let locked = try #require(all(app.map(.w)).first { $0.line == ["e4", "c5"] })
    #expect(!locked.owned)
    #expect(throws: HeadlessApp.Failure.self) { try app.unlock(locked) }
    app.store.update { $0.pawns = 3 }
    try app.unlock(locked)
    #expect(app.state.pawns == 3 - UNLOCK_PRICE)
    #expect(all(app.map(.w)).contains { $0.line == ["e4", "c5"] && $0.owned })
  }
}
