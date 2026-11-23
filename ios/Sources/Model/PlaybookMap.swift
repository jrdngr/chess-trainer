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
  /// Its tag, if any: the id of a shelf in `TAG_SHELVES`.
  public var shelf: String?
  /// The hole that grows it, for a locked opening.
  public var gap: Gap?
  public var children: [MapNode]
  /// The opening on the list it stands for, by id, where it is one.
  public var family: String?
  /// An opening of yours that's turned off.
  public var off = false

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

/// The shelves that tag an opening on the Playbook: the ones that say how a game plays.
public let TAG_SHELVES: Set<String> = ["gambits", "systems", "solid", "sharp"]

/// The tag shelf an opening sits on: its own, else the nearest one above it.
public func shelfOf(_ tree: OpeningTree, _ node: OpeningNode) -> Shelf? {
  for each in ancestorsOf(tree, node.id).reversed() {
    if let shelf = SHELVES.first(where: { TAG_SHELVES.contains($0.id) && $0.keys.contains(each.name) }) { return shelf }
  }
  return nil
}

extension AppState {
  /// Whether your Playbook on `side` has the opening `id`: it reaches the opening's position or one named under it,
  /// in any order. The tree shows such an opening as yours, and its page stays open while it is.
  public func hasOpening(_ tree: OpeningTree, side: Color, id: String) -> Bool {
    guard let rep = playbookList.first(where: { $0.color == side }) else { return false }
    return rep.nodes.values.contains { move in
      guard let named = tree.byKey[positionKey(move.fenAfter)] else { return false }
      return ancestorsOf(tree, named.id).contains { $0.id == id }
    }
  }
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
      family: family, off: family.map { state.isOff($0) } ?? false)
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

/// The tree stands on four columns, inside a 20pt margin.
public let MAP_COLUMNS = 4
/// A disc's size.
public let MAP_DISC = 46.0
/// Under a disc with a name: a 7pt gap and the name's two lines.
public let MAP_NAME = 35.0
/// The room under a name for its price or when it grows.
public let MAP_FOOT = 16.0
/// From one row of named openings to the next, and from a row of bare first moves.
public let MAP_PITCH = 128.0
public let MAP_PITCH_BARE = 76.0
/// A link's rail runs this far above the discs it drops to, and stops this short of a disc.
public let MAP_RAIL = 14.0
public let MAP_LINK_GAP = 4.0

/// Whether an opening shows its name under its disc: a first move of yours, for sale or on the
/// way to them shows only the move.
public func mapShowsName(_ node: MapNode) -> Bool {
  !(node.line.count == 1 && (node.owned || node.forSale || node.state == .way))
}

/// The center of column `i` on a tree `width` wide.
public func mapColumn(_ i: Int, width: Double) -> Double {
  let pitch = (width - 63) / Double(MAP_COLUMNS)
  return width / 2 + (Double(i) - Double(MAP_COLUMNS - 1) / 2) * pitch
}

/// Where an opening sits on the drawn tree: its center across, its disc's top, how wide its
/// name may run, and the row of the tree it is on.
public struct MapSpot: Equatable, Sendable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var row: Int
}

/// One rail of a fan and the openings that drop from it.
public struct MapRail: Equatable, Sendable {
  public var y: Double
  public var ids: [String]
}

/// The links from an open opening to its branches: a trunk straight down its column from `from`,
/// and off it one rail for each line of branches.
public struct MapFan: Equatable, Sendable {
  public var parent: String
  public var x: Double
  public var from: Double
  public var rails: [MapRail]
}

public struct MapLayout: Equatable, Sendable {
  public var spots: [String: MapSpot]
  public var fans: [MapFan]
  /// The bottom of each row of the tree.
  public var bottoms: [Double]
  public var height: Double
}

/// The columns a row of `count` branches takes under an opening in column `parent`: one line
/// of up to four, the first under its opening when there is room; more go on lines of three
/// beside the opening's trunk, and the last line holds up to four, ending the trunk.
public func mapColumns(_ count: Int, parent: Int) -> [[Int]] {
  let n = MAP_COLUMNS
  func line(_ m: Int) -> [Int] {
    let start = min(parent, n - m)
    return Array(start..<(start + m))
  }
  guard count > n else { return count == 0 ? [] : [line(count)] }
  let beside = (0..<n).filter { $0 != parent }
  let upper = (count - n + beside.count - 1) / beside.count
  return Array(repeating: beside, count: upper) + [line(count - upper * beside.count)]
}

