import Book
import ChessCore
import Shared

/// Openings, derived from the tree rather than stored. `src/model/openings.ts`.

public struct DerivedOpening: Equatable, Sendable {
  /// Stable within a repertoire: the node the region begins at.
  public var id: String
  public var repertoireId: String
  public var color: Color
  public var name: String
  public var eco: String?
  /// The node the region begins at. Deleting it deletes the opening.
  public var rootId: String
  /// Moves from the start up to and including that node's move.
  public var path: [String]
  /// Nodes in the region.
  public var moves: Int
  /// Moves that exist only for this opening: what deleting it costs.
  public var removes: Int
  /// Lines that end inside the region.
  public var lines: Int
  /// Deepest ply the region reaches.
  public var depth: Int
  /// Named regions one level further in.
  public var variations: [DerivedOpening]
  /// Roots of openings inside this one's subtree that are listed on their own.
  public var nested: [String]?
}

private final class NamedRegion {
  var name: String
  var eco: String?
  let rootId: String
  let path: [String]
  /// Ply the name attaches at. One only restates the first move.
  let ply: Int
  var children: [NamedRegion] = []
  /// Lines ending here but outside every child region.
  var ownLines = 0

  init(name: String, eco: String?, rootId: String, path: [String]) {
    self.name = name
    self.eco = eco
    self.rootId = rootId
    self.path = path
    ply = path.count
  }

  func copy(children: [NamedRegion]) -> NamedRegion {
    let out = NamedRegion(name: name, eco: eco, rootId: rootId, path: path)
    out.children = children
    out.ownLines = ownLines
    return out
  }
}

/// Every opening in one repertoire, the biggest first.
public func openingsIn(_ rep: Repertoire, _ index: ReferenceIndex) -> [DerivedOpening] {
  let openings = collapse(namedRegions(rep, index))
  if rep.color == .b {
    for (region, name) in zip(openings, blackNames(openings.map { ($0.name, $0.path) }, index)) { region.name = name }
  }
  return sorted(openings.map { finish(rep, $0) })
}

/// Every named region of a tree, nested as the book names them.
private func namedRegions(_ rep: Repertoire, _ index: ReferenceIndex) -> [NamedRegion] {
  var tops: [NamedRegion] = []
  func visit(_ node: RepMove, _ path: [String], _ enclosing: NamedRegion?) {
    let here = path + [node.san]
    var region = enclosing
    if let named = nameAt(index, node.fenAfter), named.name != enclosing?.name {
      let made = NamedRegion(name: named.name, eco: named.eco, rootId: node.id, path: here)
      if let enclosing { enclosing.children.append(made) } else { tops.append(made) }
      region = made
    } else if region == nil {
      // Nothing on this path is named, so the move names itself.
      let made = NamedRegion(name: moveLabel(here), eco: nil, rootId: node.id, path: here)
      tops.append(made)
      region = made
    }
    let kids = childrenOf(rep, node.id)
    if kids.isEmpty { region!.ownLines += 1 }
    for kid in kids { visit(kid, here, region) }
  }
  for root in childrenOf(rep, nil) { visit(root, [], nil) }
  return tops
}

private final class FamilyRow {
  let name: String
  var eco: String?
  let rootId: String
  let path: [String]
  var ownLines = 0
  var nested: [String] = []
  init(name: String, rootId: String, path: [String]) {
    self.name = name
    self.rootId = rootId
    self.path = path
  }
}

/// The Playbook's rows: one per opening family, a family nested in another on a row of its own.
public func familiesIn(_ rep: Repertoire, _ index: ReferenceIndex) -> [DerivedOpening] {
  var rows: [FamilyRow] = []
  func visit(_ region: NamedRegion, _ row: FamilyRow?) {
    let family = familyName(index, region.name)
    var here = row
    if here == nil || family != here!.name {
      let made = FamilyRow(name: family, rootId: region.rootId, path: region.path)
      row?.nested.append(region.rootId)
      rows.append(made)
      here = made
    }
    // The ECO of the family's own position, where the tree passes through it.
    if region.name == family || here!.eco == nil { here!.eco = region.eco ?? here!.eco }
    here!.ownLines += region.ownLines
    for child in region.children { visit(child, here) }
  }
  for region in namedRegions(rep, index) { visit(region, nil) }

  let listed = rows.filter { $0.ownLines > 0 }
  var names = listed.map(\.name)
  if rep.color == .b { names = blackNames(listed.map { ($0.name, $0.path) }, index) }
  return sorted(listed.enumerated().map { i, row in
    let stats = subtreeStats(rep, row.rootId, row.path.count, Set(row.nested))
    return DerivedOpening(
      id: "\(rep.id)#\(row.rootId)", repertoireId: rep.id, color: rep.color, name: names[i], eco: row.eco,
      rootId: row.rootId, path: row.path, moves: stats.moves,
      removes: row.nested.isEmpty ? pruneCount(rep, row.rootId) : removedWith(rep, stats.tips),
      lines: stats.lines, depth: stats.depth, variations: [], nested: row.nested.isEmpty ? nil : row.nested)
  })
}

