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

/// The slot a family fills, or nil for one no slot takes (a Black answer to anything but 1.e4 or 1.d4).
public func choiceSlot(_ family: [String]) -> ChoiceSlot? {
  switch family.count {
  case 1: return .w
  case 2: return family[0] == "e4" ? .e4 : family[0] == "d4" ? .d4 : nil
  default: return nil
  }
}

/// What "Recommend some openings" puts in: the Italian as White, 1...e5 and the Queen's Gambit Declined as Black.
public let RECOMMENDED_OPENINGS: [SeedOpening] = [
  SeedOpening(sans: ["e4", "e5", "Nf3", "Nc6", "Bc4"], color: .w),
  SeedOpening(sans: ["e4", "e5"], color: .b),
  SeedOpening(sans: ["d4", "d5", "c4", "e6"], color: .b),
]

/// One side's tree while choosing: every family a slot can take, none owned.
public func choosingMap(_ tree: OpeningTree, side: Color) -> [MapNode] {
  playbookMap(AppState(), tree, side: side).filter { root in
    side == .w || ["e4", "d4"].contains(root.line.first ?? "")
  }
}

extension AppState {
  /// "Recommend some openings": the recommended openings go in, and onboarding is done.
  public mutating func recommend(_ tree: OpeningTree) {
    onboarded(tree, RECOMMENDED_OPENINGS)
  }

  /// "Choose my openings" done: each picked family goes in with its seed line, free, and onboarding is done.
  /// A family no slot takes is left out.
  public mutating func choose(_ tree: OpeningTree, _ families: [[String]]) {
    let size = settings.movesPerFill
    onboarded(tree, families.compactMap { family in
      guard let slot = choiceSlot(family) else { return nil }
      return SeedOpening(sans: familySeed(tree, family, slot.color, size: size), color: slot.color)
    })
  }
}
