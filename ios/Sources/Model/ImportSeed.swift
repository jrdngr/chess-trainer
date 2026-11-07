import Book
import ChessCore
import Foundation

/// Seeding the Playbook from games played elsewhere: the openings you play
/// most, as rows to add. Only your own moves go in, and only while enough of
/// your games reach them; a move strong players rarely choose, or one the
/// engine calls a mistake, ends the line before it.

/// The least number of your games that must reach a move for it to be kept.
public let SEED_MIN_GAMES = 4
/// How many unchecked rows the list shows.
public let SEED_UNCHECKED_MAX = 8
/// The plies of each game read.
public let SEED_MAX_PLIES = 30
/// How far below the bar an unchecked row may sit: the bar times this.
public let SEED_LOOSE = 0.5

/// The share of your games with a side that must reach your move `number` (1 is your first) for it to be kept:
/// 10% for your first two moves, 5% more for each move after.
public func seedBar(_ number: Int) -> Double {
  0.10 + 0.05 * Double(max(0, number - 2))
}

/// A gap in a Playbook's breadth: a first move as White, or an answer as Black to White's first move.
public enum SeedSlot: Hashable, Sendable {
  case white
  case against(String)

  public var color: Color { self == .white ? .w : .b }
  public var label: String {
    switch self {
    case .white: return "As White"
    case .against(let san): return "Against 1.\(san)"
    }
  }
}

/// One opening to add, for one side: every line of yours in it that clears the bar.
public struct SeedRow: Equatable, Sendable, Identifiable {
  public var name: String
  public var color: Color
  public var slot: SeedSlot
  /// Each line from the start, ending on your move.
  public var lines: [[String]]
  /// How many of your games with this side reached it.
  public var games: Int
  /// Fills a slot your Playbook leaves empty, and clears the full bar: added unless unchecked.
  public var checked: Bool

  public var id: String { "\(color.rawValue)#\(name)" }
}

/// Your games with one side, as a tree of move sequences: how often each move followed each line.
private struct GameTrie {
  var total = 0
  var next: [String: [String: Int]] = [:]

  init(_ games: [ImportedGame], _ color: Color) {
    for game in games where game.userColor == color {
      total += 1
      var path = ""
      for san in game.moves.prefix(SEED_MAX_PLIES) {
        next[path, default: [:]][san, default: 0] += 1
        path = path.isEmpty ? san : "\(path) \(san)"
      }
    }
  }

  /// How many games went down this line.
  func reach(_ sans: [String]) -> Int {
    guard let last = sans.last else { return total }
    return next[sans.dropLast().joined(separator: " ")]?[last] ?? 0
  }
}

/// The share of the book's games that choose `san` here: 0 when the book does not know the position.
private func bookShare(_ index: ReferenceIndex, _ fen: String, _ san: String) -> Double {
  let entry = lookup(index, fen)
  let total = totalGamesAt(entry)
  guard total > 0, let move = entry?.moves.first(where: { $0.san == san }) else { return 0 }
  return move.games / total
}

/// Your lines for one side: each of your moves kept while it clears the bar (times `scale`),
/// is a book move strong players choose, and is no mistake.
private func seedLines(_ trie: GameTrie, _ color: Color, _ index: ReferenceIndex, _ lost: [String: Double], scale: Double) -> [[String]] {
  var out: [[String]] = []
  /// Whether a line was written at or below this point.
  @discardableResult
  func visit(_ fen: String, _ path: [String]) -> Bool {
    let nexts = (trie.next[path.joined(separator: " ")] ?? [:]).sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
    if fenTurn(fen) == color {
      let need = max(Double(SEED_MIN_GAMES), seedBar(path.count / 2 + 1) * scale * Double(trie.total))
      var wrote = false
      for (san, count) in nexts where Double(count) >= need {
        guard bookShare(index, fen, san) >= BOOK_SHARE else { continue }
        if let cost = lost["\(positionKey(fen)) \(san)"], cost > BLUNDER_LIMIT { continue }
        guard let move = applySan(fen, san) else { continue }
        if visit(move.after, path + [move.san]) { wrote = true }
      }
      return wrote
    }
    var wrote = false
    for (san, count) in nexts where count >= SEED_MIN_GAMES {
      guard let move = applySan(fen, san) else { continue }
      if visit(move.after, path + [move.san]) { wrote = true }
    }
    // Your last move here is where the line ends.
    if !wrote && !path.isEmpty {
      out.append(path)
      return true
    }
    return wrote
  }
  visit(START_FEN, [])
  return out
}

/// The slot a line fills: your first move as White, or White's first move you answer as Black.
private func slotOf(_ color: Color, _ path: [String]) -> SeedSlot {
  color == .w ? .white : .against(path.first ?? "")
}

