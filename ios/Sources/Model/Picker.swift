import Book
import ChessCore
import Shared

/// The opening picker's catalogue: the book's names arranged the way the
/// book spells them, Family: Branch, Line. `src/model/picker.ts`.

public final class PickerEntry: @unchecked Sendable {
  /// The full name this entry stands for.
  public let key: String
  /// The last part of the name. A family's label is the family.
  public let label: String
  public let family: String
  /// 0 a family, 1 a branch, 2 and up a line.
  public let level: Int
  /// The tree node behind the entry; the shallowest of its lines when the
  /// book never names the entry on its own (`exact` false).
  public internal(set) var node: OpeningNode
  public let exact: Bool
  public private(set) weak var parent: PickerEntry?
  public internal(set) var children: [PickerEntry] = []
  /// Games through the entry.
  public internal(set) var games: Double
  /// Whose opening it is.
  public internal(set) var side: Color = .w
  public internal(set) var sharpness: Sharpness = 3
  /// 1 to 5, from how many lines you would need to know.
  public internal(set) var difficulty = 3

  init(key: String, label: String, family: String, level: Int, node: OpeningNode, exact: Bool, parent: PickerEntry?, games: Double) {
    self.key = key
    self.label = label
    self.family = family
    self.level = level
    self.node = node
    self.exact = exact
    self.parent = parent
    self.games = games
  }
}

public struct PickerGroup: Sendable {
  public var id: String
  public var label: String
  public var family: String
  public var entries: [PickerEntry]
  public var sharpness: Sharpness
  /// A node to select for the whole group, where one position defines it.
  public var node: OpeningNode?
  /// Other groups an entry can be reached from, by entry key.
  public var alsoVia: [String: [String]]
}

public enum FirstMove: String, Sendable {
  case e4, d4, flank
}

public final class PickerFamily: @unchecked Sendable {
  public let entry: PickerEntry
  public let firstMove: FirstMove
  /// Nil for a family small enough to list its branches flat.
  public internal(set) var groups: [PickerGroup]?
  init(entry: PickerEntry, firstMove: FirstMove) {
    self.entry = entry
    self.firstMove = firstMove
  }
}

public final class PickerCatalog: @unchecked Sendable {
  public let families: [PickerFamily]
  /// Every entry by its full name.
  public let byKey: OrderedMap<String, PickerEntry>
  /// The entry each exact node stands for.
  public let byNode: [String: PickerEntry]
  public let familyByName: [String: PickerFamily]
  init(families: [PickerFamily], byKey: OrderedMap<String, PickerEntry>, byNode: [String: PickerEntry], familyByName: [String: PickerFamily]) {
    self.families = families
    self.byKey = byKey
    self.byNode = byNode
    self.familyByName = familyByName
  }
}

public func pickerCatalog(_ tree: OpeningTree) -> PickerCatalog {
  tree.index.caches.value("pickerCatalog") { buildCatalog(tree) }
}

/// A name as the keys of every level it names, shallowest first.
public func nameLevels(_ family: String, _ name: String) -> [String] {
  guard let at = name.range(of: ": ") else { return family == name ? [name] : [family, name] }
  let prefix = String(name[..<at.lowerBound])
  let parts = name[at.upperBound...].components(separatedBy: ", ")
  return [family] + parts.indices.map { "\(prefix): \(parts[...$0].joined(separator: ", "))" }
}

private func labelOf(_ key: String, _ level: Int) -> String {
  if level == 0 { return key }
  let rest = key.range(of: ": ").map { String(key[$0.upperBound...]) } ?? key
  return rest.components(separatedBy: ", ").last!
}

private func firstMoveOf(_ node: OpeningNode) -> FirstMove {
  node.sans.first == "e4" ? .e4 : node.sans.first == "d4" ? .d4 : .flank
}

