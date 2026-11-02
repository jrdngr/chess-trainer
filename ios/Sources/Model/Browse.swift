import Book
import ChessCore
import Foundation
import Shared

/// What the opening picker lists below its board.
///
/// Every list is rows that stand for a line: tapping one plays the line out on
/// the board, and a row with rows under it opens them. The picker selects what
/// is on the board, so a row is only ever a way to get the board somewhere.

public enum ReasonKind: String, Sendable {
  case hole, like, style
}

public struct BrowseRow {
  /// Unique within its list.
  public var key: String
  public var label: String
  public var sans: [String]
  public var side: Color
  /// The rows under this one, built when it is opened.
  public var open: (() -> [BrowseItem])?
  /// Why a suggestion is suggested.
  public var why: (text: String, kind: ReasonKind)?

  public init(key: String, label: String, sans: [String], side: Color, open: (() -> [BrowseItem])? = nil, why: (text: String, kind: ReasonKind)? = nil) {
    self.key = key
    self.label = label
    self.sans = sans
    self.side = side
    self.open = open
    self.why = why
  }
}

public enum BrowseItem {
  case head(String)
  case row(BrowseRow)
}

/// "Najdorf" for "Najdorf Variation": the word every opening has is noise in a list.
public func shortName(_ label: String) -> String {
  for word in ["Defence", "Variation", "Opening", "Game"] where label.hasSuffix(" " + word) {
    let short = String(label.dropLast(word.count + 1))
    return short.isEmpty ? label : short
  }
  return label
}

/// The name a line shows under: the book's deepest name along it, as the picker spells it.
public func lineName(_ tree: OpeningTree, _ catalog: PickerCatalog, _ sans: [String]) -> String {
  if sans.isEmpty { return "Any opening" }
  guard let node = tree.byId[sans.joined(separator: " ")] ?? deepestNodeAlong(tree, sans) else { return moveLabel(sans) }
  guard let entry = entryForNode(catalog, node) else { return node.name }
  return shortEntryLabel(entry)
}

/// "Sicilian: Najdorf" for a branch, the family's own name for a family.
func shortEntryLabel(_ entry: PickerEntry) -> String {
  let trail = entryTrail(entry).map { shortName($0.label) }
  return trail.count > 1 ? "\(trail[0]): \(trail[trail.count - 1])" : trail[0]
}

/* ── book ── */

func entryRow(_ catalog: PickerCatalog, _ entry: PickerEntry) -> BrowseRow {
  let groups = entry.level == 0 ? catalog.familyByName[entry.key]?.groups : nil
  var open: (() -> [BrowseItem])?
  if let groups {
    open = {
      groups.map { group in
        .row(BrowseRow(
          key: "group:\(group.id)", label: group.label, sans: group.node?.sans ?? entry.node.sans, side: entry.side,
          open: { group.entries.map { .row(entryRow(catalog, $0)) } }))
      }
    }
  } else if !entry.children.isEmpty {
    open = { entry.children.map { .row(entryRow(catalog, $0)) } }
  }
  return BrowseRow(key: entry.key, label: entry.label, sans: entry.node.sans, side: entry.side, open: open)
}

private let FIRST_MOVES: [(id: FirstMove, head: String)] = [(.e4, "1.e4"), (.d4, "1.d4"), (.flank, "Flank openings")]

/// Every family, under its first move, most played first.
public func bookItems(_ catalog: PickerCatalog) -> [BrowseItem] {
  var out: [BrowseItem] = []
  for (id, head) in FIRST_MOVES {
    out.append(.head(head))
    let families = catalog.families.filter { $0.firstMove == id }.jsSorted { $1.entry.games - $0.entry.games }
    for family in families { out.append(.row(entryRow(catalog, family.entry))) }
  }
  return out
}

/// A shelf's openings, as rows; names the book has since lost are left out.
public func shelfRows(_ catalog: PickerCatalog, _ shelf: Shelf) -> [BrowseRow] {
  shelf.keys.compactMap { catalog.byKey[$0] }.map { entry in
    var row = entryRow(catalog, entry)
    row.label = shortEntryLabel(entry)
    return row
  }
}

/* ── my lines ── */

/// "Exchange Variation" under "Queen's Gambit Declined", not the whole name again.
private func underName(_ name: String, _ parent: String?) -> String {
  guard let parent else { return name }
  for sep in [": ", ", "] where name.hasPrefix(parent + sep) { return String(name.dropFirst(parent.count + sep.count)) }
  if let colon = parent.range(of: ": "), colon.lowerBound > parent.startIndex {
    let head = String(parent[..<colon.upperBound])
    if name.hasPrefix(head) { return String(name.dropFirst(head.count)) }
  }
  return name
}

