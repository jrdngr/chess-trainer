import ChessCore

/// The Pawn Shop: what pawns buy, in a tree where an item needs the ones above it.

/// A feature a new player starts without.
public enum ShopFeature: String, Sendable, Codable, CaseIterable {
  /// White or Black on Home; Black games start here.
  case sidePicker
  /// One lens each, in a chain: Pawns, Pieces, Kings, Eval.
  case lensPawns, lensPieces, lensKings, lensEval
  /// Any Opening or one of yours on Home.
  case openingPicker
  /// Freeform runs, and Either side.
  case freeform
  case recommendations
  case middlegame
  case endgames
}

/// The shelf an item sits on.
public enum ShopShelf: String, Sendable, CaseIterable { case features, content, cosmetics }

/// One thing in the shop.
public struct ShopItem: Equatable, Sendable, Identifiable {
  public var id: String
  public var name: String
  public var shelf: ShopShelf
  public var price: Int
  /// The items to own first.
  public var needs: [String]
  /// The feature it unlocks; nil for an item that can't be bought yet.
  public var feature: ShopFeature?
  /// "each": one of several alike, shown as one.
  public var each: Bool
  /// What it does, in a sentence or two, on its sheet.
  public var about: String
  public init(
    _ id: String, _ name: String, _ shelf: ShopShelf, _ price: Int, needs: [String] = [], feature: ShopFeature? = nil,
    each: Bool = false, about: String
  ) {
    self.id = id
    self.about = about
    self.name = name
    self.shelf = shelf
    self.price = price
    self.needs = needs
    self.feature = feature
    self.each = each
  }
}

/// Everything in the shop, in its tree's order.
public let SHOP: [ShopItem] = [
  ShopItem("sidePicker", "Side picker", .features, 5, feature: .sidePicker, about: "Play Black as well as White. Pick your side on Home before each game."),
  ShopItem("lensPawns", "Pawns lens", .features, 10, feature: .lensPawns, about: "Hold it for hints on the pawns: weak ones, passed ones and the pushes that matter. Plan comes with it."),
  ShopItem("lensPieces", "Pieces lens", .features, 20, needs: ["lensPawns"], feature: .lensPieces, about: "Hold it to see loose pieces and the ones under attack."),
  ShopItem("lensKings", "Kings lens", .features, 30, needs: ["lensPieces"], feature: .lensKings, about: "Hold it to see how safe each king is."),
  ShopItem("lensEval", "Eval lens", .features, 60, needs: ["lensKings"], feature: .lensEval, about: "Hold it to see the engine's score for the position."),
  ShopItem("openingPicker", "Opening picker", .features, 50, needs: ["sidePicker"], feature: .openingPicker, about: "Play one of your openings instead of all of them. Pick it on Home."),
  ShopItem("freeform", "Freeform", .features, 120, needs: ["openingPicker"], feature: .freeform, about: "Games from move one where you can play any of your lines. Also lets you play either side."),
  ShopItem("recommendations", "Recommendations", .features, 150, needs: ["freeform"], feature: .recommendations, about: "The gaps in your Playbook, most important first, on Home. Tap one to fill it."),
  ShopItem("middlegame", "Middlegame", .features, 300, needs: ["lensPieces"], feature: .middlegame, about: "Play on from the end of your openings, with a plan for the position."),
  ShopItem("endgames", "Endgames", .features, 300, feature: .endgames, about: "Practice the endings every player needs: win the won ones, hold the drawn ones."),
  ShopItem("guides", "Opening guides", .content, 100, needs: ["openingPicker"], each: true, about: "The ideas and plans behind one of your openings."),
  ShopItem("personalities", "Opponent personalities", .content, 200, needs: ["freeform"], about: "Opponents with their own style: attackers, defenders, tricksters."),
  ShopItem("boards", "Board styles", .cosmetics, 150, each: true, about: "A new look for the board."),
  ShopItem("pieces", "Piece styles", .cosmetics, 150, each: true, about: "A new set of pieces."),
  ShopItem("decks", "Deck styles", .cosmetics, 150, each: true, about: "A new look for your opening cards."),
  ShopItem("styles", "Full UI styles", .cosmetics, 400, each: true, about: "A new look for the whole app."),
  ShopItem("icons", "App icons", .cosmetics, 100, each: true, about: "A new icon for your home screen."),
]

public func shopItem(_ id: String) -> ShopItem? { SHOP.first { $0.id == id } }

/// Where an item stands for you.
public enum ShopStatus: Equatable, Sendable {
  case owned
  /// Yours to buy now.
  case buyable
  /// Its price is more than your pawns, by this many.
  case short(Int)
  /// An item it needs is not yours yet.
  case locked
  /// Not for sale yet.
  case soon
}

extension ShopFeature {
  /// The feature that unlocks a lens.
  public static func lens(_ kind: LensKind) -> ShopFeature {
    switch kind {
    case .pawns: .lensPawns
    case .pieces: .lensPieces
    case .kings: .lensKings
    case .eval: .lensEval
    }
  }

  public var isLens: Bool { LensKind.allCases.contains { Self.lens($0) == self } }
}

extension AppState {
  /// Whether a feature is yours.
  public func owns(_ feature: ShopFeature) -> Bool { unlocked.contains(feature.rawValue) }

  /// Whether a lens is yours.
  public func owns(lens kind: LensKind) -> Bool { owns(.lens(kind)) }

  /// Whether any lens is yours.
  public var ownsALens: Bool { LensKind.allCases.contains { owns(lens: $0) } }

  public func status(_ item: ShopItem) -> ShopStatus {
    if unlocked.contains(item.id) { return .owned }
    if item.feature == nil { return .soon }
    if !item.needs.allSatisfy(unlocked.contains) { return .locked }
    return pawns >= item.price ? .buyable : .short(item.price - pawns)
  }

  /// Buy an item: its price comes off the balance. Returns whether it was bought.
  @discardableResult
  public mutating func buy(_ id: String) -> Bool {
    guard let item = shopItem(id), status(item) == .buyable else { return false }
    pawns -= item.price
    unlocked.insert(id)
    return true
  }

  /// Every feature yours, as an existing profile gets.
  public mutating func unlockAll() {
    for feature in ShopFeature.allCases { unlocked.insert(feature.rawValue) }
  }

  /// Home's choices held to the features you own: White without the side picker,
  /// Any Opening without the opening picker, Drill and one side without Freeform.
  public mutating func holdToUnlocks() {
    if !owns(.sidePicker) { settings.selection.color = .w }
    if !owns(.freeform) {
      settings.start = .drill
      if settings.selection.color == .either { settings.selection.color = .w }
    }
    if !owns(.openingPicker) { settings.selection.opening = ANY_OPENING }
  }
}
