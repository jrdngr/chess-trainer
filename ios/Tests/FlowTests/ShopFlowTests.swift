import ChessCore
import Game
import Model
import Testing

/// A new player starts on White Drill with Any Opening and every feature locked; pawns buy
/// them in the Pawn Shop, each opening the choice it stands for.
@MainActor @Test func aNewPlayerBuysFeaturesInTheShop() async throws {
  try await headless(everything: false) { app in
    try app.skipTutorial(starter: "classical")
    #expect(app.state.settings.selection == Selection(color: .w, opening: ANY_OPENING))
    #expect(app.state.settings.start == .drill)
    #expect(app.report().contains("Locked: Side picker"))
    #expect(throws: HeadlessApp.Failure.self) { try app.select(side: .b) }
    #expect(throws: HeadlessApp.Failure.self) { try app.openEndgames() }
    #expect(app.recommendations.isEmpty)
    #expect(throws: HeadlessApp.Failure.self) { try app.buy("sidePicker") }

    app.store.update { $0.pawns = 60 }
    #expect(throws: HeadlessApp.Failure.self) { try app.buy("freeform") }
    try app.buy("sidePicker")
    #expect(app.state.pawns == 55)
    #expect(app.store.justUnlocked == .sidePicker, "Home shows it off next")
    try app.select(side: .b)
    #expect(app.state.settings.selection.color == .b)
    #expect(throws: HeadlessApp.Failure.self) { try app.select(side: .either) }

    try app.buy("openingPicker")
    #expect(app.state.pawns == 5)
    #expect(app.shopReport().contains("Freeform: 120, 115 short"))
    #expect(throws: HeadlessApp.Failure.self) { try app.buy("boards") }
  }
}
