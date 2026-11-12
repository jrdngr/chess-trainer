import Book
import ChessCore

/// Book moves: the Playbook holds only moves the book has. Any move the book
/// has is a book move, however rarely it is played.

/// The least share of strong players' games a common move has: what the
/// opponent rolls and the book phase after your prep take.
public let BOOK_SHARE = 0.05
/// Centipawns given away past which a move is a mistake: the line a run ends at.
public let BLUNDER_LIMIT: Double = 80

/// How many moves at the start of a line the book has, for either side.
public func bookLength(_ index: ReferenceIndex, _ sans: [String]) -> Int {
  let fens = walkSan(sans, START_FEN).fens
  for i in sans.indices where i >= fens.count - 1 || !inBook(index, fens[i], sans[i]) { return i }
  return sans.count
}

/// Whether the side playing move `ply` (0 is White's first) is `color`.
public func movedBy(_ ply: Int, _ color: Color) -> Bool {
  (ply % 2 == 0) == (color == .w)
}

/// The moves of a tree the book does not have, highest first: each is
/// removed with everything under it.
public func nonBookMoves(_ rep: Repertoire, _ index: ReferenceIndex) -> [String] {
  var out: [String] = []
  func visit(_ node: RepMove) {
    if !inBook(index, node.fenBefore, node.san) {
      out.append(node.id)
      return
    }
    for kid in childrenOf(rep, node.id) { visit(kid) }
  }
  for root in childrenOf(rep, nil) { visit(root) }
  return out
}

extension AppState {
  /// Removes every move the book does not have, with everything under it,
  /// and what only existed for the positions that went.
  public mutating func removeNonBookMoves(_ index: ReferenceIndex) {
    for repId in repertoireOrder {
      guard let rep = repertoires[repId] else { continue }
      let gone = nonBookMoves(rep, index)
      if gone.isEmpty { continue }
      shrink(repId, { gone.reduce($0) { removeSubtree($0, $1) } }) { before, after in
        AppEvent(kind: "remove-non-book", repertoireId: repId, color: before.color).with(removedBetween(before, after))
      }
    }
  }
}
