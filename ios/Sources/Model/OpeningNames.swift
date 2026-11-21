import Book
import ChessCore
import Foundation
import Shared

/// "Najdorf" for "Najdorf Variation": the word every opening has is noise in a list.
public func shortName(_ label: String) -> String {
  for word in ["Defense", "Variation", "Opening", "Game"] where label.hasSuffix(" " + word) {
    let short = String(label.dropLast(word.count + 1))
    return short.isEmpty ? label : short
  }
  return label
}

/// The name a line shows under: the book's deepest name along it, as the picker spells it.
public func lineName(_ tree: OpeningTree, _ catalog: PickerCatalog, _ sans: [String]) -> String {
  if sans.isEmpty { return "Any Opening" }
  guard let node = tree.byId[sans.joined(separator: " ")] ?? deepestNodeAlong(tree, sans) else { return moveLabel(sans) }
  guard let entry = entryForNode(catalog, node) else { return node.name }
  return shortEntryLabel(entry)
}

/// "Sicilian: Najdorf" for a branch, the family's own name for a family.
func shortEntryLabel(_ entry: PickerEntry) -> String {
  let trail = entryTrail(entry).map { shortName($0.label) }
  return trail.count > 1 ? "\(trail[0]): \(trail[trail.count - 1])" : trail[0]
}

/// Every move your playbooks play, as position|san.
public func repMoves(_ reps: [Playbook]) -> Set<String> {
  Set(reps.flatMap { $0.nodes.values.map { "\($0.key)|\($0.san)" } })
}