private func buildCatalog(_ tree: OpeningTree) -> PickerCatalog {
  let index = tree.index
  var byKey = OrderedMap<String, PickerEntry>()

  // The node for each name: the shallowest, where the book reuses a name.
  var nodeByName = OrderedMap<String, OpeningNode>()
  for node in tree.byId.values where node.depth > 0 {
    if let seen = nodeByName[node.name], !(node.sans.count < seen.sans.count || (node.sans.count == seen.sans.count && node.games > seen.games)) {
      continue
    }
    nodeByName[node.name] = node
  }

  func ensure(_ key: String, _ level: Int, _ family: String, _ parent: PickerEntry?) -> PickerEntry {
    if let entry = byKey[key] { return entry }
    let node = nodeByName[key]
    let entry = PickerEntry(
      key: key, label: labelOf(key, level), family: family, level: level, node: node ?? tree.root,
      exact: node != nil, parent: parent, games: node?.games ?? 0)
    byKey[key] = entry
    parent?.children.append(entry)
    return entry
  }

  for name in nodeByName.keys {
    let family = familyName(index, name)
    var parent: PickerEntry?
    for (level, key) in nameLevels(family, name).enumerated() { parent = ensure(key, level, family, parent) }
  }

  // Entries the book only names through their lines borrow the shallowest line.
  func settle(_ entry: PickerEntry) {
    for child in entry.children { settle(child) }
    if !entry.exact {
      let lines = entry.children.map(\.node).filter { $0.depth > 0 }
      let shallowest = lines.jsSorted { a, b in
        let len = Double(a.sans.count - b.sans.count)
        return len != 0 ? len : b.games - a.games
      }.first
      if let shallowest { entry.node = shallowest }
      entry.games = entry.children.reduce(0) { $0 + $1.games }
    }
    entry.side = entry.node.depth > 0 ? playerOf(entry.node.sans) : .w
  }
  // A line is played from its branch's side.
  func inherit(_ entry: PickerEntry) {
    if let side = BRANCH_SIDES[entry.key] { entry.side = side }
    if entry.level >= 2, let parent = entry.parent { entry.side = parent.side }
    for child in entry.children { inherit(child) }
  }
  let roots = byKey.values.filter { $0.level == 0 }
  for root in roots { settle(root) }
  for root in roots { inherit(root) }

  var byNode: [String: PickerEntry] = [:]
  for entry in byKey.values where entry.exact { byNode[entry.node.id] = entry }

  let families = roots.map { PickerFamily(entry: $0, firstMove: firstMoveOf($0.node)) }
  var familyByName: [String: PickerFamily] = [:]
  for family in families { familyByName[family.entry.key] = family }

  for family in families {
    if let split = FAMILY_GROUPS[family.entry.key] {
      family.groups = groupFamily(tree, family.entry, split.groups, split.rest, split.restSharpness)
    }
  }

  scoreSharpness(families)
  scoreDifficulty(tree, byKey.values)
  return PickerCatalog(families: families, byKey: byKey, byNode: byNode, familyByName: familyByName)
}

/* ── groups ── */

private func keyAfter(_ sans: String) -> String? {
  var fen = START_FEN
  for san in sans.split(separator: " ", omittingEmptySubsequences: false) {
    guard let move = applySan(fen, String(san)) else { return nil }
    fen = move.after
  }
  return positionKey(fen)
}

private func gamesAt(_ tree: OpeningTree, _ key: String) -> Double {
  tree.index.entries[key]?.moves.reduce(0) { $0 + $1.games } ?? 0
}

private final class ResolvedGroup {
  let spec: GroupSpec
  let keys: [String]
  let games: Double
  init(spec: GroupSpec, keys: [String], games: Double) {
    self.spec = spec
    self.keys = keys
    self.games = games
  }
}