/// The tree node standing at a line's last position, for ratings and favorites.
public func nodeAt(_ tree: OpeningTree, _ sans: [String]) -> OpeningNode? {
  if let exact = tree.byId[sans.joined(separator: " ")] { return exact }
  let fens = walkSan(sans).fens
  if fens.count != sans.count + 1 { return nil }
  return tree.byKey[positionKey(fens[fens.count - 1])]
}

/// Your own repertoire as names: each side, then its openings, their
/// variations, and the lines of an opening with none. Favorites first.
public func myLines(_ reps: [Repertoire], _ index: ReferenceIndex, _ tree: OpeningTree, _ favorites: [String]) -> [BrowseItem] {
  let stars = Set(favorites)
  let starred = { (sans: [String]) in nodeAt(tree, sans).map { stars.contains($0.id) } ?? false }
  var out: [BrowseItem] = []
  for color in [Color.w, .b] {
    var rows: [BrowseRow] = []
    for rep in reps where rep.color == color {
      func openingRow(_ opening: DerivedOpening, _ parent: String?) -> BrowseRow {
        let lines = opening.variations.isEmpty ? linesOf(rep, opening, index) : []
        var open: (() -> [BrowseItem])?
        if !opening.variations.isEmpty {
          open = { favoritesFirst(opening.variations.map { openingRow($0, opening.name) }, starred).map { .row($0) } }
        } else if lines.count > 1 {
          open = {
            lines.map { line in
              .row(BrowseRow(
                key: "\(rep.id)#\(line.tipId)", label: line.split.map { "\(line.name) · \($0)" } ?? line.name,
                sans: line.path, side: color))
            }
          }
        }
        return BrowseRow(key: opening.id, label: underName(opening.name, parent), sans: opening.path, side: color, open: open)
      }
      rows += openingsIn(rep, index).map { openingRow($0, nil) }
    }
    if rows.isEmpty { continue }
    out.append(.head(color == .w ? "White" : "Black"))
    out += favoritesFirst(rows, starred).map { .row($0) }
  }
  return out
}

private func favoritesFirst(_ rows: [BrowseRow], _ starred: ([String]) -> Bool) -> [BrowseRow] {
  rows.map { (row: $0, star: starred($0.sans)) }
    .jsSorted { Double(($1.star ? 1 : 0) - ($0.star ? 1 : 0)) }
    .map(\.row)
}

/* ── recent ── */


/// Openings you played lately, newest first, under Today, This week and Earlier.
public func recentItems(_ tree: OpeningTree, _ catalog: PickerCatalog, _ score: ScoreState, _ now: Double = Env.now(), _ limit: Int = 40) -> [BrowseItem] {
  let today = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: now / 1000)).timeIntervalSince1970 * 1000
  let played = score.nodes
    .compactMap { id, stats -> (node: OpeningNode, at: Double)? in
      guard let node = tree.byId[id], node.depth > 0, let at = stats.lastAt, at > 0 else { return nil }
      return (node, at)
    }
    .jsSorted { $1.at - $0.at }
    .prefix(limit)
  var out: [BrowseItem] = []
  var head = ""
  for (node, at) in played {
    let group = at >= today ? "Today" : at >= today - 6 * DAY ? "This week" : "Earlier"
    if group != head {
      head = group
      out.append(.head(group))
    }
    out.append(.row(nodeRow(tree, catalog, node)))
  }
  return out
}

private func nodeRow(_ tree: OpeningTree, _ catalog: PickerCatalog, _ node: OpeningNode) -> BrowseRow {
  let entry = entryForNode(catalog, node)
  let open = entry.flatMap { $0.node.id == node.id ? entryRow(catalog, $0).open : nil }
  return BrowseRow(
    key: node.id, label: lineName(tree, catalog, node.sans), sans: node.sans,
    side: sideForPick(catalog, node) ?? .w, open: open)
}

/* ── search ── */

/// "qga" for "Queen's Gambit Accepted".
private func initials(_ name: String) -> String {
  name.split { $0.isWhitespace || $0 == ":" || $0 == "," || $0 == "-" }
    .map { String($0.first!) }
    .joined()
    .lowercased()
}

