import ChessCore
import Foundation
import Shared

/// One move row in the book.
public struct ExplorerMove: Equatable, Sendable {
  public var san: String
  public var games: Double
  public var white: Double
  public var draw: Double
  public var black: Double
  /// The key of the position the move leads to, when the book has it.
  public var next: String?
}

public struct ExplorerEntry: Equatable, Sendable {
  public var key: String
  public var opening: String?
  public var eco: String?
  public var moves: [ExplorerMove]
}

public struct OpeningName: Equatable, Sendable {
  public var eco: String
  public var name: String
}

/// One named opening: where it sits, and how often it is played.
public struct CatalogueEntry: Equatable, Sendable {
  /// The defining move order, space-joined: also the opening's id.
  public var id: String
  public var sans: [String]
  public var eco: String
  public var name: String
  public var games: Double
}

/// The reference book: every position it knows by key, and the names on them.
///
/// `prototype/src/model/book.ts` and `reference.ts`. The famous games the web app pins
/// to positions (`topGames`) are left for the explorer screen that shows them.
public final class ReferenceIndex: @unchecked Sendable {
  public let entries: OrderedMap<String, ExplorerEntry>
  public let names: OrderedMap<String, OpeningName>
  /// Every named opening, most played first.
  public let catalogue: [CatalogueEntry]
  public let totalGames: Double
  /// Every book move knows where it leads.
  public let linked: Bool

  init(entries: OrderedMap<String, ExplorerEntry>, names: OrderedMap<String, OpeningName>, catalogue: [CatalogueEntry], totalGames: Double, linked: Bool) {
    self.entries = entries
    self.names = names
    self.catalogue = catalogue
    self.totalGames = totalGames
    self.linked = linked
  }

  /// Caches the model builds on top of the book, one per index.
  public let caches = Caches()

  public final class Caches: @unchecked Sendable {
    private var store: [String: Any] = [:]
    private let lock = NSLock()
    public func value<T>(_ key: String, _ make: () -> T) -> T {
      lock.lock()
      if let found = store[key] as? T { lock.unlock(); return found }
      lock.unlock()
      let made = make()
      lock.lock()
      store[key] = made
      lock.unlock()
      return made
    }
  }
}

public enum BookError: Error {
  case malformed(String)
}

/// Lichess spells it "Defense"; the app spells it "Defence".
func normaliseName(_ name: String) -> String {
  name.replacing(#/\bDefense\b/#, with: "Defence")
}

/// Decode `book.json`. Wire format, as `book.ts` documents it:
///   positions: [positionKey, gamesAtPosition, [[san, shareBp, whitePct, drawPct, next], ...]]
///   names:     [positionKey, sanPath, eco, name]
public func decodeBook(_ data: Data) throws -> ReferenceIndex {
  guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
    let positions = root["positions"] as? [[Any]],
    let nameRows = root["names"] as? [[Any]],
    let version = root["version"] as? Double,
    let totalGames = root["totalGames"] as? Double
  else { throw BookError.malformed("top level") }

  let keys = positions.map { $0.first as? String ?? "" }
  var entries = OrderedMap<String, ExplorerEntry>()
  for row in positions {
    guard row.count == 3, let key = row[0] as? String, let total = row[1] as? Double, let moves = row[2] as? [[Any]] else {
      throw BookError.malformed("position")
    }
    var rows: [ExplorerMove] = moves.map { m in
      let san = m[0] as? String ?? ""
      let bp = m[1] as? Double ?? 0
      let whitePct = m[2] as? Double ?? 0
      let drawPct = m[3] as? Double ?? 0
      let games = JS.round(total * bp / 10_000)
      let white = JS.round(games * whitePct / 100)
      let draw = JS.round(games * drawPct / 100)
      var next: String?
      if m.count > 4, let at = m[4] as? Int, at >= 0, at < keys.count { next = keys[at] }
      return ExplorerMove(san: san, games: games, white: white, draw: draw, black: max(0, games - white - draw), next: next)
    }
    rows.jsSort { cmp($1.games, $0.games) }
    entries[key] = ExplorerEntry(key: key, moves: rows)
  }

  var names = OrderedMap<String, OpeningName>()
  var found: [CatalogueEntry] = []
  for row in nameRows {
    guard row.count == 4, let key = row[0] as? String, let path = row[1] as? String, let eco = row[2] as? String, let raw = row[3] as? String else {
      throw BookError.malformed("name")
    }
    let name = normaliseName(raw)
    names[key] = OpeningName(eco: eco, name: name)
    if var entry = entries[key] {
      entry.eco = eco
      entry.opening = name
      entries[key] = entry
    }
    let sans = path.split(separator: " ").map(String.init)
    // A one-move name is the whole database with a first move: not an opening.
    if sans.count < 2 { continue }
    let games = entries[key]?.moves.reduce(0) { $0 + $1.games } ?? 0
    found.append(CatalogueEntry(id: path, sans: sans, eco: eco, name: name, games: games))
  }

  // One row per name, the most played (then the shortest) where names repeat.
  var byName = OrderedMap<String, CatalogueEntry>()
  for entry in found {
    if let seen = byName[entry.name], !(entry.games > seen.games || (entry.games == seen.games && entry.sans.count < seen.sans.count)) {
      continue
    }
    byName[entry.name] = entry
  }
  let catalogue = byName.values.jsSorted { a, b in
    let games = b.games - a.games
    return games != 0 ? games : Double(JS.localeCompare(a.name, b.name))
  }
  return ReferenceIndex(entries: entries, names: names, catalogue: catalogue, totalGames: totalGames, linked: version >= 2)
}