/// The tree's rows laid out `width` wide. Each row sits under the row above, so
/// opening a branch never moves what is already drawn.
public func mapLayout(_ rows: [[MapNode]], path: [String], width: Double) -> MapLayout {
  let top = 12.0
  let pitch = (width - 63) / Double(MAP_COLUMNS)
  var spots: [String: MapSpot] = [:]
  var fans: [MapFan] = []
  var bottoms: [Double] = []
  var columns: [String: Int] = [:]
  var y = top
  func bottom(_ line: [MapNode], _ y: Double) -> Double {
    y + MAP_DISC + (line.contains(where: mapShowsName) ? MAP_NAME + MAP_FOOT : 0)
  }
  func step(_ line: [MapNode]) -> Double { line.contains(where: mapShowsName) ? MAP_PITCH : MAP_PITCH_BARE }
  for (r, row) in rows.enumerated() {
    var lines: [[(MapNode, Int)]]
    var fan: MapFan?
    if r == 0 {
      lines = stride(from: 0, to: row.count, by: MAP_COLUMNS).map { start in
        row[start..<min(row.count, start + MAP_COLUMNS)].enumerated().map { ($0.element, $0.offset) }
      }
    } else {
      let parentId = path[r - 1]
      let col = columns[parentId] ?? 0
      var rest = row[...]
      lines = mapColumns(row.count, parent: col).map { cols in
        let take = rest.prefix(cols.count)
        rest = rest.dropFirst(cols.count)
        return Array(zip(take, cols))
      }
      if let parent = spots[parentId], let node = rows[r - 1].first(where: { $0.id == parentId }) {
        let from = parent.y + MAP_DISC + (mapShowsName(node) ? MAP_NAME : 0) + MAP_LINK_GAP
        fan = MapFan(parent: parentId, x: parent.x, from: from, rails: [])
      }
    }
    var last = y
    for (i, line) in lines.enumerated() {
      if i > 0 { y += step(lines[i - 1].map(\.0)) }
      for (node, col) in line {
        spots[node.id] = MapSpot(x: mapColumn(col, width: width), y: y, width: pitch - 4, row: r)
        columns[node.id] = col
      }
      fan?.rails.append(MapRail(y: y - MAP_RAIL, ids: line.map(\.0.id)))
      last = y
    }
    if let fan { fans.append(fan) }
    let lastLine = lines.last?.map(\.0) ?? []
    bottoms.append(bottom(lastLine, last))
    y = last + step(lastLine)
  }
  return MapLayout(spots: spots, fans: fans, bottoms: bottoms, height: (bottoms.last ?? top) + top)
}

/// How a link is drawn: to the open path, to an opening of yours, or to one you don't have.
public enum MapLinkKind: Int, Comparable, Sendable {
  case other, owned, path
  public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public struct MapPoint: Equatable, Sendable {
  public var x: Double
  public var y: Double
  public init(_ x: Double, _ y: Double) {
    self.x = x
    self.y = y
  }
}

/// One stroke of the links, its turns drawn round; each piece of a link is drawn once, in the
/// kind of the most important opening it leads to.
public struct MapSegment: Equatable, Sendable {
  public var kind: MapLinkKind
  public var points: [MapPoint]
}

/// The strokes that draw a layout's fans.
public func mapLinks(_ layout: MapLayout, _ rows: [[MapNode]], path: [String]) -> [MapSegment] {
  let onPath = Set(path)
  var kinds: [String: MapLinkKind] = [:]
  for node in rows.joined() { kinds[node.id] = onPath.contains(node.id) ? .path : node.owned ? .owned : .other }
  func best(_ ids: some Sequence<String>) -> MapLinkKind { ids.compactMap { kinds[$0] }.max() ?? .other }
  var out: [MapSegment] = []
  for fan in layout.fans {
    let px = fan.x
    var y = fan.from
    for (i, rail) in fan.rails.enumerated() {
      let spots = rail.ids.compactMap { id in layout.spots[id].map { (id, $0) } }
      let below = fan.rails[i...].flatMap(\.ids)
      let center = spots.first { abs($0.1.x - px) < 0.5 }
      let left = spots.filter { $0.1.x < px - 0.5 }.sorted { $0.1.x > $1.1.x }
      let right = spots.filter { $0.1.x > px + 0.5 }.sorted { $0.1.x < $1.1.x }
      let goesOn = i < fan.rails.count - 1 || center != nil
      let end = goesOn || (!left.isEmpty && !right.isEmpty) ? rail.y : rail.y - MAP_CORNER_ROOM
      out.append(MapSegment(kind: best(below), points: [MapPoint(px, y), MapPoint(px, end)]))
      for side in [left, right] where !side.isEmpty {
        var from = px
        for (j, (id, spot)) in side.enumerated() {
          let drop = spot.y - MAP_LINK_GAP
          var points = j == 0 ? [MapPoint(px, rail.y - MAP_CORNER_ROOM), MapPoint(px, rail.y)] : [MapPoint(from, rail.y)]
          if j == side.count - 1 {
            out.append(MapSegment(kind: kinds[id] ?? .other, points: points + [MapPoint(spot.x, rail.y), MapPoint(spot.x, drop)]))
          } else {
            points.append(MapPoint(spot.x, rail.y))
            out.append(MapSegment(kind: best(side[j...].map(\.0)), points: points))
            out.append(MapSegment(kind: kinds[id] ?? .other, points: [MapPoint(spot.x, rail.y), MapPoint(spot.x, drop)]))
          }
          from = spot.x
        }
      }
      if let (id, spot) = center {
        out.append(MapSegment(kind: kinds[id] ?? .other, points: [MapPoint(px, rail.y), MapPoint(px, spot.y - MAP_LINK_GAP)]))
      }
      y = rail.y
    }
  }
  return out.sorted { $0.kind < $1.kind }
}

/// How far a link's turn reaches each way.
public let MAP_CORNER_ROOM = 8.0
