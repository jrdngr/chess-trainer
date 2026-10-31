import ChessCore

/// Starter sets: a ready-made Playbook for a new player, by style.
/// `src/model/starterSets.ts`; the sets are written out from `spec/constants.json`.

public enum SetSlot: String, Sendable, CaseIterable {
  case w, e4, d4
}

public struct StarterOpening: Equatable, Sendable {
  /// The book's move order for it, also its id in the opening tree.
  public var id: String
  /// What the set calls it, where the book's name is not what a beginner should read.
  public var label: String?
  init(id: String, label: String? = nil) {
    self.id = id
    self.label = label
  }
}

public struct StarterSet: Equatable, Sendable {
  public var id: String
  public var name: String
  public var description: String
  public var slots: [SetSlot: [StarterOpening]]
}

public let SLOT_LABELS: [SetSlot: String] = [.w: "As White", .e4: "Against 1.e4", .d4: "Against 1.d4"]
public let SLOT_COLOR: [SetSlot: Color] = [.w: .w, .e4: .b, .d4: .b]

public let STARTER_SETS: [StarterSet] = [
  StarterSet(
    id: "classical", name: "Classical",
    description: "Grab the center, develop, castle. Where most coaches start.",
    slots: [.w: [StarterOpening(id: "e4 e5 Nf3 Nc6 Bc4")], .e4: [StarterOpening(id: "e4 e5", label: "1...e5")], .d4: [StarterOpening(id: "d4 d5 c4 e6")]]),
  StarterSet(
    id: "system", name: "System",
    description: "The same setup nearly every game, so there's little to memorize.",
    slots: [.w: [StarterOpening(id: "d4 d5 Bf4", label: "London System"), StarterOpening(id: "d4 Nf6 Bf4", label: "London System")], .e4: [StarterOpening(id: "e4 c6")], .d4: [StarterOpening(id: "d4 d5 c4 c6")]]),
  StarterSet(
    id: "solid", name: "Solid",
    description: "Hard to crack. Fewer early fights, more long games.",
    slots: [.w: [StarterOpening(id: "d4 d5 c4")], .e4: [StarterOpening(id: "e4 e5", label: "1...e5"), StarterOpening(id: "e4 e5 Nf3 Nc6 Bb5 Nf6", label: "Berlin")], .d4: [StarterOpening(id: "d4 Nf6 c4 e6 Nc3 Bb4")]]),
  StarterSet(
    id: "aggressive", name: "Aggressive",
    description: "Unbalanced positions where you go after the king.",
    slots: [.w: [StarterOpening(id: "e4 e5 Nf3 Nc6 d4 exd4")], .e4: [StarterOpening(id: "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6", label: "Sicilian Dragon")], .d4: [StarterOpening(id: "d4 Nf6 c4 g6 Nc3 d5")]]),
  StarterSet(
    id: "fianchetto", name: "Fianchetto",
    description: "Bishops on the long diagonals, same setup whatever they play.",
    slots: [.w: [StarterOpening(id: "Nf3 d5 g3"), StarterOpening(id: "Nf3 Nf6 g3 g6", label: "King's Indian Attack")], .e4: [StarterOpening(id: "e4 d6")], .d4: [StarterOpening(id: "d4 Nf6 c4 g6 Nc3")]]),
  StarterSet(
    id: "mirror", name: "Mirror",
    description: "The c-pawn first with both colors, so White and Black share ideas.",
    slots: [.w: [StarterOpening(id: "c4")], .e4: [StarterOpening(id: "e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 g6", label: "Accelerated Dragon")], .d4: [StarterOpening(id: "d4 Nf6 c4 c5 d5 e6")]]),
]

/// Every opening a set holds, with the side that plays it.
public func setOpenings(_ set: StarterSet) -> [(id: String, color: Color, slot: SetSlot, label: String?)] {
  SetSlot.allCases.flatMap { slot in (set.slots[slot] ?? []).map { ($0.id, SLOT_COLOR[slot]!, slot, $0.label) } }
}

/// How many of your own moves lines hold: one per position a side answers.
public func countOwnMoves(_ lines: [(sans: [String], color: Color)]) -> Int {
  var own = Set<String>()
  for line in lines {
    let fens = walkSan(line.sans).fens
    for i in line.sans.indices where i < fens.count && fenTurn(fens[i]) == line.color {
      own.insert("\(line.color.rawValue) \(positionKey(fens[i]))")
    }
  }
  return own.count
}