/// Split a family's branches into its groups, by position: a branch goes to
/// the deepest group position it passes through, else one it can transpose
/// from; other groups it can be reached from are noted as "also via".
public func groupFamily(_ tree: OpeningTree, _ family: PickerEntry, _ specs: [GroupSpec], _ rest: String, _ restSharpness: Sharpness?) -> [PickerGroup] {
  let resolved = specs.map { spec -> ResolvedGroup in
    let keys = spec.from.compactMap(keyAfter)
    return ResolvedGroup(spec: spec, keys: keys, games: keys.reduce(0) { $0 + gamesAt(tree, $1) })
  }

  var members: [ObjectIdentifier?: [PickerEntry]] = [:]
  var reachable: [ObjectIdentifier: [ResolvedGroup]] = [:]
  var homes: [ObjectIdentifier: ResolvedGroup?] = [:]
  let id = { (g: ResolvedGroup?) in g.map(ObjectIdentifier.init) }
  for branch in family.children {
    let path = branch.node.pathKeys
    var home: ResolvedGroup?
    var deepest = -1
    for group in resolved {
      for key in group.keys {
        let at = path.firstIndex(of: key) ?? -1
        if at > deepest {
          deepest = at
          home = group
        }
      }
    }
    let approach = approachOne(tree, branch.node)
    let via = resolved.filter { group in
      group.keys.contains { approach.contains($0) } && !group.keys.contains { path.contains($0) }
    }
    if home == nil { home = via.jsSorted { cmp($1.games, $0.games) }.first }
    reachable[ObjectIdentifier(branch)] = via.filter { $0 !== home }
    homes[ObjectIdentifier(branch)] = home
    members[id(home), default: []].append(branch)
  }

  // A group of one is only a heading over its own branch: fold it into the rest.
  for group in resolved {
    let list = members[id(group)] ?? []
    if list.count == 1 {
      members[nil, default: []].append(contentsOf: list)
      members[id(group)] = nil
    }
  }
  let kept = Set(resolved.filter { (members[id($0)]?.count ?? 0) > 1 }.map(ObjectIdentifier.init))

  var out: [PickerGroup] = []
  let familySharp = FAMILY_SHARPNESS[family.key] ?? 3
  for group in resolved.map(Optional.some) + [nil] {
    if let group, !kept.contains(ObjectIdentifier(group)) { continue }
    let entries = members[id(group)] ?? []
    if entries.isEmpty { continue }
    var alsoVia: [String: [String]] = [:]
    for entry in entries {
      let labels = (reachable[ObjectIdentifier(entry)] ?? [])
        // A group that leads into this one's own position reaches every branch in it.
        .filter { other in
          kept.contains(ObjectIdentifier(other)) && other !== group && !leadsInto(tree, other, homes[ObjectIdentifier(entry)] ?? nil)
        }
        .jsSorted { cmp($1.games, $0.games) }
        .prefix(2)
        .map(\.spec.label)
      if !labels.isEmpty { alsoVia[entry.key] = Array(labels) }
    }
    let single = group.flatMap { $0.keys.count == 1 ? tree.byKey[$0.keys[0]] : nil }
    out.append(PickerGroup(
      id: "\(family.key)#\(group?.spec.label ?? rest)", label: group?.spec.label ?? rest, family: family.key,
      entries: entries, sharpness: group?.spec.sharpness ?? restSharpness ?? familySharp,
      node: single.flatMap { familyName(tree.index, $0.name) == family.key ? $0 : nil }, alsoVia: alsoVia))
  }
  return out
}

/// Can one group's position lead into another's?
private func leadsInto(_ tree: OpeningTree, _ from: ResolvedGroup, _ to: ResolvedGroup?) -> Bool {
  guard let to else { return false }
  let parents = bookGraph(tree.index).parents
  let targets = Set(from.keys)
  return to.keys.contains { key in
    var seen: Set<String> = [key]
    var queue = [key]
    while let at = queue.popLast() {
      if targets.contains(at) { return true }
      for parent in parents[at] ?? [] where !seen.contains(parent) {
        seen.insert(parent)
        queue.append(parent)
      }
    }
    return false
  }
}

/* ── sharpness ── */

