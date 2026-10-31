import ChessCore
import Shared

/// The Playbook tree: one per side. `src/model/repertoire.ts` and the tree types in `types.ts`.

/// Where a move came from: see `SOURCE_LABELS`.
public enum MoveSource: String, Sendable, Codable, CaseIterable {
  case picker, book, growth, engine, manual, analysis, `import`, play, tidy, board, seed
}

/// A single move in the tree.
public struct RepMove: Equatable, Sendable, Codable {
  public var id: String
  public var parentId: String?
  public var repertoireId: String
  /// FEN of the position this move is played from.
  public var fenBefore: String
  /// positionKey(fenBefore): transpositions collapse on it.
  public var key: String
  public var san: String
  public var uci: String
  public var fenAfter: String
  public var children: [String]
  /// The preferred continuation among siblings.
  public var preferred: Bool
  public var note: String?
  public var source: MoveSource
  public var addedAt: Double
  /// When you kept this reply on Tidy's card.
  public var keptAt: Double?
  /// Centipawns the move gave away against the engine's best, when checked on the way in.
  public var lost: Double?
}

public struct Repertoire: Equatable, Sendable, Codable {
  public var id: String
  public var name: String
  /// The side you play in it.
  public var color: Color
  public var rootFen: String
  public var rootChildren: [String]
  public var nodes: [String: RepMove]
  public var createdAt: Double
}

nonisolated(unsafe) private var idCounter = 0

/// A fresh id: unique within a session, like the prototype's.
public func newId(_ prefix: String = "n") -> String {
  idCounter += 1
  return "\(prefix)_\(String(Int64(Env.now()), radix: 36))_\(String(idCounter, radix: 36))"
}

public func createRepertoire(_ name: String, _ color: Color, _ id: String? = nil) -> Repertoire {
  Repertoire(id: id ?? newId("rep"), name: name, color: color, rootFen: START_FEN, rootChildren: [], nodes: [:], createdAt: Env.now())
}

public func childrenOf(_ rep: Repertoire, _ nodeId: String?) -> [RepMove] {
  let ids = nodeId.map { rep.nodes[$0]?.children ?? [] } ?? rep.rootChildren
  return ids.compactMap { rep.nodes[$0] }
}

public func fenAt(_ rep: Repertoire, _ nodeId: String?) -> String {
  guard let nodeId else { return rep.rootFen }
  return rep.nodes[nodeId]?.fenAfter ?? rep.rootFen
}

/// The moves from the root down to and including `nodeId`.
public func pathTo(_ rep: Repertoire, _ nodeId: String?) -> [RepMove] {
  var out: [RepMove] = []
  var cur = nodeId
  while let id = cur, let node = rep.nodes[id] {
    out.insert(node, at: 0)
    cur = node.parentId
  }
  return out
}

public func findChildBySan(_ rep: Repertoire, _ parentId: String?, _ san: String) -> RepMove? {
  childrenOf(rep, parentId).first { $0.san == san }
}

/// The node a line from the root ends on, or nil when the tree lacks it.
public func nodeAtLine(_ rep: Repertoire, _ sans: [String]) -> RepMove? {
  var parent: String?
  var node: RepMove?
  for san in sans {
    node = findChildBySan(rep, parent, san)
    guard let found = node else { return nil }
    parent = found.id
  }
  return node
}

public struct AddMoveResult {
  public var rep: Repertoire
  public var node: RepMove
  public var created: Bool
}

