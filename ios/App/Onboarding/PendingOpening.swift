import ChessCore
import Model

/// An opening waiting to go in, as the ready screen and the picked list show it.
struct PendingOpening: Equatable {
  var key: String
  var name: String
  var color: ChessCore.Color
  var moves: Int
  /// Its own moves: starred once it goes in.
  var sans: [String]
  /// The lines played on the board that put it in, for an opening from the board.
  var lines: [OnboardingLine]?
}

/// One line a side, however many openings it put in.
func boardLines(_ pending: [PendingOpening]) -> [OnboardingLine] {
  var order: [String] = []
  var lines: [String: OnboardingLine] = [:]
  for line in pending.flatMap({ $0.lines ?? [] }) {
    let key = "\(line.color.rawValue) \(line.sans.joined(separator: " "))"
    if lines[key] == nil { order.append(key) }
    lines[key] = line
  }
  return order.map { lines[$0]! }
}

func seedsOf(_ pending: [PendingOpening]) -> [SeedOpening] {
  pending.map { SeedOpening(sans: $0.sans, color: $0.color) }
}

/// The Playbook as the held openings would make it.
func onboardedState(_ state: AppState, _ tree: OpeningTree, _ pending: [PendingOpening]) -> AppState {
  var next = state
  next.onboarded(tree, seedsOf(pending), boardLines(pending))
  return next
}

/// A key for what is held, to tell when lists built from it are stale.
func pendingKey(_ pending: [PendingOpening]) -> String {
  pending.map { "\($0.color.rawValue)\($0.key)" }.joined(separator: "|")
}

/* ── starter sets ── */

/// An opening's name as a set shows it: the set's own label, else the book's, shortened.
func setOpeningName(_ tree: OpeningTree, _ id: String, _ label: String?) -> String {
  if let label { return label }
  return tree.byId[id].map { shortLabel($0.name) } ?? id
}

/// A slot's openings by name, the same name once.
func slotNames(_ tree: OpeningTree, _ set: StarterSet, _ slot: SetSlot) -> [String] {
  var seen = Set<String>()
  return (set.slots[slot] ?? []).map { setOpeningName(tree, $0.id, $0.label) }.filter { seen.insert($0).inserted }
}

/// Your moves a set puts in, all of them or one slot's.
func setMoves(_ set: StarterSet, _ slot: SetSlot? = nil) -> Int {
  let openings = setOpenings(set).filter { slot == nil || $0.slot == slot }
  return countOwnMoves(openings.map { (sans: line($0.id), color: $0.color) })
}

/// A set's openings, one by one, as they wait to go in.
func pendingFromSet(_ tree: OpeningTree, _ set: StarterSet) -> [PendingOpening] {
  setOpenings(set).map { o in
    let sans = line(o.id)
    return PendingOpening(
      key: o.id, name: setOpeningName(tree, o.id, o.label), color: o.color, moves: countOwnMoves([(sans: sans, color: o.color)]), sans: sans)
  }
}

/// A set's slots in order.
func slotsOf(_ set: StarterSet) -> [SetSlot] {
  SetSlot.allCases.filter { set.slots[$0] != nil }
}