private func scoreSharpness(_ families: [PickerFamily]) {
  func visit(_ entry: PickerEntry, _ inherited: Sharpness) {
    var own = SHARPNESS_OVERRIDES[entry.key] ?? inherited
    // A gambit is sharp in any family, unless someone said otherwise about this line.
    if SHARPNESS_OVERRIDES[entry.key] == nil, entry.level > 0,
      entry.label.firstMatch(of: #/Gambit|Countergambit/#) != nil, !entry.label.contains("Declined")
    {
      own = max(own, 4)
    }
    entry.sharpness = own
    for child in entry.children { visit(child, own) }
  }
  for family in families {
    let base = FAMILY_SHARPNESS[family.entry.key] ?? 3
    family.entry.sharpness = SHARPNESS_OVERRIDES[family.entry.key] ?? base
    for branch in family.entry.children {
      let group = family.groups?.first { $0.entries.contains { $0 === branch } }
      visit(branch, group?.sharpness ?? family.entry.sharpness)
    }
  }
}

/* ── difficulty ── */

/// A reply needs an answer once it is played this often.
private let REPLY_SHARE = 0.1
/// How far past the entry's own position the count looks.
private let MAX_PLIES = 14
private let MIN_PLIES = 4

/// How many lines you would have to know to play from a position: your most
/// played move at your turns, every reply of 10% or more at theirs.
public func theoryLines(_ children: [String: [(key: String, games: Double)]], _ key: String, _ side: Color, _ plies: Int, _ memo: inout [String: Double]) -> Double {
  if plies <= 0 { return 1 }
  let id = "\(key)|\(plies)|\(side.rawValue)"
  if let known = memo[id] { return known }
  let moves = children[key] ?? []
  var count: Double = 1
  if !moves.isEmpty {
    let turn: Color = key.split(separator: " ", omittingEmptySubsequences: false)[1] == "b" ? .b : .w
    let sorted = moves.jsSorted { cmp($1.games, $0.games) }
    if turn == side {
      count = theoryLines(children, sorted[0].key, side, plies - 1, &memo)
    } else {
      let total = sorted.reduce(0) { $0 + $1.games }
      let replies = sorted.enumerated().filter { $0.offset == 0 || $0.element.games / max(1, total) >= REPLY_SHARE }
      count = 0
      for reply in replies { count += theoryLines(children, reply.element.key, side, plies - 1, &memo) }
    }
  }
  memo[id] = count
  return count
}

private func deepestPly(_ entry: PickerEntry) -> Int {
  entry.children.reduce(entry.node.sans.count) { max($0, deepestPly($1)) }
}

/// Difficulty as a 1 to 5 bucket, ranked among entries at the same level.
private func scoreDifficulty(_ tree: OpeningTree, _ entries: [PickerEntry]) {
  let children = bookGraph(tree.index).children
  var memo: [String: Double] = [:]
  var raw: [ObjectIdentifier: Double] = [:]
  var rated: [PickerEntry] = []
  for entry in entries where entry.node.depth > 0 {
    let plies = max(MIN_PLIES, min(MAX_PLIES, deepestPly(entry) - entry.node.sans.count))
    raw[ObjectIdentifier(entry)] = theoryLines(children, entry.node.key, entry.side, plies, &memo)
    rated.append(entry)
  }
  var tiers = OrderedMap<Int, [PickerEntry]>()
  for entry in rated { tiers[min(entry.level, 2)] = (tiers[min(entry.level, 2)] ?? []) + [entry] }
  for list in tiers.values {
    let value = { (e: PickerEntry) in raw[ObjectIdentifier(e)]! }
    let sorted = list.jsSorted { value($0) - value($1) }
    for (i, entry) in sorted.enumerated() {
      // Ties share a bucket: the first of a run of equal counts decides it.
      var first = i
      while first > 0 && value(sorted[first - 1]) == value(entry) { first -= 1 }
      entry.difficulty = 1 + Int((Double(first) / Double(sorted.count) * 5).rounded(.down))
    }
  }
}

/// The entry a tree node is shown as: its own, or the deepest named one around it.
public func entryForNode(_ catalog: PickerCatalog, _ node: OpeningNode) -> PickerEntry? {
  catalog.byNode[node.id] ?? catalog.byKey[node.name]
}

/// An entry and everything above it, family first.
public func entryTrail(_ entry: PickerEntry) -> [PickerEntry] {
  var out: [PickerEntry] = []
  var cursor: PickerEntry? = entry
  while let at = cursor {
    out.insert(at, at: 0)
    cursor = at.parent
  }
  return out
}

/// The side picking a tree node sets: its entry's, or none for "any opening".
public func sideForPick(_ catalog: PickerCatalog, _ node: OpeningNode) -> Color? {
  if node.depth == 0 { return nil }
  return entryForNode(catalog, node)?.side ?? playerOf(node.sans)
}

/// Where the book names an opening a move late. `onboarding.ts`.
public let NAMED_LATE: [String: Color] = [
  // King's Indian Defence.
  "d4 Nf6 c4 g6 Nc3": .b,
  // Scotch Game.
  "e4 e5 Nf3 Nc6 d4 exd4": .w,
]

/// Whose opening a line is: whoever played its last move, except where the book names it late.
public func playerOf(_ sans: [String]) -> Color {
  NAMED_LATE[sans.joined(separator: " ")] ?? (sans.count % 2 == 1 ? .w : .b)
}
