import Book
import ChessCore
import Foundation
import Shared

/// The Playbook tab's tree: one side's named openings, nested the way the
/// opening tree nests them, with the openings the curve will add hanging locked
/// where they will appear.

/// What a locked opening waits for.
public enum MapNeed: Equatable, Sendable {
  /// It grows when the curve gets to it; nothing else to meet.
  case inLine
  /// Its level opens at this many games.
  case games(Int)
  /// Its level opens once every opening you have is green: this many are, of these.
  case green(Int, of: Int)
}

/// Where an opening on the tree stands.
public enum MapState: Equatable, Sendable {
  case owned
  /// The curve grows it next, in this many runs.
  case next(runs: Int)
  case locked(MapNeed)
  /// An opening on the list you don't have, for sale at this price.
  case forSale(price: Int)
  /// A first move with none of your openings under it: it holds the ones for sale there.
  case way
}

public struct MapNode: Equatable, Sendable, Identifiable {
  public var id: String
  /// The book's full name.
  public var name: String
  /// The name shown under the disc: the part below its parent's.
  public var label: String
  /// The move inside the disc.
  public var move: String
  public var color: Color
  /// The moves to it.
  public var line: [String]
  public var state: MapState
  /// Its form at your move there, 0...1, for showing; nil before it has enough answers or while locked.
  public var form: Double?
  /// Your lines through it.
  public var lines: Int
  /// The picker shelf it sits on, if any: Sharp, Solid, Gambits or Systems.
  public var shelf: String?
  /// The hole that grows it, for a locked opening.
  public var gap: Gap?
  public var children: [MapNode]
  /// The opening on the list it stands for, by id, where it is one.
  public var family: String?

  public var owned: Bool { state == .owned }
  public var forSale: Bool { if case .forSale = state { true } else { false } }
}

