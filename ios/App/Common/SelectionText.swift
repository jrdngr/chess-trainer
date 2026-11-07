import Model

/// A name without the word every opening has: "Najdorf" for "Najdorf
/// Variation", "King's Indian" for "King's Indian Defence". `shortLabel`.
func shortLabel(_ label: String) -> String {
  for suffix in [" Defence", " Variation", " Opening", " Game"] where label.hasSuffix(suffix) {
    let cut = String(label.dropLast(suffix.count))
    return cut.isEmpty ? label : cut
  }
  return label
}

/// Where a node sits, as short names from its family down.
func selectionTrail(_ tree: OpeningTree, _ catalog: PickerCatalog, _ openingId: String) -> [String] {
  if openingId == ANY_FAVORITE { return ["Any Favorite"] }
  let node = nodeById(tree, openingId)
  if node.depth == 0 { return ["Any Playbook"] }
  let trail = entryForNode(catalog, node).map { entryTrail($0).map { shortLabel($0.label) } } ?? [node.name]
  guard node.custom else { return trail }
  // A line played past its name: the name, then the moves it goes on with.
  let named = node.parentId.flatMap { tree.byId[$0] }
  let from = named.map { n in n.sans.enumerated().allSatisfy { node.sans.indices.contains($0.offset) && node.sans[$0.offset] == $0.element } ? n.sans.count : 0 } ?? 0
  return from > 0 ? trail + [moveRange(node.sans, from)] : trail
}

/// "6.e3 e6": the moves of a line from one ply on, numbered as played.
func moveRange(_ sans: [String], _ from: Int) -> String {
  sans.dropFirst(from).enumerated().map { i, san in
    let ply = from + i
    let n = ply / 2 + 1
    return ply % 2 == 0 ? "\(n).\(san)" : i == 0 ? "\(n)...\(san)" : san
  }.joined(separator: " ")
}

/// "White · Sicilian › Najdorf": the selection as a subtitle.
func selectionText(_ tree: OpeningTree, _ catalog: PickerCatalog, _ color: ColorChoice, _ openingId: String) -> String {
  "\(colorLabel(color)) \u{00b7} \(selectionTrail(tree, catalog, openingId).joined(separator: " \u{203a} "))"
}
