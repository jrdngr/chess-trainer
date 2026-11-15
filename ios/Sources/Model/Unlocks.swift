import ChessCore

/// The Pawn Shop: what pawns buy, in a tree where an item needs the ones above it.

/// A feature a new player starts without.
public enum ShopFeature: String, Sendable, Codable, CaseIterable {
  /// White or Black on Home; Black games start here.
  case sidePicker
  case lenses
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
  public init(_ id: String, _ name: String, _ shelf: ShopShelf, _ price: Int, needs: [String] = [], feature: ShopFeature? = nil, each: Bool = false) {
    self.id = id
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
  ShopItem("sidePicker", "Side picker", .features, 5, feature: .sidePicker),
  ShopItem("lenses", "Lenses", .features, 15, feature: .lenses),
  ShopItem("openingPicker", "Opening picker", .features, 50, needs: ["sidePicker"], feature: .openingPicker),
  ShopItem("freeform", "Freeform", .features, 120, needs: ["openingPicker"], feature: .freeform),
  ShopItem("recommendations", "Recommendations", .features, 150, needs: ["freeform"], feature: .recommendations),
  ShopItem("middlegame", "Middlegame", .features, 300, needs: ["lenses"], feature: .middlegame),
  ShopItem("endgames", "Endgames", .features, 300, feature: .endgames),
  ShopItem("guides", "Opening guides", .content, 100, needs: ["openingPicker"], each: true),
  ShopItem("personalities", "Opponent personalities", .content, 200, needs: ["freeform"]),
  ShopItem("boards", "Board styles", .cosmetics, 150, each: true),
  ShopItem("pieces", "Piece styles", .cosmetics, 150, each: true),
  ShopItem("decks", "Deck styles", .cosmetics, 150, each: true),
  ShopItem("styles", "Full UI styles", .cosmetics, 400, each: true),
  ShopItem("icons", "App icons", .cosmetics, 100, each: true),
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

extension AppState {
  /// Whether a feature is yours.
  public func owns(_ feature: ShopFeature) -> Bool { unlocked.contains(feature.rawValue) }

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
