import Book
import ChessCore

/// Choosing openings at the start: Welcome's "Recommend some openings" puts in the
/// recommended ones, and "Choose my openings" fills three slots on the Playbook tree.
/// After that, new families come only from the tree.

/// The three families a new player starts with: one as White, and Black's answers to 1.e4 and 1.d4.
public enum ChoiceSlot: String, Sendable, CaseIterable {
  case w, e4, d4

  public var color: Color { self == .w ? .w : .b }
  public var label: String { [.w: "As White", .e4: "Against 1.e4", .d4: "Against 1.d4"][self]! }
}

/// The slot an opening fills: White's, or Black's against 1.e4 or 1.d4. Nil for one no slot takes.
public func choiceSlot(_ id: String) -> ChoiceSlot? {
  guard let opening = curatedOpening(id) else { return nil }
  if opening.color == .w { return .w }
  return ChoiceSlot(rawValue: opening.firstMove)
}

/// What "Recommend some openings" puts in: the Italian as White, 1...e5 and the Queen's Gambit Declined as Black.
public let RECOMMENDED_OPENINGS: [SeedOpening] = [
  SeedOpening(sans: ["e4", "e5", "Nf3", "Nc6", "Bc4"], color: .w),
  SeedOpening(sans: ["e4", "e5"], color: .b),
  SeedOpening(sans: ["d4", "d5", "c4", "e6"], color: .b),
]

/// One side's tree while choosing: every opening a slot can take, none owned.
public func choosingMap(_ tree: OpeningTree, side: Color) -> [MapNode] {
  playbookMap(AppState(), tree, side: side).filter { root in
    side == .w || ChoiceSlot(rawValue: root.line.first ?? "") != nil
  }
}

extension AppState {
  /// "Recommend some openings": the recommended openings go in, and onboarding is done.
  public mutating func recommend(_ tree: OpeningTree) {
    onboarded(tree, RECOMMENDED_OPENINGS)
  }

  /// "Choose my openings" done: each picked opening goes in with its seed lines, free, and onboarding is done.
  /// An opening no slot takes is left out.
  public mutating func choose(_ tree: OpeningTree, _ ids: [String]) {
    let size = settings.movesPerFill
    onboarded(tree, ids.compactMap(curatedOpening).filter { choiceSlot($0.id) != nil }.flatMap { opening in
      opening.roots.map { SeedOpening(sans: familySeed(tree, $0, opening.color, size: size), color: opening.color) }
    })
  }
}