private func matches(_ needle: String, _ name: String, _ sans: [String], _ eco: String?) -> Bool {
  if name.lowercased().contains(needle) { return true }
  if let eco, eco.lowercased().hasPrefix(needle) { return true }
  let plain = needle.replacing(#/[0-9]+\.+/#, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
  if !plain.isEmpty && sans.joined(separator: " ").lowercased().hasPrefix(plain) { return true }
  return !needle.contains(" ") && needle.count >= 2 && initials(name).hasPrefix(needle)
}

/// Search by name, ECO, moves or initials: your own lines first, then the book.
public func searchItems(_ query: String, _ reps: [Repertoire], _ index: ReferenceIndex, _ tree: OpeningTree, _ catalog: PickerCatalog, _ limit: Int = 40) -> [BrowseItem] {
  let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  if needle.isEmpty { return [] }
  var out: [BrowseItem] = []

  var mine: [BrowseRow] = []
  func walk(_ opening: DerivedOpening, _ color: Color) {
    if matches(needle, opening.name, opening.path, opening.eco) {
      mine.append(BrowseRow(key: "mine:\(opening.id)", label: lineName(tree, catalog, opening.path), sans: opening.path, side: color))
    }
    for v in opening.variations { walk(v, color) }
  }
  for rep in reps { for opening in openingsIn(rep, index) { walk(opening, rep.color) } }
  if !mine.isEmpty { out += [.head("My lines")] + mine.prefix(12).map { .row($0) } }

  let book = catalog.byKey.values
    .filter { matches(needle, $0.key, $0.node.sans, $0.node.eco) }
    .jsSorted { a, b in a.level != b.level ? Double(a.level - b.level) : b.games - a.games }
    .prefix(limit)
    .map { entry in
      var row = entryRow(catalog, entry)
      row.label = shortEntryLabel(entry)
      return BrowseItem.row(row)
    }
  if !book.isEmpty { out += [.head("Book")] + book }
  return out
}

/* ── next moves ── */

public struct NextMove: Sendable {
  public var san: String
  /// "3.Nc3" or "3...Nf6".
  public var label: String
  /// Share of book games at this position, 0 to 100.
  public var share: Double
  /// Where it goes, by name, or "" when the book names nothing near.
  public var name: String
  /// Your repertoire plays it here.
  public var mine: Bool
}

/// Every move your repertoires play, as position|san.
public func repMoves(_ reps: [Repertoire]) -> Set<String> {
  Set(reps.flatMap { $0.nodes.values.map { "\($0.key)|\($0.san)" } })
}

/// The book's moves from a position, most played first.
func mostPlayed(_ index: ReferenceIndex, _ fen: String) -> [ExplorerMove] {
  (lookup(index, fen)?.moves ?? []).jsSorted { $1.games - $0.games }
}

/// The book's moves from a position, most played first, each named for where it
/// goes: its own name when the book names the position, else the names a couple
/// of plies on.
public func nextMoves(_ index: ReferenceIndex, _ tree: OpeningTree, _ catalog: PickerCatalog, _ sans: [String], _ mine: Set<String>) -> [NextMove] {
  let fen = walkSan(sans).fens.last ?? START_FEN
  let key = positionKey(fen)
  let moves = mostPlayed(index, fen)
  let total = moves.reduce(0) { $0 + $1.games }
  let here = deepestNodeAlong(tree, sans)
  return moves.prefix(14).map { move in
    let line = sans + [move.san]
    return NextMove(
      san: move.san, label: moveLabel(line), share: total != 0 ? move.games / total * 100 : 0,
      name: whereItGoes(index, tree, catalog, line, here), mine: mine.contains("\(key)|\(move.san)"))
  }
}

private func whereItGoes(_ index: ReferenceIndex, _ tree: OpeningTree, _ catalog: PickerCatalog, _ line: [String], _ here: OpeningNode?) -> String {
  let beyond = { (node: OpeningNode) in node.id != here?.id && node.depth > (here?.depth ?? 0) }
  if let exact = nodeAt(tree, line), beyond(exact) { return lineName(tree, catalog, exact.sans) }
  // Unnamed: look a few plies on along the book's most played moves.
  var frontier = [walkSan(line).fens.last!]
  var found: [String] = []
  var ply = 0
  while ply < 4 && found.count < 2 && !frontier.isEmpty {
    var next: [String] = []
    for fen in frontier {
      for move in mostPlayed(index, fen).prefix(3) {
        guard let after = applySan(fen, move.san)?.after else { continue }
        if let node = tree.byKey[positionKey(after)], beyond(node) {
          let name = shortName(entryForNode(catalog, node)?.label ?? node.name)
          if !found.contains(name) && found.count < 2 { found.append(name) }
        } else {
          next.append(after)
        }
      }
    }
    frontier = Array(next.prefix(9))
    ply += 1
  }
  return found.joined(separator: " · ")
}
