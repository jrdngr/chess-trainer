import Book
import ChessCore
import Shared

/// The Extensions review's graph: one opening drawn as a grid of moves, laid
/// out by fixed rules so the picture is computed, never hand-tuned.
///
/// - Columns are half-moves from the opening's root.
/// - Rows go depth first: a node's first child carries on along its row, each
///   other child starts a new row below the whole subtree of the one before.
/// - At your move the move you play comes first, then book moves, extensions,
///   and mistakes last. At the opponent's, book replies by share, extensions last.
/// - A move into a position already drawn higher up ends its row with a join.
///   A line past `GRAPH_MAX_PLIES` ends in a "+N" cell.
/// - The Extensions filter keeps only the paths down to an extension.

/// How many plies the graph draws. `Picker.swift` has its own `MAX_PLIES`.
public let GRAPH_MAX_PLIES = 16

public enum CellKind: Equatable, Sendable {
  case move(MoveKind)
  case join
  case more

  public var name: String {
    switch self {
    case .move(let kind): return kind.rawValue
    case .join: return "join"
    case .more: return "more"
    }
  }
}

public struct GraphCell: Equatable, Sendable {
  public var kind: CellKind
  /// The move's node; absent on a join or a "+N".
  public var nodeId: String?
  public var label: String
  /// For a join, the row that already holds the position.
  public var joinRow: Int?
}

public struct GraphRow: Equatable, Sendable {
  /// Where the row forks off: a row and column of the parent's cell. Nil for a top row.
  public var parent: (row: Int, col: Int)?
  /// The column of the row's first cell.
  public var start: Int
  public var cells: [GraphCell]

  public static func == (a: GraphRow, b: GraphRow) -> Bool {
    a.parent?.row == b.parent?.row && a.parent?.col == b.parent?.col && a.start == b.start && a.cells == b.cells
  }
}

private func rank(_ kind: MoveKind) -> Double {
  switch kind {
  case .book: return 0
  case .rare, .past: return 1
  case .mistake: return 2
  }
}

private func shareOf(_ index: ReferenceIndex, _ node: RepMove) -> Double {
  let entry = lookup(index, node.fenBefore)
  let total = totalGamesAt(entry)
  let games = entry?.moves.first { $0.san == node.san }?.games ?? 0
  return total > 0 ? games / total : 0
}

/// A node's children in the order the graph draws them.
public func orderedKids(_ rep: Repertoire, _ index: ReferenceIndex, _ kinds: [String: MoveKind], _ nodeId: String) -> [RepMove] {
  let kids = childrenOf(rep, nodeId)
  if kids.count < 2 { return kids }
  let yours = fenTurn(kids[0].fenBefore) == rep.color
  func r(_ n: RepMove) -> Double { rank(kinds[n.id] ?? .book) }
  return kids.jsSorted { a, b in
    if yours {
      let p = Double((b.preferred ? 1 : 0) - (a.preferred ? 1 : 0))
      return p != 0 ? p : r(a) - r(b)
    }
    let k = r(a) - r(b)
    return k != 0 ? k : shareOf(index, b) - shareOf(index, a)
  }
}

/// Lay out the moves under `rootId`, the opening's root, as rows of cells.
public func layoutGraph(_ rep: Repertoire, _ index: ReferenceIndex, _ kinds: [String: MoveKind], _ rootId: String, extOnly: Bool = false) -> [GraphRow] {
  var holdsExtension: [String: Bool] = [:]
  func hasExt(_ node: RepMove) -> Bool {
    if let known = holdsExtension[node.id] { return known }
    let own = (kinds[node.id] ?? .book) != .book
    let out = own || childrenOf(rep, node.id).contains(where: hasExt)
    holdsExtension[node.id] = out
    return out
  }

  var rows: [GraphRow] = []
  var seen: [String: Int] = [:]
  if let root = rep.nodes[rootId] { seen[positionKey(root.fenAfter)] = -1 }

  func walk(_ nodeId: String, _ col: Int, _ rowIdx: Int?, _ parent: (row: Int, col: Int)?) {
    var kids = orderedKids(rep, index, kinds, nodeId)
    if extOnly { kids = kids.filter(hasExt) }
    for (i, child) in kids.enumerated() {
      var r = rowIdx ?? 0
      if i > 0 || rowIdx == nil {
        rows.append(GraphRow(parent: parent, start: col, cells: []))
        r = rows.count - 1
      }
      if col >= GRAPH_MAX_PLIES {
        rows[r].cells.append(GraphCell(kind: .more, label: "+\(subtreeIds(rep, child.id).count)"))
        continue
      }
      let kind = kinds[child.id] ?? .book
      rows[r].cells.append(GraphCell(kind: .move(kind), nodeId: child.id, label: child.san))
      let key = positionKey(child.fenAfter)
      if let earlier = seen[key], earlier >= 0 {
        rows[r].cells.append(GraphCell(kind: .join, label: "↗\(earlier + 1)", joinRow: earlier))
        continue
      }
      seen[key] = r
      walk(child.id, col + 1, r, (r, col))
    }
  }
  walk(rootId, 0, nil, nil)
  return rows
}

/// Where a node's extension begins: its first move off the book, or nil for a book move.
public func extensionRoot(_ rep: Repertoire, _ kinds: [String: MoveKind], _ nodeId: String) -> RepMove? {
  var found: RepMove?
  for node in pathTo(rep, nodeId).reversed() {
    if (kinds[node.id] ?? .book) == .book { break }
    found = node
  }
  return found
}

/// Every extension's first move in a tree, top of the tree first.
public func extensionRoots(_ rep: Repertoire, _ kinds: [String: MoveKind]) -> [RepMove] {
  nodesInOrder(rep)
    .filter { (kinds[$0.id] ?? .book) != .book }
    .filter { node in node.parentId.map { (kinds[$0] ?? .book) == .book } ?? true }
    .jsSorted { cmp(pathTo(rep, $0.id).count, pathTo(rep, $1.id).count) }
}

/// A kept extension stays reviewed until something under it is newer than the keep.
public func keptCurrent(_ rep: Repertoire, _ node: RepMove) -> Bool {
  guard let keptAt = node.keptAt, keptAt != 0 else { return false }
  return subtreeIds(rep, node.id).allSatisfy { (rep.nodes[$0]?.addedAt ?? 0) <= keptAt }
}
