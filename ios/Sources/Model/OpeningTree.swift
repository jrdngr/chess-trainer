import Book
import ChessCore
import Foundation
import Shared

/// The opening tree: every named opening the book knows, nested the way a
/// player thinks about them. `src/model/openingTree.ts`.
public final class OpeningNode: @unchecked Sendable {
  /// The defining move order, space-joined. The root's id is "".
  public let id: String
  public let name: String
  public let eco: String?
  public let sans: [String]
  /// Position key at the end of `sans`.
  public let key: String
  /// Keys of every position along `sans`, the last included.
  public let pathKeys: [String]
  public let games: Double
  /// 0 the root, 1 a first move, 2 a family, 3 and up variations.
  public internal(set) var depth: Int
  /// A line the book does not name on its own, picked on the board.
  public let custom: Bool
  public internal(set) var parentId: String?
  public internal(set) var children: [OpeningNode] = []

  // What `regionOf` and `approachOne` work out, kept per node like the prototype's WeakMaps.
  private var _approach: Set<String>?
  private var _region: Region?
  private static let lock = NSLock()
  var approach: Set<String>? {
    get { Self.lock.withLock { _approach } }
    set { Self.lock.withLock { _approach = newValue } }
  }
  var region: Region? {
    get { Self.lock.withLock { _region } }
    set { Self.lock.withLock { _region = newValue } }
  }

  init(id: String, name: String, eco: String?, sans: [String], key: String, pathKeys: [String], games: Double, depth: Int, custom: Bool = false, parentId: String?) {
    self.id = id
    self.name = name
    self.eco = eco
    self.sans = sans
    self.key = key
    self.pathKeys = pathKeys
    self.games = games
    self.depth = depth
    self.custom = custom
    self.parentId = parentId
  }
}

public final class OpeningTree: @unchecked Sendable {
  public let root: OpeningNode
  public let byId: OrderedMap<String, OpeningNode>
  /// The deepest node at each position, for naming a line by where it goes.
  public let byKey: [String: OpeningNode]
  /// The book the tree was built from.
  public let index: ReferenceIndex

  private var lineNodes: [String: OpeningNode?] = [:]
  private let lock = NSLock()

  init(root: OpeningNode, byId: OrderedMap<String, OpeningNode>, byKey: [String: OpeningNode], index: ReferenceIndex) {
    self.root = root
    self.byId = byId
    self.byKey = byKey
    self.index = index
  }

  func lineNode(_ id: String, _ make: () -> OpeningNode?) -> OpeningNode? {
    lock.lock()
    if let made = lineNodes[id] { lock.unlock(); return made }
    lock.unlock()
    let node = make()
    lock.lock()
    lineNodes[id] = node
    lock.unlock()
    return node
  }
}

public let ANY_OPENING = ""

/// Built once per book.
public func openingTree(_ index: ReferenceIndex) -> OpeningTree {
  index.caches.value("openingTree") { buildOpeningTree(index) }
}

func walkKeys(_ sans: [String]) -> (keys: [String], legal: Bool) {
  var fen = START_FEN
  var keys: [String] = []
  for san in sans {
    guard let move = applySan(fen, san) else { return (keys, false) }
    fen = move.after
    keys.append(positionKey(fen))
  }
  return (keys, true)
}

private func makeNode(_ sans: [String], _ name: String, _ eco: String?, _ games: Double, _ parentId: String?) -> OpeningNode? {
  let (keys, legal) = walkKeys(sans)
  guard legal else { return nil }
  return OpeningNode(
    id: sans.joined(separator: " "), name: name, eco: eco, sans: sans,
    key: keys.last ?? positionKey(START_FEN), pathKeys: keys, games: games, depth: 0, parentId: parentId)
}

/// "1.e4", "1...c5": a move named after itself.
public func moveLabel(_ sans: [String]) -> String {
  let ply = sans.count
  return "\((ply - 1) / 2 + 1).\(ply % 2 == 1 ? "" : "..")\(sans[ply - 1])"
}

