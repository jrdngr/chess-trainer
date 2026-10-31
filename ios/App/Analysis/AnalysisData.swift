import ChessCore

/// A named book line to inspect and import: `BookLine` in `model/types.ts`.
struct BookLine: Identifiable, Equatable {
  var id: String
  var name: String
  var eco: String?
  /// Which side the line is "for".
  var forColor: ChessCore.Color
  /// SAN moves from the standard start position.
  var moves: [String]
  var summary: String
  var ideas: [String]?
}

/// A famous game the explorer pins to the positions it passes: `ReferenceGame`.
struct ReferenceGame: Identifiable, Equatable {
  var white: String
  var black: String
  var result: String
  var year: Int
  var event: String?
  var moves: [String]
  var id: String { "\(white)|\(black)|\(year)" }
}

/// The book lines that continue the moves played so far.
func bookLinesFrom(_ visible: [String]) -> [BookLine] {
  if visible.isEmpty { return BOOK_LINES }
  return BOOK_LINES.filter { line in visible.indices.allSatisfy { $0 < line.moves.count && line.moves[$0] == visible[$0] } }
}

/// The famous games through a position, at most 8: `attachGames` in `book.ts`.
func topGames(_ fen: String) -> [ReferenceGame] {
  TopGames.byKey[positionKey(fen)] ?? []
}

private enum TopGames {
  static let byKey: [String: [ReferenceGame]] = {
    var map: [String: [ReferenceGame]] = [:]
    for game in REFERENCE_GAMES {
      var fen = START_FEN
      var seen = Set<String>()
      for san in game.moves.prefix(30) {
        let key = positionKey(fen)
        if seen.insert(key).inserted, (map[key]?.count ?? 0) < 8 { map[key, default: []].append(game) }
        guard let move = applySan(fen, san) else { break }
        fen = move.after
      }
    }
    return map
  }()
}