/// The part of a name below another: "Najdorf Variation" under "Sicilian Defense".
public func nameBelow(_ name: String, _ parent: String?) -> String {
  let parts = name.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
  guard parts.count == 2 else { return name }
  let variations = parts[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
  return variations.last ?? name
}

/// The shelf an opening sits on: its own, else the nearest one above it.
public func shelfOf(_ tree: OpeningTree, _ node: OpeningNode) -> Shelf? {
  for each in ancestorsOf(tree, node.id).reversed() {
    if let shelf = SHELVES.first(where: { $0.keys.contains(each.name) }) { return shelf }
  }
  return nil
}

/// One side's tree, its first moves at the top.
public func playbookMap(_ state: AppState, _ tree: OpeningTree, side: Color) -> [MapNode] {
  // With no Playbook on this side yet, every family is for sale.
  let rep = state.playbookList.first(where: { $0.color == side }) ?? createPlaybook("", side, "none")
  // The openings your lines go through, and how many of your lines go through each.
  var owned = Set<String>()
  for node in rep.nodes.values {
    guard let named = tree.byKey[positionKey(node.fenAfter)] else { continue }
    for each in ancestorsOf(tree, named.id) { owned.insert(each.id) }
  }
  // Your own moves to each position, shortest first: an opening you reach in another
  // order than the book's opens at your line, which is the one the Playbook has.
  var yours: [String: [String]] = [:]
  for move in nodesInOrder(rep) {
    let sans = pathTo(rep, move.id).map(\.san)
    let key = positionKey(move.fenAfter)
    if yours[key].map({ sans.count < $0.count }) ?? true { yours[key] = sans }
  }
  var lines: [String: Int] = [:]
  for leaf in leafLines(rep) {
    var through = Set<String>()
    for fen in walkSan(leaf.sans).fens.dropFirst() {
      guard let named = tree.byKey[positionKey(fen)] else { continue }
      for each in ancestorsOf(tree, named.id) { through.insert(each.id) }
    }
    for id in through { lines[id, default: 0] += 1 }
  }
  let atMove = FormAtMove(state.events)
  let next = curvePlaybookGaps(state, tree).first
  let runs = runsUntilGrowth(state)
  let gate = curveGate(state, tree)
  let holes = !rep.nodes.isEmpty && curveSides(state).contains(where: { $0.id == rep.id }) ? curveHoles([rep], tree.index, tree: tree) : []

  // Each hole as the first opening it leads into that you don't have, under the nearest one you do.
  var locked: [String?: [MapNode]] = [:]
  var placed = Set<String>()
  for gap in holes {
    let line = unlockLine(tree, gap, size: 30)
    var fresh: OpeningNode?
    var fen = START_FEN
    for (ply, san) in line.enumerated() {
      guard let move = applySan(fen, san) else { break }
      fen = move.after
      guard ply >= gap.hole.path.count, let named = tree.byKey[positionKey(fen)], !owned.contains(named.id) else { continue }
      fresh = named
      break
    }
    let id = fresh?.id ?? "hole:\(gap.id)"
    guard placed.insert(id).inserted else { continue }
    var parent = fresh.flatMap { $0.parentId }
    while let up = parent, !owned.contains(up), let node = tree.byId[up], node.depth > 0 { parent = node.parentId }
    if fresh == nil { parent = deepestNodeAlong(tree, gap.hole.path)?.id }
    if let up = parent, !owned.contains(up) { parent = nil }
    let need: MapNeed
    switch curveLevel(gap) {
    case 0: need = .inLine
    case let level:
      let games = CURVE_LEVEL_GAMES[level] ?? 0
      need = gate.games < games ? .games(games) : gate.allGreen ? .inLine : .green(gate.green, of: gate.openings)
    }
    let parentName = parent.flatMap { tree.byId[$0]?.name }
    let name = fresh?.name ?? gap.name
    let label = fresh.map { $0.depth == 1 ? moveLabel($0.sans) : nameBelow($0.name, parentName) } ?? moveLabel(gap.line)
    locked[parent, default: []].append(MapNode(
      id: id, name: name, label: label == parentName.map({ nameBelow($0, nil) }) ? moveLabel(gap.line) : label,
      move: fresh?.depth == 1 ? moveLabel(gap.line) : gap.hole.san, color: side, line: gap.line,
      state: next?.id == gap.id ? .next(runs: runs) : .locked(need), form: nil, lines: 0,
      shelf: fresh.flatMap { shelfOf(tree, $0)?.id }, gap: gap, children: [], family: nil))
  }

  func build(_ node: OpeningNode, _ parentName: String?) -> MapNode {
    let kids = node.children.filter { owned.contains($0.id) }.sorted { $0.games > $1.games }
    let label = node.depth == 1 ? moveLabel(node.sans) : nameBelow(node.name, parentName)
    let shown = parentName.map { nameBelow($0, nil) == label } == true ? moveLabel(node.sans) : label
    let family = openingList(side).first { $0.roots.contains(node.sans) }?.id
    return MapNode(
      id: node.id, name: node.name, label: shown, move: node.depth == 1 ? moveLabel(node.sans) : node.sans.last ?? "",
      color: side, line: yours[node.key] ?? node.sans, state: .owned, form: atMove.value(node.key, side), lines: lines[node.id] ?? 0, shelf: shelfOf(tree, node)?.id,
      gap: nil, children: kids.map { build($0, node.name) } + lockedOrder(locked[node.id] ?? []) + forSale[node.id, default: []],
      family: family)
  }

  // The openings on the list you don't have, for sale where they would hang: under the
  // nearest opening of yours on their way, else under their first move, which shows as the
  // way to them when you have nothing there.
  let price = state.families.price(side)
  let have = Set(state.ownedFamilies(side).map(\.id))
  var forSale: [String: [MapNode]] = [:]
  var ways: [MapNode] = []
  for opening in openingList(side) where !have.contains(opening.id) {
    let root = opening.roots[0]
    let named = deepestNodeAlong(tree, root)
    let sale = MapNode(
      id: "sale:\(opening.id)", name: opening.name, label: opening.name, move: root.last ?? "", color: side,
      line: root, state: .forSale(price: price), form: nil, lines: 0, shelf: named.flatMap { shelfOf(tree, $0)?.id },
      gap: nil, children: [], family: opening.id)
    let parent = (1..<root.count).reversed().lazy
      .compactMap { tree.byId[root.prefix($0).joined(separator: " ")] }
      .first { owned.contains($0.id) }?.id
    if let parent {
      forSale[parent, default: []].append(sale)
      continue
    }
    let first = opening.firstMove
    if !ways.contains(where: { $0.id == first }) {
      let node = nodeById(tree, first)
      ways.append(MapNode(
        id: first, name: node.depth == 1 ? node.name : moveLabel([first]), label: moveLabel([first]), move: moveLabel([first]),
        color: side, line: [first], state: .way, form: nil, lines: 0, shelf: nil, gap: nil, children: [], family: nil))
    }
    forSale[first, default: []].append(sale)
  }
  let roots = tree.root.children.filter { owned.contains($0.id) }.sorted { $0.games > $1.games }
  let wayRoots = ways.map { way in
    var way = way
    way.children = forSale[way.id] ?? []
    return way
  }
  return roots.map { build($0, nil) } + lockedOrder(locked[nil] ?? []) + wayRoots
}

/// Locked openings in order: Next first, then as often as you would meet them.
private func lockedOrder(_ nodes: [MapNode]) -> [MapNode] {
  func isNext(_ node: MapNode) -> Bool { if case .next = node.state { return true } else { return false } }
  return nodes.enumerated().sorted { a, b in
    if isNext(a.element) != isNext(b.element) { return isNext(a.element) }
    let ar = a.element.gap?.importance ?? 0, br = b.element.gap?.importance ?? 0
    return ar != br ? ar > br : a.offset < b.offset
  }.map(\.element)
}

/// The rows the tree shows with `path` open: the top row, then the children of
/// each opening on the path, while there are any.
public func mapRows(_ roots: [MapNode], path: [String]) -> [[MapNode]] {
  var rows = [roots]
  var row = roots
  for id in path {
    guard let open = row.first(where: { $0.id == id }), !open.children.isEmpty else { break }
    rows.append(open.children)
    row = open.children
  }
  return rows
}

/// The Home line's opening: what the curve grows next, named as the tree names it, and in how many runs.
public func nextOpening(_ state: AppState, _ tree: OpeningTree) -> (name: String, runs: Int)? {
  guard let node = nextMapNode(state, tree), case .next(let runs) = node.state else { return nil }
  return (nameBelow(node.name, nil), runs)
}

/// When the Next opening grows, for Home's line.
public func nextWhen(_ runs: Int) -> String {
  runs == 0 ? "in your next game" : "in ~\(runs) \(runs == 1 ? "game" : "games")"
}

/// The Next opening on its side's tree, for Home's line to open the tree at.
public func nextMapNode(_ state: AppState, _ tree: OpeningTree) -> MapNode? {
  guard let gap = curvePlaybookGaps(state, tree).first else { return nil }
  func find(_ list: [MapNode]) -> MapNode? {
    for node in list {
      if node.gap?.id == gap.id { return node }
      if let below = find(node.children) { return below }
    }
    return nil
  }
  return find(playbookMap(state, tree, side: gap.color))
}

/// The ids from a top opening down to `id`, or nil when it isn't on the tree.
public func mapPath(_ roots: [MapNode], to id: String) -> [String]? {
  for node in roots {
    if node.id == id { return [id] }
    if let below = mapPath(node.children, to: id) { return [node.id] + below }
  }
  return nil
}

/// The open path after a tap on `id`: a tap on the open opening folds it back
/// to its parent, any other tap opens the one tapped.
public func mapTap(_ roots: [MapNode], path: [String], _ id: String) -> [String] {
  let rows = mapRows(roots, path: path)
  guard let row = rows.firstIndex(where: { $0.contains { $0.id == id } }) else { return path }
  let node = rows[row].first { $0.id == id }!
  if path.last == id, row > 0, !node.children.isEmpty { return Array(path.prefix(row)) }
  return Array(path.prefix(row)) + [id]
}

/// What a locked opening shows under its name: when it grows.
public func mapWhen(_ state: MapState) -> String? {
  switch state {
  case .owned, .forSale, .way: return nil
  case .next(let runs): return runs == 0 ? "Next game" : "~\(runs) \(runs == 1 ? "game" : "games")"
  case .locked(.inLine): return "In line"
  case .locked(.games(let games)): return "Game \(games)"
  case .locked(.green(let green, let of)): return "Green \(green)/\(of)"
  }
}

/* ── layout ── */

/// Where an opening sits on the drawn tree: its center across, its top, and how wide its label may run.
public struct MapSpot: Equatable, Sendable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var row: Int
  /// For the lower tier of a wide row, the top of the row, where its link drops in between the upper tier.
  public var gate: Double?
}

