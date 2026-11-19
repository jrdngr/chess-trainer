import ChessCore

/// The Pawn Shop: what pawns buy, in a tree where an item needs the ones above it.

/// A feature a new player starts without.
public enum ShopFeature: String, Sendable, Codable, CaseIterable {
  /// White, Black or Either on Home; Black games start here.
  case sidePicker
  /// One lens each, in a chain: Pawns, Pieces, Kings, Eval. Plan, beside the lenses, is its own.
  case lensPawns, lensPieces, lensKings, lensEval, lensPlan
  /// Upgrades, each adding a part to its lens: structure names and endgame pawns to Pawns,
  /// square control and endgame pieces to Pieces, endgame kings to Kings, eval history to Eval.
  case lensStructure, lensEndgamePawns, lensControl, lensEndgamePieces, lensEndgameKings, lensEvalHistory
  /// Any Opening or one of yours on Home.
  case openingPicker
  /// Freeform runs.
  case freeform
  case middlegame
  /// Endgames, with Basic mates and From your games.
  case endgames
  /// Endgame families bought on their own, after Endgames.
  case endgamesPawn, endgamesRook

  /// The Endgames family a feature adds, if any.
  public var endgameFamily: String? {
    switch self {
    case .endgames: "mates"
    case .endgamesPawn: "pawn"
    case .endgamesRook: "rook"
    default: nil
    }
  }
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
  ShopItem("sidePicker", "Side picker", .features, 50, feature: .sidePicker, about: "Choose White, Black, or either before each game."),
  ShopItem("openingPicker", "Opening picker", .features, 100, needs: ["sidePicker"], feature: .openingPicker, about: "Choose which opening your games start in."),
  ShopItem("freeform", "Freeform", .features, 3_000, needs: ["openingPicker"], feature: .freeform, about: "Start games from move one and play any of your lines."),
  ShopItem("lensPawns", "Pawns lens", .features, 100, feature: .lensPawns, about: "Shows weak pawns, holes, and each side's best pawn break."),
  ShopItem("lensStructure", "Pawn structure", .features, 400, needs: ["lensPawns"], feature: .lensStructure, about: "The Pawns lens names the pawn structure."),
  ShopItem("lensEndgamePawns", "Endgame pawns", .features, 600, needs: ["lensPawns"], feature: .lensEndgamePawns, about: "In endgames, the Pawns lens shows each passed pawn's type and its square."),
  ShopItem("lensPieces", "Pieces lens", .features, 200, needs: ["lensPawns"], feature: .lensPieces, about: "Shows which pieces are active, passive or idle, and the worst piece."),
  ShopItem("lensControl", "Square control", .features, 600, needs: ["lensPieces"], feature: .lensControl, about: "The Pieces lens shows which side controls each square."),
  ShopItem("lensEndgamePieces", "Endgame pieces", .features, 800, needs: ["lensPieces"], feature: .lensEndgamePieces, about: "In endgames, the Pieces lens judges rooks, bad bishops and kings."),
  ShopItem("lensKings", "Kings lens", .features, 300, needs: ["lensPieces"], feature: .lensKings, about: "Shows how safe each king is, open lines to it, and missing shield pawns."),
  ShopItem("lensEndgameKings", "Endgame kings", .features, 1_000, needs: ["lensKings"], feature: .lensEndgameKings, about: "In endgames, the Kings lens shows key squares, the opposition and cut-off lines."),
  ShopItem("lensEval", "Eval lens", .features, 500, needs: ["lensKings"], feature: .lensEval, about: "Shows the engine's evaluation as a bar over the board."),
  ShopItem("lensEvalHistory", "Eval history", .features, 1_200, needs: ["lensEval"], feature: .lensEvalHistory, about: "The Eval lens charts the game and shows what your last move cost."),
  ShopItem("lensPlan", "Plan", .features, 1_000, feature: .lensPlan, about: "Shows a plan for the position."),
  ShopItem("middlegame", "Middlegame", .features, 8_000, feature: .middlegame, about: "Play middlegames that start from your openings."),
  ShopItem("endgames", "Endgames", .features, 5_000, feature: .endgames, about: "Practice the basic mates and endings from your games."),
  ShopItem("endgamesPawn", "King and pawn", .content, 5_000, needs: ["endgames"], feature: .endgamesPawn, about: "Key squares, the opposition and the square rule."),
  ShopItem("endgamesRook", "Rook endings", .content, 3_500, needs: ["endgames"], feature: .endgamesRook, about: "The Lucena and Philidor positions."),
  ShopItem("personalities", "Opponent personalities", .content, 5_000, needs: ["freeform"], about: "Opponents with their own play styles."),
  ShopItem("boards", "Board styles", .cosmetics, 3_000, each: true, about: "New board designs."),
  ShopItem("pieces", "Piece styles", .cosmetics, 3_000, each: true, about: "New piece sets."),
  ShopItem("decks", "Deck styles", .cosmetics, 3_000, each: true, about: "New card designs."),
  ShopItem("styles", "Full UI styles", .cosmetics, 10_000, each: true, about: "New looks for the whole app."),
  ShopItem("icons", "App icons", .cosmetics, 2_000, each: true, about: "New app icons."),
]

