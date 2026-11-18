import Book
import ChessCore

/// Growth's answers: what the book offers at a hole. The holes are in `Holes.swift`.

/// The family heading for a line: the shallowest name past the first move.
public func family(_ index: ReferenceIndex, _ sans: [String]) -> NamedLine? {
  let names = namesAlong(index, sans)
  guard var found = names.first(where: { $0.ply >= 2 }) ?? names.last else { return nil }
  found.name = familyName(index, found.name)
  return found
}

/// The book's answers at a position, most played first.
public func optionsAt(_ index: ReferenceIndex, _ fen: String, _ limit: Int = 4) -> [Reply] {
  Array(popularReplies(index, fen, 0).prefix(limit))
}

/// What a run offers you at a hole: the book's answers, none past the book.
public func choicesAt(_ index: ReferenceIndex, _ fen: String, _ limit: Int = 4) -> [Reply] {
  optionsAt(index, fen, limit)
}

/// The book's arrows at a position: each piece's most played move, up to `count` pieces.
public func movesToDraw(_ index: ReferenceIndex, _ fen: String, _ count: Int = 3) -> [DrawnMove] {
  onePerPiece(fen, popularReplies(index, fen, 0).map(\.san), count).map { DrawnMove(san: $0.san, from: $0.from, to: $0.to) }
}

/// The best of each piece's moves among `sans`, for arrows.
public func onePerPiece(_ fen: String, _ sans: [String], _ count: Int = .max) -> [(san: String, from: String, to: String)] {
  var out: [(san: String, from: String, to: String)] = []
  var pieces = Set<String>()
  for san in sans {
    if out.count >= count { break }
    guard let move = applySan(fen, san), !pieces.contains(move.from) else { continue }
    pieces.insert(move.from)
    out.append((san, move.from, move.to))
  }
  return out
}