public struct MapLayout: Equatable, Sendable {
  public var spots: [String: MapSpot]
  /// Below each row, where the links to the next row branch out.
  public var bus: [Double]
  public var height: Double
}

/// The most openings a row holds on one tier.
public let MAP_TIER = 4

/// A wide row on two tiers: yours above, locked below; when either holds more
/// than a tier's worth, the row splits in half by rank instead.
public func mapTiers(_ row: [MapNode]) -> (upper: [MapNode], lower: [MapNode])? {
  guard row.count > MAP_TIER else { return nil }
  let mine = row.filter { $0.owned || $0.state == .way }, locked = row.filter { !$0.owned && $0.state != .way }
  if !mine.isEmpty && mine.count <= MAP_TIER && locked.count <= MAP_TIER { return (mine, locked) }
  let half = (row.count + 1) / 2
  return (Array(row.prefix(half)), Array(row.dropFirst(half)))
}

/// The tree's rows laid out `width` wide. Each row sits under the row above, so
/// opening a branch never moves what is already drawn.
public func mapLayout(_ rows: [[MapNode]], width: Double, nodeHeight: Double) -> MapLayout {
  let top = 10.0, fan = 30.0
  var spots: [String: MapSpot] = [:]
  var bus: [Double] = []
  var y = top
  for (r, row) in rows.enumerated() {
    let branches = { (list: [MapNode]) in list.contains { !$0.children.isEmpty } }
    if let tiers = mapTiers(row) {
      // Tiers sit half a step apart, so every link drops through its own lane.
      let most = Double(max(tiers.upper.count, tiers.lower.count))
      let pitch = min(86, (width - 16 - 80) / max(1, most - 0.5))
      let wide = min(80, pitch - 4)
      let same = tiers.upper.count % 2 == tiers.lower.count % 2
      let shift = same ? -pitch / 4 : 0
      func xs(_ list: [MapNode], _ off: Double) -> [Double] {
        list.indices.map { width / 2 + (Double($0) - Double(list.count - 1) / 2) * pitch + off }
      }
      let lowerY = y + nodeHeight + (branches(tiers.upper) ? 22 : 14)
      for (node, x) in zip(tiers.upper, xs(tiers.upper, shift)) {
        spots[node.id] = MapSpot(x: x, y: y, width: wide, row: r, gate: nil)
      }
      for (node, x) in zip(tiers.lower, xs(tiers.lower, same ? pitch / 2 + shift : 0)) {
        spots[node.id] = MapSpot(x: x, y: lowerY, width: wide, row: r, gate: y)
      }
      bus.append(lowerY + nodeHeight + (branches(tiers.lower) ? 16 : 4))
    } else {
      let slot = min(124, (width - 24) / Double(max(1, row.count)))
      let x0 = width / 2 - slot * Double(row.count) / 2
      for (i, node) in row.enumerated() {
        spots[node.id] = MapSpot(x: x0 + slot * (Double(i) + 0.5), y: y, width: slot - 6, row: r, gate: nil)
      }
      bus.append(y + nodeHeight + (branches(row) ? 16 : 4))
    }
    y = bus[r] + fan
  }
  return MapLayout(spots: spots, bus: bus, height: bus.last ?? top)
}
