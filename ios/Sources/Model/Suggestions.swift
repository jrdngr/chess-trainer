import Book
import ChessCore
import Foundation
import Shared

/// The picker's suggestions: the second half of `src/model/browse.ts`.

private struct Suggestion {
  var row: BrowseRow
  /// How often you would face it without an answer: 0 to 1.
  var need: Double = 0
  var needText: String?
  /// Shares a structure with or transposes into something you play.
  var fit: Double = 0
  var fitText: String?
  /// Plays like something you play a lot.
  var style: Double = 0
  var styleText: String?
}

/// A reply under this share of book games at its position is not a hole worth filling.
private let HOLE_SHARE = 0.08
/// Nor is one you would meet in under this share of your games.
private let HOLE_REACH = 0.02

/// A repertoire's moves in the order they were added: each line's new moves
/// after the lines before it, which is the tree read depth first.
private func nodesInOrder(_ rep: Repertoire) -> [RepMove] {
  var out: [RepMove] = []
  func visit(_ node: RepMove) {
    out.append(node)
    for kid in childrenOf(rep, node.id) { visit(kid) }
  }
  for root in childrenOf(rep, nil) { visit(root) }
  return out
}

/// How played a node is, 0 to 1, flattened so a line deep in the tree still counts.
private func popularity(_ index: ReferenceIndex, _ node: OpeningNode) -> Double {
  let total = index.totalGames != 0 ? index.totalGames : 1
  return min(1, (node.games / total).squareRoot())
}

private func candidateRow(_ node: OpeningNode, _ side: Color) -> BrowseRow {
  BrowseRow(key: node.id, label: "", sans: node.sans, side: side)
}

/// Follow the book's most played move until it reaches a name, a few plies at most.
private func namedAfter(_ index: ReferenceIndex, _ tree: OpeningTree, _ sans: [String], _ plies: Int = 4) -> OpeningNode? {
  var line = sans
  var fen = walkSan(line).fens.last!
  for _ in 0..<plies {
    guard let top = mostPlayed(index, fen).first, let after = applySan(fen, top.san)?.after else { break }
    line.append(top.san)
    fen = after
    if let node = tree.byKey[positionKey(after)] { return tree.byId[line.joined(separator: " ")] ?? node }
  }
  return nil
}

/// Holes: book replies your repertoire meets often and has no answer to.
private func holeCandidates(_ reps: [Repertoire], _ index: ReferenceIndex, _ tree: OpeningTree) -> [Suggestion] {
  var out: [Suggestion] = []
  var sides = reps
  // No Black repertoire at all still faces 1.e4: an empty one finds those holes.
  if !reps.contains(where: { $0.color == .b }) {
    sides.append(Repertoire(id: "", name: "", color: .b, rootFen: START_FEN, rootChildren: [], nodes: [:], createdAt: 0))
  }

  for rep in sides {
    var byKey: [String: [RepMove]] = [:]
    for node in nodesInOrder(rep) { byKey[node.key, default: []].append(node) }
    var seen: Set<String> = []
    // Positions with the opponent to move: what they play, and where you go from there.
    func visit(_ fen: String, _ sans: [String], _ reach: Double) {
      let key = positionKey(fen)
      if seen.contains(key) { return }
      seen.insert(key)
      let moves = lookup(index, fen)?.moves ?? []
      let total = moves.reduce(0) { $0 + $1.games }
      if total == 0 { return }
      for move in moves {
        let share = move.games / total
        guard let after = applySan(fen, move.san)?.after else { continue }
        let answers = byKey[positionKey(after)] ?? []
        let line = sans + [move.san]
        if !answers.isEmpty {
          for answer in answers { visit(answer.fenAfter, line + [answer.san], reach * share) }
          continue
        }
        if share < HOLE_SHARE || reach * share < HOLE_REACH { continue }
        guard let target = namedAfter(index, tree, line) else { continue }
        let first = sans.isEmpty || (rep.color == .w && sans.count == 1)
        out.append(Suggestion(
          row: candidateRow(target, rep.color), need: reach * share,
          needText: first
            ? "Nothing yet against \(moveLabel(line))"
            : "\(moveLabel(line)) in \(JS.string(JS.round(share * 100)))% of book games"))
      }
    }
    if rep.color == .b {
      visit(START_FEN, [], 1)
    } else {
      for root in childrenOf(rep, nil) { visit(root.fenAfter, [root.san], 1) }
    }
  }
  return out
}

/// Families named for a first move rather than for anybody's plan.
private let GENERIC_FAMILIES: Set<String> = [
  "King's Pawn Game", "Queen's Pawn Game", "Indian Defence", "King's Knight Opening", "Zukertort Opening", "Horwitz Defence",
]
/// Branch names that say where in the book a line is, not what it is:
/// `/^(Normal|Main Line|Modern Line|Modern Variations?|Open|Closed|Traditional|Accepted|Declined)\b/`.
private let GENERIC_BRANCH = [
  "Normal", "Main Line", "Modern Line", "Modern Variations", "Modern Variation", "Open", "Closed", "Traditional", "Accepted",
  "Declined",
]

