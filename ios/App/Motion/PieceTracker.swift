import ChessCore

/// Which piece is which from one position to the next, so a moved piece
/// keeps its identity and slides to its new square (`.piece`'s 0.16s
/// left/top transition) rather than vanishing and reappearing.
final class PieceTracker {
  private var fen: String?
  private var ids: [String: Int] = [:]
  private var pieces: [String: BoardPiece] = [:]
  private var next = 0

  /// The id of each square's piece in `fen`, carried over from the last position asked for.
  func ids(_ fen: String, _ now: [String: BoardPiece]) -> [String: Int] {
    if fen == self.fen { return ids }
    var out: [String: Int] = [:]
    var gone = pieces.filter { entry in now[entry.key].map { !same($0, entry.value) } ?? true }
    // Unmoved pieces keep their id.
    for (square, piece) in now where pieces[square].map({ same($0, piece) }) == true { out[square] = ids[square] }
    // A piece that arrived takes the id of one of its kind that left, the nearest first; a promotion takes its pawn's.
    for (square, piece) in now.sorted(by: { $0.key < $1.key }) where out[square] == nil {
      let match = gone.filter { same($0.value, piece) }.min { distance($0.key, square) < distance($1.key, square) }
        ?? gone.filter { $0.value.color == piece.color && $0.value.type == .p }.min { distance($0.key, square) < distance($1.key, square) }
      if let match {
        out[square] = ids[match.key]
        gone[match.key] = nil
      } else {
        next += 1
        out[square] = next
      }
    }
    self.fen = fen
    ids = out.compactMapValues { $0 }
    pieces = now
    for square in now.keys where ids[square] == nil {
      next += 1
      ids[square] = next
    }
    return ids
  }

  private func same(_ a: BoardPiece, _ b: BoardPiece) -> Bool { a.type == b.type && a.color == b.color }

  private func distance(_ a: String, _ b: String) -> Int {
    let x = Array(a.utf8), y = Array(b.utf8)
    return abs(Int(x[0]) - Int(y[0])) + abs(Int(x[1]) - Int(y[1]))
  }
}