/// Add one move under `parentId`. Replaying a move returns the node it already has.
public func addMove(_ rep: Repertoire, _ parentId: String?, _ san: String, _ source: MoveSource = .manual) -> AddMoveResult? {
  let fenBefore = fenAt(rep, parentId)
  if let existing = findChildBySan(rep, parentId, san) { return AddMoveResult(rep: rep, node: existing, created: false) }
  guard let move = applySan(fenBefore, san) else { return nil }
  let node = RepMove(
    id: newId(), parentId: parentId, repertoireId: rep.id, fenBefore: fenBefore, key: positionKey(fenBefore),
    san: move.san, uci: move.uci, fenAfter: move.after, children: [],
    // The first move added from a position is the preferred one.
    preferred: childrenOf(rep, parentId).isEmpty, source: source, addedAt: Env.now())
  var next = rep
  next.nodes[node.id] = node
  if let parentId {
    next.nodes[parentId]!.children.append(node.id)
  } else {
    next.rootChildren.append(node.id)
  }
  return AddMoveResult(rep: next, node: node, created: true)
}

/// A move's source, or how to tell it per move.
public enum SourceFor {
  case fixed(MoveSource)
  case each((_ fenBefore: String, _ san: String) -> MoveSource)
}

/// Add a whole SAN line, reusing the nodes it already matches.
public func addLine(_ rep: Repertoire, _ sans: [String], _ source: SourceFor = .fixed(.manual), _ startNodeId: String? = nil) -> (rep: Repertoire, added: Int, tipId: String?) {
  var current = rep
  var parentId = startNodeId
  var added = 0
  for san in sans {
    let tagged: MoveSource
    switch source {
    case .fixed(let s): tagged = s
    case .each(let tell): tagged = tell(fenAt(current, parentId), san)
    }
    guard let res = addMove(current, parentId, san, tagged) else { break }
    current = res.rep
    parentId = res.node.id
    if res.created { added += 1 }
  }
  return (current, added, parentId)
}

/// Keep what the engine said of each move along a line: `lost[i]` is for move i.
public func recordLosses(_ rep: Repertoire, _ sans: [String], _ lost: [Double?]) -> Repertoire {
  var next = rep
  var parentId: String?
  for (i, san) in sans.enumerated() {
    let kids = parentId.map { rep.nodes[$0]?.children ?? [] } ?? rep.rootChildren
    guard let node = kids.compactMap({ rep.nodes[$0] }).first(where: { $0.san == san }) else { break }
    if i < lost.count, let value = lost[i], node.lost != value { next.nodes[node.id]!.lost = value }
    parentId = node.id
  }
  return next
}

/// Remove a node and everything below it.
public func removeSubtree(_ rep: Repertoire, _ nodeId: String) -> Repertoire {
  guard let node = rep.nodes[nodeId] else { return rep }
  var nodes = rep.nodes
  var stack = [nodeId]
  while let id = stack.popLast() {
    guard let n = nodes[id] else { continue }
    stack.append(contentsOf: n.children)
    nodes[id] = nil
  }
  var rootChildren = rep.rootChildren
  if let parentId = node.parentId {
    if var parent = nodes[parentId] {
      let remaining = parent.children.filter { $0 != nodeId }
      parent.children = remaining
      nodes[parentId] = parent
      // A deleted preferred move hands the preference to the first sibling left.
      if node.preferred, let first = remaining.first, !remaining.contains(where: { nodes[$0]?.preferred == true }) {
        nodes[first]?.preferred = true
      }
    }
  } else {
    rootChildren = rep.rootChildren.filter { $0 != nodeId }
    if node.preferred, let first = rootChildren.first, !rootChildren.contains(where: { nodes[$0]?.preferred == true }) {
      nodes[first]?.preferred = true
    }
  }
  var next = rep
  next.nodes = nodes
  next.rootChildren = rootChildren
  return next
}

/// Remove a node, everything below it, and the moves that only led to it.
public func pruneLine(_ rep: Repertoire, _ nodeId: String) -> Repertoire {
  guard let start = rep.nodes[nodeId] else { return rep }
  var next = removeSubtree(rep, nodeId)
  var parentId = start.parentId
  while let id = parentId {
    guard let parent = next.nodes[id], parent.children.isEmpty else { break }
    let grandparent = parent.parentId
    next = removeSubtree(next, id)
    parentId = grandparent
  }
  return next
}

