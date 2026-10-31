import ChessCore
import Shared

/// Reading the book: `src/model/reference.ts`.

/// A name, plus how deep into the line it was recognised.
public struct NamedLine: Equatable, Sendable {
  public var eco: String
  public var name: String
  /// Plies matched. 1 is "Queen's Pawn Opening"; 8 is a real variation.
  public var ply: Int
}

/// The deepest name the book gives along a line, and the ply it was given at.
public func deepestName(_ index: ReferenceIndex, _ sans: [String], _ startFen: String = START_FEN) -> NamedLine? {
  var fen = startFen
  var best = index.names[positionKey(fen)].map { NamedLine(eco: $0.eco, name: $0.name, ply: 0) }
  var ply = 0
  for san in sans {
    guard let move = applySan(fen, san) else { break }
    fen = move.after
    ply += 1
    if let named = index.names[positionKey(fen)] { best = NamedLine(eco: named.eco, name: named.name, ply: ply) }
  }
  return best
}

/// The family a name belongs to: "Sicilian Defence: Najdorf Variation" is a Sicilian Defence.
public func familyName(_ index: ReferenceIndex, _ name: String) -> String {
  families(index)[name] ?? name
}

private func families(_ index: ReferenceIndex) -> [String: String] {
  index.caches.value("families") {
    var seen = Set<String>()
    var names: [String] = []
    for named in index.names.values where seen.insert(named.name).inserted { names.append(named.name) }
    let standalone = names.filter { !$0.contains(": ") }
    var map: [String: String] = [:]
    for name in names {
      guard let at = name.range(of: ": ") else {
        map[name] = name
        continue
      }
      let prefix = String(name[..<at.lowerBound])
      // The shortest opening the catalogue names with this prefix.
      let found = standalone
        .filter { $0 == prefix || $0.hasPrefix(prefix + " ") }
        .jsSorted { cmp($0.utf16.count, $1.utf16.count) }
        .first
      map[name] = found ?? prefix
    }
    return map
  }
}

/// Every name the book attaches along a line, shallowest first.
public func namesAlong(_ index: ReferenceIndex, _ sans: [String], _ startFen: String = START_FEN) -> [NamedLine] {
  var fen = startFen
  var out: [NamedLine] = []
  var ply = 0
  for san in sans {
    guard let move = applySan(fen, san) else { break }
    fen = move.after
    ply += 1
    if let named = index.names[positionKey(fen)] { out.append(NamedLine(eco: named.eco, name: named.name, ply: ply)) }
  }
  return out
}

/// The deepest opening name on the path to a position.
public func openingNameForPath(_ index: ReferenceIndex, _ sans: [String], _ startFen: String = START_FEN) -> OpeningName? {
  deepestName(index, sans, startFen).map { OpeningName(eco: $0.eco, name: $0.name) }
}

/// The book's name for this exact position, if it has one.
public func nameAt(_ index: ReferenceIndex, _ fen: String) -> OpeningName? {
  index.names[positionKey(fen)]
}

public func lookup(_ index: ReferenceIndex, _ fen: String) -> ExplorerEntry? {
  index.entries[positionKey(fen)]
}

public func totalGamesAt(_ entry: ExplorerEntry?) -> Double {
  entry?.moves.reduce(0) { $0 + $1.games } ?? 0
}

/// A game count, short: "1.3M", "52k".
public func formatGameCount(_ n: Double) -> String {
  if n >= 1_000_000 { return JS.toFixed(n / 1_000_000, n >= 10_000_000 ? 0 : 1) + "M" }
  if n >= 1_000 { return JS.toFixed(n / 1_000, n >= 10_000 ? 0 : 1) + "k" }
  return JS.string(n)
}

public func movePercent(_ move: ExplorerMove, _ total: Double) -> Double {
  total != 0 ? move.games / total * 100 : 0
}