private func genericBranch(_ label: String) -> Bool {
  GENERIC_BRANCH.contains { word in
    guard label.hasPrefix(word) else { return false }
    // JavaScript's \b: the next character, if any, is not a word character.
    guard let next = label.dropFirst(word.count).unicodeScalars.first else { return true }
    return !(next.isASCII && (CharacterSet.alphanumerics.contains(next) || next == "_"))
  }
}

private func generic(_ entry: PickerEntry) -> Bool {
  GENERIC_FAMILIES.contains(entry.family) || (entry.level > 0 && genericBranch(entry.label))
}

/// The opening a repertoire line is filed under, for "your Najdorf": the
/// family, or its branch where the family is too big to say much on its own.
private func yourName(_ catalog: PickerCatalog, _ node: OpeningNode?) -> String {
  guard let node else { return "" }
  guard let entry = entryForNode(catalog, node) else { return shortName(node.name) }
  let trail = entryTrail(entry)
  let family = trail[0]
  let branch = trail.count > 1 ? trail[1] : nil
  let big = catalog.familyByName[family.key]?.groups != nil
  if let branch, big || GENERIC_FAMILIES.contains(family.key), !genericBranch(branch.label) { return shortName(branch.label) }
  return shortName(family.label)
}

/// Lines the book reaches your positions from, that your repertoire never plays.
private func transposeCandidates(_ reps: [Repertoire], _ index: ReferenceIndex, _ tree: OpeningTree, _ catalog: PickerCatalog) -> [Suggestion] {
  let graph = bookGraph(index)
  var out: [Suggestion] = []
  for rep in reps {
    let nodes = nodesInOrder(rep)
    let mine = Set(nodes.map { positionKey($0.fenAfter) })
    var found: Set<String> = []
    for node in nodes where plyOf(rep, node) >= 6 {
      var layer = [positionKey(node.fenAfter)]
      var up = 0
      while up < 4 && !layer.isEmpty {
        var next: [String] = []
        for key in layer {
          for parent in graph.parents[key] ?? [] {
            if mine.contains(parent) { continue }
            next.append(parent)
            guard let named = tree.byKey[parent], named.depth >= 3, !found.contains(named.id) else { continue }
            if sideForPick(catalog, named) != rep.color { continue }
            // Your own move order already gets there: it is no new line.
            if named.pathKeys.allSatisfy({ mine.contains($0) || $0 == parent }) { continue }
            found.insert(named.id)
            let into = yourName(catalog, deepestNodeAlong(tree, pathOf(rep, node)))
            out.append(Suggestion(row: candidateRow(named, rep.color), fit: popularity(index, named), fitText: "Transposes into your \(into)"))
          }
        }
        layer = Array(next.prefix(40))
        up += 1
      }
    }
  }
  return out
}

private func plyOf(_ rep: Repertoire, _ node: RepMove) -> Int {
  pathOf(rep, node).count
}

private func pathOf(_ rep: Repertoire, _ node: RepMove) -> [String] {
  var out: [String] = []
  var cursor: RepMove? = node
  while let at = cursor {
    out.insert(at.san, at: 0)
    cursor = at.parentId.flatMap { rep.nodes[$0] }
  }
  return out
}

/// What `structureAfter` has worked out, per catalogue entry.
private final class StructureCache: @unchecked Sendable {
  private var store: [String: String?] = [:]
  private let lock = NSLock()
  func value(_ key: String, _ make: () -> String?) -> String? {
    if let known = lock.withLock({ store[key] }) { return known }
    let made = make()
    lock.withLock { store[key] = made }
    return made
  }
}

/// The structure an entry's main line settles into, six plies past its own position.
private func structureAfter(_ index: ReferenceIndex, _ entry: PickerEntry) -> String? {
  index.caches.value("browseStructures") { StructureCache() }.value(entry.key) {
    var fen = walkSan(entry.node.sans).fens.last!
    for _ in 0..<6 {
      guard let top = mostPlayed(index, fen).first, let after = applySan(fen, top.san)?.after else { break }
      fen = after
    }
    return structureOf(fen)?.template.id
  }
}

/// A family and its branches, for the candidates read off the whole catalogue.
private func familyEntries(_ family: PickerFamily) -> [PickerEntry] {
  [family.entry] + family.entry.children
}

/// Openings whose pawns settle the way your lines do.
private func structureCandidates(_ reps: [Repertoire], _ index: ReferenceIndex, _ tree: OpeningTree, _ catalog: PickerCatalog) -> [Suggestion] {
  var out: [Suggestion] = []
  for rep in reps {
    let nodes = nodesInOrder(rep)
    var yours: [String: String] = [:]
    for node in nodes where node.children.isEmpty {
      guard let structure = structureOf(node.fenAfter), yours[structure.template.id] == nil else { continue }
      yours[structure.template.id] = yourName(catalog, deepestNodeAlong(tree, pathOf(rep, node)))
    }
    if yours.isEmpty { continue }
    let mine = Set(nodes.map { positionKey($0.fenAfter) })
    for family in catalog.families {
      for entry in familyEntries(family) {
        if !entry.exact || entry.side != rep.color || mine.contains(entry.node.key) || generic(entry) { continue }
        guard let id = structureAfter(index, entry), let anchor = yours[id] else { continue }
        out.append(Suggestion(row: candidateRow(entry.node, rep.color), fit: popularity(index, entry.node), fitText: "Same structure as your \(anchor)"))
      }
    }
  }
  return out
}