/// How many moves `pruneLine` would take.
public func pruneCount(_ rep: Repertoire, _ nodeId: String) -> Int {
  guard let start = rep.nodes[nodeId] else { return 0 }
  var count = subtreeIds(rep, nodeId).count
  var childId = nodeId
  var parentId = start.parentId
  while let id = parentId {
    guard let parent = rep.nodes[id], !parent.children.contains(where: { $0 != childId }) else { break }
    count += 1
    childId = id
    parentId = parent.parentId
  }
  return count
}

/// Make `nodeId` the preferred move among its siblings.
public func setPreferred(_ rep: Repertoire, _ nodeId: String) -> Repertoire {
  guard let node = rep.nodes[nodeId] else { return rep }
  var next = rep
  for sib in childrenOf(rep, node.parentId) { next.nodes[sib.id]!.preferred = sib.id == nodeId }
  return next
}

public func setNote(_ rep: Repertoire, _ nodeId: String, _ note: String) -> Repertoire {
  guard rep.nodes[nodeId] != nil else { return rep }
  var next = rep
  let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
  next.nodes[nodeId]!.note = trimmed.isEmpty ? nil : trimmed
  return next
}

/// A position where it is your turn and the tree says what to play.
public struct DecisionPoint: Equatable, Sendable {
  public var key: String
  public var fen: String
  public var repertoireId: String
  /// Every move from this position, preferred first.
  public var options: [RepMove]
  /// The shortest path to it, in SAN.
  public var pathSans: [String]
  public var depth: Int
}

/// Every position you answer, once each: a transposition is one, its options merged.
public func decisionPoints(_ rep: Repertoire) -> [DecisionPoint] {
  var byKey = OrderedMap<String, DecisionPoint>()
  func visit(_ nodeId: String?, _ pathSans: [String]) {
    let fen = fenAt(rep, nodeId)
    let kids = childrenOf(rep, nodeId)
    if !kids.isEmpty && fenTurn(fen) == rep.color {
      let key = positionKey(fen)
      if let existing = byKey[key], pathSans.count >= existing.pathSans.count {
        var merged = existing.options
        for kid in kids where !merged.contains(where: { $0.san == kid.san }) { merged.append(kid) }
        byKey[key]!.options = merged
      } else {
        let options = kids.jsSorted { a, b in Double((b.preferred ? 1 : 0) - (a.preferred ? 1 : 0)) }
        byKey[key] = DecisionPoint(key: key, fen: fen, repertoireId: rep.id, options: options, pathSans: pathSans, depth: pathSans.count)
      }
    }
    for kid in kids { visit(kid.id, pathSans + [kid.san]) }
  }
  visit(nil, [])
  return byKey.values.jsSorted { cmp($0.depth, $1.depth) }
}

/// Every line to a tip, longest first.
public func leafLines(_ rep: Repertoire) -> [(tipId: String, sans: [String])] {
  var out: [(tipId: String, sans: [String])] = []
  func visit(_ nodeId: String?, _ sans: [String]) {
    let kids = childrenOf(rep, nodeId)
    if kids.isEmpty, let nodeId {
      out.append((nodeId, sans))
      return
    }
    for kid in kids { visit(kid.id, sans + [kid.san]) }
  }
  visit(nil, [])
  return out.jsSorted { cmp($1.sans.count, $0.sans.count) }
}

/// Every node in the subtree at `nodeId`, itself included.
public func subtreeIds(_ rep: Repertoire, _ nodeId: String) -> [String] {
  var out: [String] = []
  var stack = [nodeId]
  while let id = stack.popLast() {
    guard let n = rep.nodes[id] else { continue }
    out.append(id)
    stack.append(contentsOf: n.children)
  }
  return out
}

/// What a stored tree is called.
public func repertoireName(_ color: Color) -> String {
  color == .w ? "White Playbook" : "Black Playbook"
}
