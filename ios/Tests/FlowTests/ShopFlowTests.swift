import ChessCore
import Game
import Model
import Testing

/// A new player starts on White Drill with Any Opening and every feature locked; pawns buy
/// them in the Pawn Shop, each opening the choice it stands for.
@MainActor @Test func aNewPlayerBuysFeaturesInTheShop() async throws {
  try await headless(everything: false) { app in
    onboard(app)
    #expect(app.state.settings.selection == Selection(color: .w, opening: ANY_OPENING))
    #expect(app.state.settings.start == .drill)
    #expect(app.report().contains("Locked: Side picker"))
    #expect(throws: HeadlessApp.Failure.self) { try app.select(side: .b) }
    #expect(throws: HeadlessApp.Failure.self) { try app.openEndgames() }
    #expect(throws: HeadlessApp.Failure.self) { try app.buy("sidePicker") }

    app.store.update { $0.pawns = 1_200 }
    #expect(throws: HeadlessApp.Failure.self) { try app.buy("freeform") }
    try app.buy("sidePicker")
    #expect(app.state.pawns == 1_000)
    #expect(app.store.justUnlocked == .sidePicker, "Home shows it off next")
    try app.select(side: .b)
    #expect(app.state.settings.selection.color == .b)
    try app.select(side: .either)
    #expect(app.state.settings.selection.color == .either)

    try app.buy("openingPicker")
    #expect(app.state.pawns == 0)
    #expect(app.shopReport().contains("Freeform: 3000, 3000 short"))
    #expect(throws: HeadlessApp.Failure.self) { try app.buy("boards") }
  }
}

/// The Playbook tree: Home names the Next opening, and openings you don't have are for sale on
/// a rising ladder; a swap token trades one for another.
@MainActor @Test func buyingAnOpeningOnTheTree() async throws {
  try await headless { app in
    onboard(app)
    let next = try #require(app.nextUp)
    #expect(app.report().contains("Next: \(next.name)"))
    func all(_ list: [MapNode]) -> [MapNode] { list.flatMap { [$0] + all($0.children) } }
    let london = try #require(all(app.map(.w)).first { $0.family == "london" })
    #expect(london.state == .forSale(price: 2_000))
    #expect(throws: HeadlessApp.Failure.self) { try app.buyFamily(london) }
    app.store.update { $0.pawns = 5_000 }
    try app.buyFamily(london)
    #expect(app.state.pawns == 3_000)
    #expect(all(app.map(.w)).contains { $0.family == "london" && $0.owned })
    let english = try #require(all(app.map(.w)).first { $0.family == "english" })
    #expect(english.state == .forSale(price: 2_500), "the next one costs 500 more")
    #expect(all(app.map(.b)).contains { $0.family == "najdorf" && $0.forSale })

    try app.swapFamily("london", for: english)
    #expect(app.state.ownedFamilies(.w).map(\.id) == ["italian", "english"])
    #expect(app.state.families.tokens == 0)
    #expect(app.state.pawns == 3_000, "a swap is free")
  }
}
