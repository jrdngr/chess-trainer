import Foundation
import Model
import Testing

private func state(pawns: Int, owning: [String] = []) -> AppState {
  var s = AppState()
  s.pawns = pawns
  s.unlocked = Set(owning)
  return s
}

@Suite("docs/rules/shop.md") struct ShopRules {
  /// Rule 1: the features, their prices and what each needs first.
  @Test func featuresAndTheirPrerequisites() throws {
    let features = SHOP.filter { $0.feature != nil }.map { "\($0.id) \($0.price) \($0.needs.joined(separator: ","))" }
    #expect(features == [
      "sidePicker 5 ", "lensPawns 10 ", "lensPieces 20 lensPawns", "lensKings 30 lensPieces", "lensEval 60 lensKings",
      "openingPicker 50 sidePicker", "freeform 120 openingPicker", "recommendations 150 freeform",
      "middlegame 300 lensPieces", "endgames 300 ",
    ])
  }

  /// Rule 2: buying takes the price, and only when every item it needs is yours.
  @Test func buyingNeedsPawnsAndPrerequisites() throws {
    var s = state(pawns: 100)
    let early = s.buy("openingPicker")
    #expect(!early)
    #expect(s.status(try #require(shopItem("openingPicker"))) == .locked)
    let side = s.buy("sidePicker")
    #expect(side && s.pawns == 95 && s.owns(.sidePicker))
    let again = s.buy("sidePicker")
    #expect(!again, "an item is bought once")
    let opening = s.buy("openingPicker")
    #expect(opening && s.pawns == 45)
    var poor = state(pawns: 4)
    #expect(poor.status(try #require(shopItem("sidePicker"))) == .short(1))
    let bought = poor.buy("sidePicker")
    #expect(!bought && poor.pawns == 4)
  }

  /// Rule 3: content and cosmetics are shown but not for sale.
  @Test func placeholdersAreNotForSale() throws {
    var s = state(pawns: 1000, owning: ShopFeature.allCases.map(\.rawValue))
    for item in SHOP where item.feature == nil {
      #expect(s.status(item) == .soon)
      let bought = s.buy(item.id)
      #expect(!bought)
    }
    #expect(s.pawns == 1000)
  }

  /// Rule 4: Home's choices stay within what you own.
  @Test func homeHoldsToTheFeaturesYouOwn() {
    var s = state(pawns: 0)
    s.settings.selection = Selection(color: .either, opening: "e4 c5")
    s.settings.start = .freeform
    s.holdToUnlocks()
    #expect(s.settings.selection == Selection(color: .w, opening: ANY_OPENING))
    #expect(s.settings.start == .drill)

    var side = state(pawns: 0, owning: ["sidePicker"])
    side.settings.selection = Selection(color: .b, opening: "")
    side.holdToUnlocks()
    #expect(side.settings.selection.color == .b)
    side.settings.selection.color = .either
    side.holdToUnlocks()
    #expect(side.settings.selection.color == .w, "Either comes with Freeform")
  }
}
