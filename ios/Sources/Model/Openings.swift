import Book
import ChessCore
import Shared

/// Openings, derived from the tree rather than stored.

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
/// Lines that stop where only a first-move name covers them (see `openingFamily`) have no row,
/// unless `firstMoves` keeps them, as imports do: under that name, or for Black after its first move.
public func familiesIn(_ rep: Repertoire, _ index: ReferenceIndex, firstMoves: Bool = false) -> [DerivedOpening] {
  var rows: [FamilyRow] = []
  func visit(_ region: NamedRegion, _ row: FamilyRow?) {
    var here = row
    let named = openingFamily(index, region.name) ?? (firstMoves ? familyName(index, region.name) : nil)
    if let family = named, family != row?.name {
      let made = FamilyRow(name: family, rootId: region.rootId, path: region.path)
      row?.nested.append(region.rootId)
      rows.append(made)
      here = made
    }
    if let here {
      // The ECO of the family's own position, where the tree passes through it.
      if region.name == here.name || here.eco == nil { here.eco = region.eco ?? here.eco }
      here.ownLines += region.ownLines
    }
    for child in region.children { visit(child, here) }
  }
  for region in namedRegions(rep, index) { visit(region, nil) }

  let listed = rows.filter { $0.ownLines > 0 }
  var names = listed.map(\.name)
  if firstMoves && rep.color == .b { names = blackNames(listed.map { ($0.name, $0.path) }, index) }
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

/// Black's names for a list of openings: called by the first move of each side ("1.e4 e5")
/// where the book named White's, when that is unambiguous. Written as moves, so it doesn't read as a name.
private func blackNames(_ openings: [(name: String, path: [String])], _ index: ReferenceIndex) -> [String] {
  var names = openings.map(\.name)
  let renamed = openings.indices
    .filter { openings[$0].path.count >= 2 && WHITE_NAMES.contains(familyName(index, openings[$0].name)) }
    .map { ($0, "1.\(openings[$0].path[0]) \(openings[$0].path[1])") }
  var counts: [String: Int] = [:]
  for (_, label) in renamed { counts[label, default: 0] += 1 }
  for (i, label) in renamed where counts[label] == 1 { names[i] = label }
  return names
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

/// A row of the Playbook tab: every family row of one name, however many move orders reach it.
public struct PlaybookRow: Equatable, Sendable {
  public var name: String
  public var color: Color
  public var repertoireId: String
  /// The family's rows from `familiesIn`, biggest first.
  public var parts: [DerivedOpening]

  public var id: String { "\(repertoireId)#\(name)" }
  public var lines: Int { parts.reduce(0) { $0 + $1.lines } }
}

/// The Playbook tab's rows for one side: `familiesIn`, with rows of the same name merged.
public func playbookRows(_ rep: Repertoire, _ index: ReferenceIndex, firstMoves: Bool = false) -> [PlaybookRow] {
  var rows: [PlaybookRow] = []
  for opening in familiesIn(rep, index, firstMoves: firstMoves) {
    if let at = rows.firstIndex(where: { $0.name == opening.name }) {
      rows[at].parts.append(opening)
    } else {
      rows.append(PlaybookRow(name: opening.name, color: rep.color, repertoireId: rep.id, parts: [opening]))
    }
  }
  return rows
}

/// One first move's rows on the Playbook tab, for the heading "1.e4".
public struct PlaybookGroup: Equatable, Sendable {
  public var move: String
  public var entries: [PlaybookEntry]
}

/// A row on its own, or the rows that answer one opening of yours, under that opening's name.
public enum PlaybookEntry: Equatable, Sendable {
  case row(PlaybookRow)
  /// `node` is the book position the family is named for, where its rating is kept.
  case family(name: String, node: String, rows: [PlaybookRow])

  public var lines: Int {
    switch self {
    case .row(let row): row.lines
    case .family(_, _, let rows): rows.reduce(0) { $0 + $1.lines }
    }
  }
}

/// The Playbook's rows under a heading for each first move, and rows that
/// answer the same opening of yours under that opening's name: the replies to
/// 1.d4 d5 2.c4 sit under "Queen's Gambit". The family is the shortest
/// position after one of your own moves, past the first, that two rows go
/// through and the book names. Rows keep their order.
public func playbookGroups(_ rows: [PlaybookRow], _ tree: OpeningTree) -> [PlaybookGroup] {
  func path(_ row: PlaybookRow) -> [String] { row.parts.first?.path ?? [] }
  var groups: [PlaybookGroup] = []
  var order: [String] = []
  var byMove: [String: [PlaybookRow]] = [:]
  for row in rows {
    guard let first = path(row).first else { continue }
    if byMove[first] == nil { order.append(first) }
    byMove[first, default: []].append(row)
  }
  for first in order {
    let members = byMove[first]!
    // Your own moves end at odd lengths as White, even as Black.
    let start = members[0].color == .w ? 3 : 2
    func prefixes(_ row: PlaybookRow) -> [[String]] {
      let p = path(row)
      return Swift.stride(from: start, to: p.count, by: 2).map { Array(p.prefix($0)) }
    }
    var familyOf: [String: (name: String, node: String)] = [:]
    for row in members {
      for prefix in prefixes(row) {
        let id = prefix.joined(separator: " ")
        let sharing = members.filter { path($0).count > prefix.count && Array(path($0).prefix(prefix.count)) == prefix }
        let node = nodeById(tree, id)
        guard sharing.count >= 2, node.depth == prefix.count, let name = openingFamily(tree.index, node.name) else { continue }
        familyOf[row.id] = (name, id)
        break
      }
    }
    var entries: [PlaybookEntry] = []
    for row in members {
      guard let family = familyOf[row.id] else {
        entries.append(.row(row))
        continue
      }
      if let at = entries.firstIndex(where: { if case .family(_, family.node, _) = $0 { true } else { false } }),
        case .family(let name, let node, var held) = entries[at]
      {
        held.append(row)
        entries[at] = .family(name: name, node: node, rows: held)
      } else {
        entries.append(.family(name: family.name, node: family.node, rows: [row]))
      }
    }
    groups.append(PlaybookGroup(move: "1.\(first)", entries: entries))
  }
  return groups
}

/// A row's name under its family's: "Declined" under "Queen's Gambit" for Queen's Gambit Declined.
public func nameUnder(_ family: String, _ name: String) -> String {
  guard name.hasPrefix(family + " ") else { return name }
  let rest = name.dropFirst(family.count + 1)
  return rest.prefix(1).uppercased() + rest.dropFirst()
}

/// Every line of a Playbook row, part by part.
public func linesOf(_ rep: Repertoire, _ row: PlaybookRow, _ index: ReferenceIndex) -> [OpeningLine] {
  row.parts.flatMap { linesOf(rep, $0, index) }
}