/// Whether a node belongs to an opening: in its subtree but not one nested in it, or on the way to it.
public func holdsNode(_ rep: Repertoire, _ opening: DerivedOpening, _ nodeId: String) -> Bool {
  let nested = Set(opening.nested ?? [])
  var id: String? = nodeId
  while let at = id {
    if nested.contains(at) { return false }
    if at == opening.rootId { return true }
    id = rep.nodes[at]?.parentId
  }
  id = opening.rootId
  while let at = id {
    if at == nodeId { return true }
    id = rep.nodes[at]?.parentId
  }
  return false
}

/// The ends of every line an opening holds, leaving out openings nested in it.
public func tipsOf(_ rep: Repertoire, _ opening: DerivedOpening) -> [String] {
  subtreeStats(rep, opening.rootId, opening.path.count, Set(opening.nested ?? [])).tips
}

/// How many moves go when these lines are deleted: every move all of whose lines are among them.
private func removedWith(_ rep: Repertoire, _ tips: [String]) -> Int {
  let gone = Set(tips)
  var count = 0
  func visit(_ node: RepMove) -> Bool {
    let kids = childrenOf(rep, node.id)
    var all = kids.isEmpty ? gone.contains(node.id) : true
    for kid in kids where !visit(kid) { all = false }
    if all { count += 1 }
    return all
  }
  for root in childrenOf(rep, nil) { _ = visit(root) }
  return count
}

/// The book's names for White openings Black meets without naming a defence of its own.
private let WHITE_NAMES: Set<String> = ["King's Pawn Game", "King's Knight Opening", "Queen's Pawn Game", "Zukertort Opening"]

/// Black's names for a list of openings: called after Black's first move
/// where the book named White's, when that is unambiguous.
private func blackNames(_ openings: [(name: String, path: [String])], _ index: ReferenceIndex) -> [String] {
  var names = openings.map(\.name)
  let renamed = openings.indices
    .filter { openings[$0].path.count >= 2 && WHITE_NAMES.contains(familyName(index, openings[$0].name)) }
    .map { ($0, moveLabel(Array(openings[$0].path.prefix(2)))) }
  var counts: [String: Int] = [:]
  for (_, label) in renamed { counts[label, default: 0] += 1 }
  for (i, label) in renamed where counts[label] == 1 { names[i] = label }
  return names
}

/// The opening a node sits in, if the list is to hand.
public func openingAt(_ openings: [DerivedOpening], _ nodeId: String) -> DerivedOpening? {
  for opening in openings {
    if opening.rootId == nodeId { return opening }
    if let deeper = openingAt(opening.variations, nodeId) { return deeper }
  }
  return nil
}

/// Drop the names that only lead somewhere: a first move with openings under
/// it, and deeper a region with no lines of its own and one region under it.
private func collapse(_ regions: [NamedRegion]) -> [NamedRegion] {
  var out: [NamedRegion] = []
  for region in regions {
    let children = collapse(region.children)
    let firstMove = region.ply <= 1 && !children.isEmpty
    let waypoint = children.count == 1
    if region.ownLines == 0 && (firstMove || waypoint) {
      out.append(contentsOf: children)
    } else {
      out.append(region.copy(children: children))
    }
  }
  return out
}

private func finish(_ rep: Repertoire, _ region: NamedRegion) -> DerivedOpening {
  let stats = subtreeStats(rep, region.rootId, region.path.count)
  return DerivedOpening(
    id: "\(rep.id)#\(region.rootId)", repertoireId: rep.id, color: rep.color, name: region.name, eco: region.eco,
    rootId: region.rootId, path: region.path, moves: stats.moves, removes: pruneCount(rep, region.rootId),
    lines: stats.lines, depth: stats.depth, variations: sorted(region.children.map { finish(rep, $0) }))
}

