import ChessCore
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
      "sidePicker 50 ", "openingPicker 100 sidePicker", "freeform 3000 openingPicker",
      "lensPawns 100 ", "lensStructure 400 lensPawns", "lensEndgamePawns 600 lensPawns",
      "lensPieces 200 lensPawns", "lensControl 600 lensPieces", "lensEndgamePieces 800 lensPieces",
      "lensKings 300 lensPieces", "lensEndgameKings 1000 lensKings",
      "lensEval 500 lensKings", "lensEvalHistory 1200 lensEval",
      "lensPlan 1000 ", "middlegame 8000 ", "endgames 5000 ", "endgamesPawn 5000 endgames", "endgamesRook 3500 endgames",
    ])
    #expect(FEATURE_TREE.reduce(0) { $0 + $1.price } == 22_850, "the $10 unlock's worth")
  }

  /// Rule 1: Endgames plays Basic mates and From your games; King and pawn and Rook endings are bought apart.
  @Test func endgameFamiliesAreBoughtApart() {
    var s = state(pawns: 20_000)
    _ = s.buy("endgames")
    #expect(Set(s.endgames.entries.map(\.family)) == ["mates"])
    _ = s.buy("endgamesRook")
    #expect(Set(s.endgames.entries.map(\.family)) == ["mates", "rook"])
    #expect(s.pawns == 20_000 - 5_000 - 3_500)
  }

  /// Rule 2: buying takes the price, and only when every item it needs is yours.
  @Test func buyingNeedsPawnsAndPrerequisites() throws {
    var s = state(pawns: 2_000)
    let early = s.buy("openingPicker")
    #expect(!early)
    #expect(s.status(try #require(shopItem("openingPicker"))) == .locked)
    let side = s.buy("sidePicker")
    #expect(side && s.pawns == 1_950 && s.owns(.sidePicker))
    #expect(s.settings.selection.color == .either, "the side picker starts on Either")
    let again = s.buy("sidePicker")
    #expect(!again, "an item is bought once")
    let opening = s.buy("openingPicker")
    #expect(opening && s.pawns == 1_850)
    var poor = state(pawns: 49)
    #expect(poor.status(try #require(shopItem("sidePicker"))) == .short(1))
    let bought = poor.buy("sidePicker")
    #expect(!bought && poor.pawns == 49)
  }

  /// Rule 3: content and cosmetics are shown but not for sale.
  @Test func placeholdersAreNotForSale() throws {
    var s = state(pawns: 100_000, owning: ShopFeature.allCases.map(\.rawValue))
    for item in SHOP where item.feature == nil {
      #expect(s.status(item) == .soon)
      let bought = s.buy(item.id)
      #expect(!bought)
    }
    #expect(s.pawns == 100_000)
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
    #expect(side.settings.selection.color == .either, "Either comes with the side picker")
  }

  /// Rule 6: the unlock gives the feature tree and nothing else; packs add pawns; a transaction pays once.
  @Test func cashBuysTheTreeAndPawns() {
    var s = AppState()
    #expect(!s.ownsFeatureTree)
    let unlocked = s.credit(.unlock, transaction: "1")
    #expect(unlocked && s.ownsFeatureTree && s.pawns == 0)
    #expect(!s.owns(.endgamesPawn) && !s.owns(.endgamesRook), "endgame families are bought with pawns")
    #expect(s.ownedFamilies(.w).isEmpty, "no openings")
    s.unlocked.remove("lensEvalHistory")
    let again = s.credit(.unlock, transaction: "1")
    #expect(!again && s.owns(.lensEvalHistory), "an unlock seen again still grants items added to the tree since")
    let pack = s.credit(.pawns6000, transaction: "2")
    #expect(pack && s.pawns == 6_000)
    let twice = s.credit(.pawns6000, transaction: "2")
    #expect(!twice && s.pawns == 6_000, "a transaction is credited once")
    _ = s.credit(.pawns13000, transaction: "3")
    #expect(s.pawns == 19_000)
    #expect(CashProduct.pawns13000.pawns < FEATURE_TREE.map(\.price).reduce(0, +), "$10 of pawns buys less than the unlock")
  }

  /// Rule 5: a lens draws its first part; each upgrade adds its own.
  @Test func lensUpgradesAddTheirParts() {
    let none = LensParts([])
    // An isolated queen pawn: the Pawns lens names it only with Pawn structure.
    var iqp = START_FEN
    for san in "e4 c6 d4 d5 exd5 cxd5 c4 Nf6 Nc3 e6 Nf3 Be7 cxd5 Nxd5".split(separator: " ") {
      iqp = applySan(iqp, String(san))!.after
    }
    let named = lensMarks(.pawns, iqp, .w)
    #expect(named.caption != nil)
    #expect(lensMarks(.pawns, iqp, .w, parts: none).caption == nil)
    #expect(lensMarks(.pawns, iqp, .w, parts: none).tags == named.tags, "tags and holes are the lens's first part")
    #expect(lensMarks(.pawns, iqp, .w, parts: none).dots == named.dots)
    // Square control: the Pieces lens's tints.
    #expect(lensMarks(.pieces, iqp, .w).tints?.isEmpty == false)
    #expect(lensMarks(.pieces, iqp, .w, parts: none).tints == nil)
    #expect(lensMarks(.pieces, iqp, .w, parts: none).rings == lensMarks(.pieces, iqp, .w).rings)

    // A king and pawn ending: each endgame upgrade brings its lens's endgame marks.
    let ending = "8/8/4k3/8/4P3/4K3/8/8 w - - 0 1"
    #expect(lensMarks(.pawns, ending, .w).boxes?.isEmpty == false)
    let plainPawns = lensMarks(.pawns, ending, .w, parts: none)
    #expect(plainPawns.boxes == nil && plainPawns.letters == nil && plainPawns.tags == lensMarks(.pawns, ending, .w).tags)
    #expect(lensMarks(.kings, ending, .w, parts: LensParts([.lensEndgameKings])) == lensMarks(.kings, ending, .w))
    #expect(lensMarks(.kings, ending, .w, parts: none) == kingsLens(ending, .w))
    #expect(lensMarks(.pieces, ending, .w, parts: LensParts([.lensControl])) == piecesLens(ending, .w))
  }

  /// Rule 5: the parts that are yours.
  @Test func lensPartsFollowWhatYouOwn() {
    var s = state(pawns: 10_000)
    #expect(s.lensParts == LensParts([]))
    for id in ["lensPawns", "lensStructure", "lensPieces", "lensControl"] { _ = s.buy(id) }
    #expect(s.lensParts == LensParts([.lensStructure, .lensControl]))
    let early = s.buy("lensEvalHistory")
    #expect(!early, "an upgrade needs its lens")
  }
}
