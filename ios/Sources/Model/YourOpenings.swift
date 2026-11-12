import Foundation
import ChessCore
import Book

/// Book families that only name a first move or two. They never name one of
/// your openings: a line covered only by one of them has no row.
public let FIRST_MOVE_FAMILIES: Set<String> = [
  "King's Pawn Game", "King's Knight Opening", "Queen's Pawn Game", "Zukertort Opening", "Indian Defence",
]

/// The family a book name is listed under: the book's family, or inside a
/// generic family the variation's own name ("London System" from "Queen's
/// Pawn Game: London System"). Nil where the name only marks the way in.
public func openingFamily(_ index: ReferenceIndex, _ name: String) -> String? {
  let family = familyName(index, name)
  guard FIRST_MOVE_FAMILIES.contains(family) else { return family }
  guard let at = name.range(of: ": ") else { return nil }
  let variation = name[at.upperBound...].split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
  if variation.isEmpty || variation.hasSuffix("Variation") || variation.hasSuffix("Invitation") { return nil }
  return variation
}

/// The book opening a family stands for, where its rating is kept: the
/// shallowest node of that name, else the node at `path`.
public func familyNode(_ tree: OpeningTree, _ name: String, path: [String]) -> OpeningNode? {
  if let named = shallowestByName(tree)[name] { return named }
  let node = nodeById(tree, path.joined(separator: " "))
  return node.depth > 0 ? node : nil
}

/// The family node of the opening a node sits in, if it has one.
public func familyOf(_ tree: OpeningTree, _ node: OpeningNode) -> OpeningNode? {
  guard node.depth > 0, let family = openingFamily(tree.index, node.name) else { return nil }
  return familyNode(tree, family, path: node.sans)
}

private func shallowestByName(_ tree: OpeningTree) -> [String: OpeningNode] {
  tree.index.caches.value("shallowestByName") {
    var byName: [String: OpeningNode] = [:]
    for node in tree.byId.values where node.depth > 0 {
      if let held = byName[node.name], held.depth <= node.depth { continue }
      byName[node.name] = node
    }
    return byName
  }
}

/// One of your openings: a Playbook family, the book node it stands for and
/// the side you play it from.
public struct YourOpening: Sendable {
  public var node: OpeningNode
  public var side: Color
  public var name: String
  public var lines: Int
  public var value: Double
  /// The node and side together: one family can be yours from both sides.
  public var key: String { "\(side.rawValue) \(node.id)" }
}

/// Your openings, most worth focusing on first: every Playbook family of
/// both sides. Value grows with how often the book reaches the family, how
/// many lines you hold in it, and how few runs ago you played it.
public func yourOpenings(_ reps: [Playbook], _ tree: OpeningTree, _ score: ScoreState) -> [YourOpening] {
  let total = max(1, tree.root.games)
  var out: [YourOpening] = []
  for rep in reps {
    for row in playbookRows(rep, tree.index) {
      guard let path = row.parts.first?.path, let node = familyNode(tree, row.name, path: path) else { continue }
      let lines = row.parts.reduce(0) { $0 + $1.lines }
      if let at = out.firstIndex(where: { $0.node.id == node.id && $0.side == rep.color }) {
        out[at].lines += lines
        continue
      }
      out.append(YourOpening(node: node, side: rep.color, name: row.name, lines: lines, value: 0))
    }
  }
  for i in out.indices {
    let reach = (out[i].node.games / total).squareRoot()
    let prep = 1 + log2(1 + Double(out[i].lines))
    // Played this run counts double, three runs ago one and a half.
    let lastRound = score.nodes[out[i].node.id]?.lastRound
    let fresh = lastRound.map { 1 + 1 / (1 + Double(max(0, score.lineRounds - $0)) / 3) } ?? 1
    out[i].value = reach * prep * fresh
  }
  return out.sorted { a, b in a.value != b.value ? a.value > b.value : a.name < b.name }
}

/// Saves from before "Any favorite" was folded into Any opening name it by this id.
public let LEGACY_ANY_FAVORITE = "*favorites"
