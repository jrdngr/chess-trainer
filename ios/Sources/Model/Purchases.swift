import Foundation

/// What cash buys: the one-time unlock of the Pawn Shop's feature tree and endgame families, and pawn packs.
/// Nothing else is sold for money. The ids match the products in App Store Connect.
public enum CashProduct: String, CaseIterable, Sendable {
  case unlock = "com.jordangrace.chessplaybook.unlock"
  case pawns2000 = "com.jordangrace.chessplaybook.pawns2000"
  case pawns6000 = "com.jordangrace.chessplaybook.pawns6000"
  case pawns13000 = "com.jordangrace.chessplaybook.pawns13000"

  /// The pawns a pack holds; none for the unlock.
  public var pawns: Int {
    switch self {
    case .unlock: 0
    case .pawns2000: 2_000
    case .pawns6000: 6_000
    case .pawns13000: 13_000
    }
  }

  /// The packs, smallest first.
  public static let packs: [CashProduct] = [.pawns2000, .pawns6000, .pawns13000]
}

extension AppState {
  /// Whether every item the unlock gives is yours.
  public var ownsUnlockItems: Bool { UNLOCK_ITEMS.allSatisfy { unlocked.contains($0.id) } }

  /// A purchase from the App Store, credited once per transaction: the unlock makes the
  /// feature tree and the endgame families yours (not cosmetics or openings); a pack adds its pawns.
  /// An unlock seen again still grants every feature, so items added to the tree later come with
  /// it. The side picker starts on Either, as when bought with pawns. Returns whether it was credited.
  @discardableResult
  public mutating func credit(_ product: CashProduct, transaction: String) -> Bool {
    let fresh = credited.insert(transaction).inserted
    if product == .unlock {
      for item in UNLOCK_ITEMS where unlocked.insert(item.id).inserted {
        cashUnlocked.insert(item.id)
        if item.feature == .sidePicker { settings.selection.color = .either }
      }
      syncEndgameFamilies()
    }
    guard fresh else { return false }
    pawns += product.pawns
    logEvent(AppEvent(kind: "cash", count: product.pawns, picked: product.rawValue, text: "balance \(pawns)"))
    return true
  }

  /// The App Store took the unlock back (a refund): the features only it gave go. Features
  /// bought with pawns stay, and a refunded pack's pawns stay, since they may be spent.
  /// Returns whether anything was taken back.
  @discardableResult
  public mutating func revoke(_ product: CashProduct, transaction: String) -> Bool {
    guard product == .unlock, !cashUnlocked.isEmpty else { return false }
    unlocked.subtract(cashUnlocked)
    cashUnlocked = []
    holdToUnlocks()
    syncEndgameFamilies()
    logEvent(AppEvent(kind: "cash-revoked", picked: product.rawValue, text: "transaction \(transaction)"))
    return true
  }
}
