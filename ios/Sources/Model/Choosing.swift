import Book
import ChessCore

/// Choosing openings at the start: Welcome's "Recommend some openings" puts in the
/// recommended ones, and "Choose my openings" fills three slots on the Playbook tree, in order.
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

/// One slot's tree while choosing: every opening that slot can take, none owned.
/// White's is the whole White tree; each Black slot's is only the branch under its first move.
public func choosingMap(_ tree: OpeningTree, slot: ChoiceSlot) -> [MapNode] {
  playbookMap(AppState(), tree, side: slot.color).filter { root in
    slot == .w || root.line == [slot.rawValue]
  }
}

/// "Choose my openings" in progress: the slots are filled in order (White, then against 1.e4,
/// then against 1.d4), and the tree shows only the slot being filled.
public struct Choosing: Equatable, Sendable {
  /// The opening picked for each slot, by id.
  public private(set) var picks: [ChoiceSlot: String] = [:]
  /// The slot being filled, whose tree is shown.
  public private(set) var slot: ChoiceSlot = .w

  public init() {}

  /// Every slot is filled.
  public var done: Bool { ChoiceSlot.allCases.allSatisfy { picks[$0] != nil } }

  /// The picks in slot order, once every slot is filled.
  public var ids: [String]? { done ? ChoiceSlot.allCases.compactMap { picks[$0] } : nil }

  /// A slot can be opened once it is filled or is the first one still empty.
  public func canOpen(_ slot: ChoiceSlot) -> Bool {
    picks[slot] != nil || slot == ChoiceSlot.allCases.first { picks[$0] == nil }
  }

  /// Go back to a filled slot to change its pick, or on to the first empty one.
  public mutating func open(_ slot: ChoiceSlot) {
    if canOpen(slot) { self.slot = slot }
  }

  /// Pick an opening for the slot being filled, then move on to the first empty slot.
  /// An opening for any other slot is refused.
  @discardableResult
  public mutating func pick(_ id: String) -> Bool {
    guard choiceSlot(id) == slot else { return false }
    picks[slot] = id
    if let empty = ChoiceSlot.allCases.first(where: { picks[$0] == nil }) { slot = empty }
    return true
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
    let size = MOVES_PER_FILL
    onboarded(tree, ids.compactMap(curatedOpening).filter { choiceSlot($0.id) != nil }.flatMap { opening in
      opening.roots.map { SeedOpening(sans: familySeed(tree, $0, opening.color, size: size), color: opening.color) }
    })
  }
}
