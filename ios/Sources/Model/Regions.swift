import Book
import ChessCore
import Shared

/// Regions of the opening tree: the second half of `openingTree.ts`.

/// Where a line stands relative to a region.
public enum LineStatus: String, Sendable {
  case reached, onWay, outside
}

struct Region {
  /// The node's own position, and every variation's under it.
  var inside: Set<String>
  /// Every position the book can reach one of those from.
  var approach: Set<String>
}

/// The book as a graph, both ways.
public struct BookGraph: Sendable {
  /// positionKey → the positions one move before it.
  public var parents: [String: [String]]
  /// positionKey → the positions one move after it, with how often each is played.
  public var children: [String: [(key: String, games: Double)]]
}

public func bookGraph(_ index: ReferenceIndex) -> BookGraph {
  index.caches.value("bookGraph") { buildGraph(index) }
}

private func buildGraph(_ index: ReferenceIndex) -> BookGraph {
  var parents: [String: [String]] = [:]
  var children: [String: [(key: String, games: Double)]] = [:]
  func link(_ key: String, _ child: String) {
    var up = parents[child] ?? []
    if !up.contains(key) { up.append(key) }
    parents[child] = up
  }
  if index.linked {
    for (key, entry) in index.entries.entries {
      children[key] = entry.moves.map { ($0.next ?? "", $0.games) }
      for move in entry.moves { if let next = move.next { link(key, next) } }
    }
    return BookGraph(parents: parents, children: children)
  }
  var stack = [START_FEN]
  while let fen = stack.popLast() {
    let key = positionKey(fen)
    if children[key] != nil { continue }
    var list: [(key: String, games: Double)] = []
    children[key] = []
    for move in lookup(index, fen)?.moves ?? [] {
      guard let after = applySan(fen, move.san)?.after else { continue }
      let child = positionKey(after)
      list.append((child, move.games))
      link(key, child)
      if children[child] == nil { stack.append(after) }
    }
    children[key] = list
  }
  return BookGraph(parents: parents, children: children)
}

/// Every position the book can reach one node's own position from.
public func approachOne(_ tree: OpeningTree, _ node: OpeningNode) -> Set<String> {
  if let cached = node.approach { return cached }
  let parents = bookGraph(tree.index).parents
  var out = Set(node.pathKeys)
  var queue = node.pathKeys
  while let key = queue.popLast() {
    for parent in parents[key] ?? [] where !out.contains(parent) {
      out.insert(parent)
      queue.append(parent)
    }
  }
  node.approach = out
  return out
}

/// A node as a region: its own position and its variations', and every
/// position the book can get to one of them from.
func regionOf(_ tree: OpeningTree, _ node: OpeningNode) -> Region {
  if let cached = node.region { return cached }
  let members = [node] + descendantsOf(node)
  var approach = Set<String>()
  for member in members { approach.formUnion(approachOne(tree, member)) }
  let region = Region(inside: Set(members.map(\.key)), approach: approach)
  node.region = region
  return region
}

/// Every position the book can reach the region from.
public func approachKeys(_ tree: OpeningTree, _ node: OpeningNode) -> Set<String> {
  regionOf(tree, node).approach
}

public func lineStatus(_ tree: OpeningTree, _ node: OpeningNode, _ sans: [String]) -> LineStatus {
  if node.depth == 0 { return .reached }
  let region = regionOf(tree, node)
  var fen = START_FEN
  for san in sans {
    guard let move = applySan(fen, san) else { return .outside }
    fen = move.after
    let key = positionKey(fen)
    if region.inside.contains(key) { return .reached }
    if !region.approach.contains(key) { return .outside }
  }
  return .onWay
}

/// The deepest opening a line goes through. Nil when the book names nothing along it.
public func deepestNodeAlong(_ tree: OpeningTree, _ sans: [String]) -> OpeningNode? {
  var best: OpeningNode?
  var fen = START_FEN
  for san in sans {
    guard let move = applySan(fen, san) else { break }
    fen = move.after
    if let found = tree.byKey[positionKey(fen)], best == nil || found.depth >= best!.depth { best = found }
  }
  return best
}

/// The deepest opening inside `within` that a line goes through, else `within`.
public func deepestNodeWithin(_ tree: OpeningTree, _ within: OpeningNode, _ sans: [String]) -> OpeningNode {
  guard let deepest = deepestNodeAlong(tree, sans) else { return within }
  return ancestorsOf(tree, deepest.id).contains { $0.id == within.id } || within.depth == 0 ? deepest : within
}

/// Which of several regions a line belongs to, from one walk of the line.
public func regionsOf(_ tree: OpeningTree, _ nodes: [OpeningNode], _ sans: [String]) -> [String: LineStatus] {
  var out: [String: LineStatus] = [:]
  var keys: [String] = []
  var fen = START_FEN
  var legal = true
  for san in sans {
    guard let move = applySan(fen, san) else {
      legal = false
      break
    }
    fen = move.after
    keys.append(positionKey(fen))
  }
  let last = keys.last ?? positionKey(START_FEN)
  for node in nodes {
    if node.depth == 0 {
      out[node.id] = .reached
      continue
    }
    if !legal {
      out[node.id] = .outside
      continue
    }
    let region = regionOf(tree, node)
    if let at = keys.firstIndex(where: { region.inside.contains($0) }) {
      out[node.id] = keys[..<at].allSatisfy { region.approach.contains($0) } ? .reached : .outside
      continue
    }
    let onWay = keys.allSatisfy { region.approach.contains($0) } && (keys.isEmpty || region.approach.contains(last))
    out[node.id] = onWay ? .onWay : .outside
  }
  return out
}