/// Openings as sharp or as quiet as the ones you play most.
private func styleCandidates(_ reps: [Repertoire], _ index: ReferenceIndex, _ tree: OpeningTree, _ catalog: PickerCatalog) -> [Suggestion] {
  var out: [Suggestion] = []
  for rep in reps {
    let mine = Set(rep.nodes.values.map { positionKey($0.fenAfter) })
    let anchors = openingsIn(rep, index).prefix(3).compactMap { opening -> (entry: PickerEntry, name: String)? in
      let node = nodeAt(tree, opening.path)
      guard let entry = node.flatMap({ entryForNode(catalog, $0) }) else { return nil }
      return (entry, yourName(catalog, node))
    }
    for anchor in anchors {
      let sharp = anchor.entry.sharpness
      let word = sharp >= 4 ? "Sharp" : sharp <= 2 ? "Quiet" : "Balanced"
      for family in catalog.families where family.entry.key != anchor.entry.family {
        for entry in familyEntries(family) {
          if !entry.exact || entry.side != rep.color || mine.contains(entry.node.key) || generic(entry) { continue }
          // White picks its first move: a style match that starts elsewhere is a new repertoire, not a new line.
          if rep.color == .w && entry.node.sans.first != anchor.entry.node.sans.first { continue }
          let diff = abs(entry.sharpness - sharp)
          if diff > 1 { continue }
          out.append(Suggestion(
            row: candidateRow(entry.node, rep.color),
            style: (diff == 0 ? 1 : 0.5) * popularity(index, entry.node), styleText: "\(word) like your \(anchor.name)"))
        }
      }
    }
  }
  return out
}

private let WEIGHTS = (need: 1.0, fit: 0.6, style: 0.35)

/// One list of openings worth a look, each with the reason it is there.
///
/// Every candidate gets one blended score — how often you would face it
/// unprepared, how much it shares with what you play, how well it suits your
/// style — and is labeled by whichever part of that score is biggest. The list
/// is then dealt out so no label comes up more than twice in a row.
public func suggestions(_ reps: [Repertoire], _ index: ReferenceIndex, _ tree: OpeningTree, _ catalog: PickerCatalog, _ limit: Int = 30) -> [BrowseRow] {
  var merged = OrderedMap<String, Suggestion>()
  let all = holeCandidates(reps, index, tree) + transposeCandidates(reps, index, tree, catalog)
    + structureCandidates(reps, index, tree, catalog) + styleCandidates(reps, index, tree, catalog)
  for c in all {
    let id = "\(c.row.side.rawValue)|\(c.row.key)"
    guard var had = merged[id] else {
      merged[id] = c
      continue
    }
    if c.need > had.need { (had.need, had.needText) = (c.need, c.needText) }
    if c.fit > had.fit { (had.fit, had.fitText) = (c.fit, c.fitText) }
    if c.style > had.style { (had.style, had.styleText) = (c.style, c.styleText) }
    merged[id] = had
  }

  let scored = merged.values.map { c -> (row: BrowseRow, score: Double) in
    let parts: [(kind: ReasonKind, value: Double, text: String?)] = [
      (.hole, c.need * WEIGHTS.need, c.needText),
      (.like, c.fit * WEIGHTS.fit, c.fitText),
      (.style, c.style * WEIGHTS.style, c.styleText),
    ]
    let top = parts.dropFirst().reduce(parts[0]) { a, b in b.value > a.value ? b : a }
    var row = c.row
    row.key = "\(c.row.side.rawValue):\(c.row.key)"
    row.label = lineName(tree, catalog, c.row.sans)
    row.why = (top.text ?? "", top.kind)
    if let node = tree.byId[c.row.key], let entry = catalog.byNode[node.id] { row.open = entryRow(catalog, entry).open }
    return (row, parts.reduce(0) { $0 + $1.value })
  }
  let sorted = scored.jsSorted { a, b in
    a.score != b.score ? b.score - a.score : Double(JS.localeCompare(a.row.label, b.row.label))
  }
  return Array(mixLabels(sorted.map(\.row)).prefix(limit))
}

/// Deal rows out best first, but never three of the same label in a row.
public func mixLabels(_ rows: [BrowseRow]) -> [BrowseRow] {
  var left = rows
  var out: [BrowseRow] = []
  while !left.isEmpty {
    let last = out.suffix(2).map { $0.why?.kind }
    let run = last.count == 2 && last[0] != nil && last[0] == last[1] ? last[0] : nil
    let at = run.map { run in left.firstIndex { $0.why?.kind != run } ?? 0 } ?? 0
    out.append(left.remove(at: at))
  }
  return out
}