/// Whether a Playbook leaves a slot empty, and the slot is common enough to fill:
/// White always needs a first move; Black needs an answer to each first move strong players choose.
private func slotOpen(_ slot: SeedSlot, _ reps: [Repertoire], _ index: ReferenceIndex) -> Bool {
  let rep = reps.first { $0.color == slot.color }
  switch slot {
  case .white:
    return rep.map { childrenOf($0, nil).isEmpty } ?? true
  case .against(let san):
    guard bookShare(index, START_FEN, san) >= BOOK_SHARE else { return false }
    guard let rep, let first = findChildBySan(rep, nil, san) else { return true }
    return childrenOf(rep, first.id).isEmpty
  }
}

/// One side's openings, as the Playbook would name them.
private func rowsFor(_ lines: [[String]], _ color: Color, _ trie: GameTrie, _ index: ReferenceIndex) -> [SeedRow] {
  var rep = createRepertoire(repertoireName(color), color, "seed_\(color.rawValue)")
  for line in lines { rep = addLine(rep, line, .fixed(.import)).rep }
  return playbookRows(rep, index).compactMap { row in
    guard let first = row.parts.first else { return nil }
    let held = row.parts.flatMap { part in tipsOf(rep, part).map { pathTo(rep, $0).map(\.san) } }
    let games = row.parts.reduce(0) { $0 + trie.reach($1.path) }
    return SeedRow(name: row.name, color: color, slot: slotOf(color, first.path), lines: held, games: games, checked: false)
  }
}

/// The import list: the rows to add, ranked. Checked rows come first: the
/// most-played opening for each slot your Playbook leaves empty, where it
/// clears the bar. Then up to `SEED_UNCHECKED_MAX` other openings you play
/// often: those filling an empty slot first, then by games. An opening
/// your Playbook already has never shows. `lost` is what the engine said each
/// of your moves gives away, keyed as `lossesIn` keys them.
public func seedRows(_ games: [ImportedGame], _ index: ReferenceIndex, _ reps: [Repertoire], lost: [String: Double] = [:]) -> [SeedRow] {
  var full: [SeedRow] = []
  var loose: [SeedRow] = []
  for color in [Color.w, .b] {
    let trie = GameTrie(games, color)
    if trie.total == 0 { continue }
    let have = Set(reps.filter { $0.color == color }.flatMap { playbookRows($0, index).map(\.name) })
    let fresh = { (row: SeedRow) in !have.contains(row.name) }
    full += rowsFor(seedLines(trie, color, index, lost, scale: 1), color, trie, index).filter(fresh)
    loose += rowsFor(seedLines(trie, color, index, lost, scale: SEED_LOOSE), color, trie, index).filter(fresh)
  }
  let byGames = { (a: SeedRow, b: SeedRow) in a.games != b.games ? a.games > b.games : a.id < b.id }

  var checked: [SeedRow] = []
  for row in full.sorted(by: byGames) where !checked.contains(where: { $0.slot == row.slot }) && slotOpen(row.slot, reps, index) {
    var picked = row
    picked.checked = true
    checked.append(picked)
  }
  let taken = Set(checked.map(\.id))
  let fullIds = Set(full.map(\.id))
  // A row that clears the full bar keeps its full lines; one only the loose bar finds keeps the loose ones.
  let rest = (full + loose.filter { !fullIds.contains($0.id) }).filter { !taken.contains($0.id) }
  let open = Dictionary(uniqueKeysWithValues: Set(rest.map(\.slot)).map { ($0, slotOpen($0, reps, index)) })
  let unchecked = rest.sorted { a, b in
    let oa = open[a.slot] ?? false
    let ob = open[b.slot] ?? false
    return oa != ob ? oa : byGames(a, b)
  }
  return checked + unchecked.prefix(SEED_UNCHECKED_MAX)
}

/// Every move of yours in these rows, once each: what the engine is asked about before the list is final.
public func seedMoves(_ rows: [SeedRow]) -> [(fen: String, san: String)] {
  var seen = Set<String>()
  var out: [(fen: String, san: String)] = []
  for row in rows {
    for line in row.lines {
      let fens = walkSan(line).fens
      for (i, san) in line.enumerated() where i < fens.count - 1 && movedBy(i, row.color) {
        let key = "\(positionKey(fens[i])) \(san)"
        if seen.insert(key).inserted { out.append((fens[i], san)) }
      }
    }
  }
  return out
}

extension AppState {
  /// The chosen rows, added to the Playbook as imported moves, with what the engine said of each of your moves.
  /// Returns how many moves went in.
  @discardableResult
  public mutating func addSeedRows(_ rows: [SeedRow], lost: [String: Double] = [:]) -> Int {
    var added = 0
    for row in rows {
      let repId = ensureRepertoire(row.color)
      for line in row.lines {
        let fens = walkSan(line).fens
        let costs = line.indices.map { i in i < fens.count ? lost["\(positionKey(fens[i])) \(line[i])"] : nil }
        added += addLine(repId, line, .fixed(.import), via: .import, lost: costs)
      }
    }
    return added
  }
}