func buildOpeningTree(_ index: ReferenceIndex) -> OpeningTree {
  let root = OpeningNode(
    id: ANY_OPENING, name: "Any opening", eco: nil, sans: [], key: positionKey(START_FEN),
    pathKeys: [], games: index.totalGames, depth: 0, parentId: nil)
  var byId = OrderedMap<String, OpeningNode>()
  byId[root.id] = root

  func firstMove(_ san: String, _ games: Double) -> OpeningNode {
    if let found = byId[san] { return found }
    let named = applySan(START_FEN, san).flatMap { nameAt(index, $0.after) }
    let node = makeNode([san], named?.name ?? moveLabel([san]), named?.eco, games, root.id)!
    byId[node.id] = node
    return node
  }
  for move in lookup(index, START_FEN)?.moves ?? [] { _ = firstMove(move.san, move.games) }

  // Every catalogue entry becomes a node before any parent is decided.
  let entries = index.catalogue.compactMap { makeNode($0.sans, $0.name, $0.eco, $0.games, nil) }
  for node in entries { byId[node.id] = node }
  var byName: [String: OpeningNode] = [:]
  for node in entries { byName[node.name] = node }

  func extendsPath(_ longer: [String], _ shorter: [String]) -> Bool {
    longer.count > shorter.count && shorter.indices.allSatisfy { longer[$0] == shorter[$0] }
  }

  for node in entries {
    // Moves first: the deepest opening whose move order this one extends.
    var parent: OpeningNode?
    for other in entries where other !== node && extendsPath(node.sans, other.sans) {
      if parent == nil || other.sans.count > parent!.sans.count { parent = other }
    }
    // Names second: a family's variation reached by another road is still the family's.
    let family = familyName(index, node.name)
    if family != node.name, parent == nil || familyName(index, parent!.name) != family {
      if let named = byName[family], named !== node, !extendsPath(named.sans, node.sans) { parent = named }
    }
    node.parentId = (parent ?? firstMove(node.sans[0], 0)).id
  }

  // Cut any loop the name rule could make at the first move.
  for node in entries {
    var seen: Set<String> = [node.id]
    var cursor = node
    while let up = cursor.parentId, up != root.id {
      if seen.contains(up) {
        node.parentId = firstMove(node.sans[0], 0).id
        break
      }
      seen.insert(up)
      cursor = byId[up]!
    }
  }

  for node in byId.values where node !== root {
    byId[node.parentId ?? root.id]!.children.append(node)
  }

  func sortChildren(_ node: OpeningNode, _ depth: Int) {
    node.depth = depth
    node.children.jsSort { a, b in
      let games = b.games - a.games
      return games != 0 ? games : Double(JS.localeCompare(a.name, b.name))
    }
    for child in node.children { sortChildren(child, depth + 1) }
  }
  sortChildren(root, 0)

  var byKey: [String: OpeningNode] = [:]
  for node in byId.values {
    if let existing = byKey[node.key], node.depth <= existing.depth { continue }
    byKey[node.key] = node
  }
  return OpeningTree(root: root, byId: byId, byKey: byKey, index: index)
}

/// The node with this id; a legal line the tree lacks as a custom node under
/// the deepest opening it passes; anything else, the root.
public func nodeById(_ tree: OpeningTree, _ id: String) -> OpeningNode {
  tree.byId[id] ?? lineNode(tree, id) ?? tree.root
}

private func lineNode(_ tree: OpeningTree, _ id: String) -> OpeningNode? {
  if id.isEmpty { return nil }
  return tree.lineNode(id) {
    let sans = id.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
    let (keys, legal) = walkKeys(sans)
    guard legal else { return nil }
    let parent = deepestNodeAlong(tree, sans) ?? tree.root
    return OpeningNode(
      id: id, name: parent.name, eco: parent.eco, sans: sans, key: keys.last!, pathKeys: keys,
      games: 0, depth: parent.depth + 1, custom: true, parentId: parent.id)
  }
}

/// The node and everything above it, the root excluded, shallowest first.
public func ancestorsOf(_ tree: OpeningTree, _ id: String) -> [OpeningNode] {
  var out: [OpeningNode] = []
  var cursor = tree.byId[id]
  while let node = cursor, node.depth > 0 {
    out.insert(node, at: 0)
    cursor = node.parentId.flatMap { tree.byId[$0] }
  }
  return out
}

/// Starred first, then most played: the order at every level of the picker.
public func orderedChildren(_ node: OpeningNode, _ starred: [String]) -> [OpeningNode] {
  let stars = Set(starred)
  return node.children.jsSorted { a, b in
    let star = Double((stars.contains(b.id) ? 1 : 0) - (stars.contains(a.id) ? 1 : 0))
    if star != 0 { return star }
    let games = b.games - a.games
    return games != 0 ? games : Double(JS.localeCompare(a.name, b.name))
  }
}

/// Every node under this one, itself excluded, in picker order.
public func descendantsOf(_ node: OpeningNode) -> [OpeningNode] {
  var out: [OpeningNode] = []
  func visit(_ n: OpeningNode) {
    for child in n.children {
      out.append(child)
      visit(child)
    }
  }
  visit(node)
  return out
}

/// Is this node, or any opening it sits inside, starred?
public func starredWithin(_ tree: OpeningTree, _ id: String, _ starred: [String]) -> Bool {
  let stars = Set(starred)
  return ancestorsOf(tree, id).contains { stars.contains($0.id) }
}