/// The features the $10 unlock gives: the whole feature shelf.
public var FEATURE_TREE: [ShopItem] { SHOP.filter { $0.shelf == .features } }

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

  /// A lens, Plan among them.
  public var isLens: Bool { self == .lensPlan || LensKind.allCases.contains { Self.lens($0) == self } }

  /// An upgrade that adds a part to a lens.
  public var isLensUpgrade: Bool { Self.lensUpgrades.contains(self) }

  public static let lensUpgrades: [ShopFeature] = [
    .lensStructure, .lensEndgamePawns, .lensControl, .lensEndgamePieces, .lensEndgameKings, .lensEvalHistory,
  ]
}

/// The lens upgrades that are yours: what each lens draws beyond its first part.
public struct LensParts: Equatable, Sendable {
  public var owned: Set<ShopFeature>
  public init(_ owned: Set<ShopFeature>) { self.owned = owned }
  /// Every part, as Analysis shows.
  public static let all = LensParts(Set(ShopFeature.lensUpgrades))
  public func has(_ upgrade: ShopFeature) -> Bool { owned.contains(upgrade) }

  /// Whether a lens draws its endgame marks in an endgame.
  public func endgame(_ kind: LensKind) -> Bool {
    switch kind {
    case .pawns: has(.lensEndgamePawns)
    case .pieces: has(.lensEndgamePieces)
    case .kings: has(.lensEndgameKings)
    case .eval: true
    }
  }
}

extension AppState {
  /// Whether a feature is yours.
  public func owns(_ feature: ShopFeature) -> Bool { unlocked.contains(feature.rawValue) }

  /// Whether a lens is yours.
  public func owns(lens kind: LensKind) -> Bool { owns(.lens(kind)) }

  /// The lens upgrades that are yours.
  public var lensParts: LensParts { LensParts(Set(ShopFeature.lensUpgrades.filter { owns($0) })) }

  /// Whether any lens is yours, Plan among them.
  public var ownsALens: Bool { ShopFeature.allCases.contains { $0.isLens && owns($0) } }

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
    // The side picker starts on Either, so Black comes up straight away.
    if item.feature == .sidePicker { settings.selection.color = .either }
    syncEndgameFamilies()
    logEvent(AppEvent(kind: "buy", count: item.price, picked: id, text: "balance \(pawns)"))
    return true
  }

  /// Every feature yours, for measuring and tests.
  public mutating func unlockAll() {
    for feature in ShopFeature.allCases { unlocked.insert(feature.rawValue) }
    syncEndgameFamilies()
  }

  /// Endgames plays the families you own: From your games comes with Endgames.
  public mutating func syncEndgameFamilies() {
    guard owns(.endgames) else { return }
    let owned = ShopFeature.allCases.filter { owns($0) }.compactMap(\.endgameFamily)
    endgames.families = Set(owned + ["games"])
  }

  /// Home's choices held to the features you own: White without the side picker,
  /// Any Opening without the opening picker, Drill without Freeform.
  public mutating func holdToUnlocks() {
    if !owns(.sidePicker) { settings.selection.color = .w }
    if !owns(.freeform) { settings.start = .drill }
    if !owns(.openingPicker) { settings.selection.opening = ANY_OPENING }
  }
}