/// Biggest first: where the work is.
private func sorted(_ openings: [DerivedOpening]) -> [DerivedOpening] {
  openings.jsSorted { a, b in
    let removes = Double(b.removes - a.removes)
    return removes != 0 ? removes : Double(JS.localeCompare(a.name, b.name))
  }
}

private func subtreeStats(_ rep: Repertoire, _ nodeId: String, _ ply: Int, _ skip: Set<String> = []) -> (moves: Int, lines: Int, depth: Int, tips: [String]) {
  let all = childrenOf(rep, nodeId)
  if all.isEmpty { return (1, 1, ply, [nodeId]) }
  // Only the way into an opening listed on its own: a move, but no line.
  let kids = all.filter { !skip.contains($0.id) }
  if kids.isEmpty { return (1, 0, 0, []) }
  var moves = 1, lines = 0, depth = ply
  var tips: [String] = []
  for kid in kids {
    let below = subtreeStats(rep, kid.id, ply + 1, skip)
    moves += below.moves
    lines += below.lines
    depth = max(depth, below.depth)
    tips += below.tips
  }
  return (moves, lines, depth, tips)
}

/// One line of an opening: a path from the start to a move with nothing after it.
public struct OpeningLine: Equatable, Sendable {
  public var tipId: String
  public var path: [String]
  /// The deepest book name the line reaches, without the opening's own name in front.
  public var name: String
  /// "5.Re1": where it parts from a line with the same name.
  public var split: String?
  /// Moves only this line owns: what deleting it removes.
  public var removes: Int
}

/// Every line of one opening, in tree order, each named for where it goes.
public func linesOf(_ rep: Repertoire, _ opening: DerivedOpening, _ index: ReferenceIndex) -> [OpeningLine] {
  guard let root = rep.nodes[opening.rootId] else { return [] }
  var raw: [(tipId: String, path: [String], name: String, split: Int)] = []
  let nested = Set(opening.nested ?? [])
  func visit(_ node: RepMove, _ path: [String], _ name: String) {
    let here = path + [node.san]
    let named = nameAt(index, node.fenAfter)?.name ?? name
    let all = childrenOf(rep, node.id)
    if all.isEmpty {
      raw.append((node.id, here, named, splitPly(rep, node.id)))
      return
    }
    for kid in all where !nested.contains(kid.id) { visit(kid, here, named) }
  }
  visit(root, Array(opening.path.dropLast()), opening.name)

  var counts: [String: Int] = [:]
  for line in raw { counts[line.name, default: 0] += 1 }
  return raw.map { line in
    let clash = counts[line.name, default: 0] > 1 && line.split > 0
    return OpeningLine(
      tipId: line.tipId, path: line.path, name: shortName(line.name, opening.name),
      split: clash ? moveLabel(Array(line.path.prefix(line.split))) : nil,
      removes: pruneCount(rep, line.tipId))
  }
}

/// "Ruy Lopez: Berlin Defence" under the Ruy Lopez reads "Berlin Defence".
private func shortName(_ name: String, _ family: String) -> String {
  if name == family { return name }
  for sep in [": ", ", "] where name.hasPrefix(family + sep) {
    return String(name.dropFirst(family.count + sep.count))
  }
  // A variation's own name repeats only the family.
  if let colon = family.range(of: ": "), colon.lowerBound > family.startIndex {
    let head = String(family[..<colon.upperBound])
    if name.hasPrefix(head) { return String(name.dropFirst(head.count)) }
  }
  return name
}

/// Ply of the first move only this line has.
private func splitPly(_ rep: Repertoire, _ tipId: String) -> Int {
  var ply = 0
  var id: String? = tipId
  while let at = id {
    ply += 1
    id = rep.nodes[at]?.parentId
  }
  var childId = tipId
  var parentId = rep.nodes[tipId]?.parentId
  while let at = parentId {
    guard let parent = rep.nodes[at], !parent.children.contains(where: { $0 != childId }) else { break }
    ply -= 1
    childId = at
    parentId = parent.parentId
  }
  return ply
}
