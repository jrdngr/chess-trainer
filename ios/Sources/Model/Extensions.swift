import Book
import ChessCore

/// Extensions: the moves in your Playbook that are not book moves. `src/model/extensions.ts`.

/// The least share of strong players' games a book move has: `openingRun.ts`.
public let BOOK_SHARE = 0.05
/// Centipawns given away past which a move is a mistake: the line a run ends at.
public let BLUNDER_LIMIT: Double = 80

public enum MoveKind: String, Sendable {
  case book, rare, mistake, past
}

/// What a move is at its own position, with what the engine said when it has said it.
public func moveKind(_ index: ReferenceIndex, _ fenBefore: String, _ san: String, _ lost: Double? = nil) -> MoveKind {
  if let lost, lost > BLUNDER_LIMIT { return .mistake }
  let entry = lookup(index, fenBefore)
  let total = totalGamesAt(entry)
  guard let entry, total > 0 else { return .past }
  guard let move = entry.moves.first(where: { $0.san == san }) else { return .rare }
  return move.games / total >= BOOK_SHARE ? .book : .rare
}

/// Under an extension a move the book would play is still an extension, read as rare.
private func underExtension(_ kind: MoveKind) -> MoveKind {
  kind == .book ? .rare : kind
}

/// Each move of a line by kind, for the player of `color`. The opponent's always read as book.
public func lineKinds(_ index: ReferenceIndex, _ sans: [String], _ color: Color, _ lost: [Double?] = []) -> [MoveKind] {
  let fens = walkSan(sans, START_FEN).fens
  var out: [MoveKind] = []
  var off = false
  var i = 0
  while i < sans.count && i < fens.count - 1 {
    defer { i += 1 }
    if !movedBy(i, color) {
      out.append(.book)
      continue
    }
    let kind = moveKind(index, fens[i], sans[i], i < lost.count ? lost[i] : nil)
    out.append(off ? underExtension(kind) : kind)
    off = off || kind != .book
  }
  return out
}

/// How many moves at the start of a line are book moves.
public func bookLength(_ kinds: [MoveKind]) -> Int {
  kinds.firstIndex { $0 != .book } ?? kinds.count
}

/// Every move of a tree by kind, keyed by node id.
public func treeKinds(_ rep: Repertoire, _ index: ReferenceIndex) -> [String: MoveKind] {
  var out: [String: MoveKind] = [:]
  func visit(_ node: RepMove, _ off: Bool) {
    let own = fenTurn(node.fenBefore) == rep.color ? moveKind(index, node.fenBefore, node.san, node.lost) : .book
    out[node.id] = off ? underExtension(own) : own
    for kid in childrenOf(rep, node.id) { visit(kid, off || own != .book) }
  }
  for root in childrenOf(rep, nil) { visit(root, false) }
  return out
}

/// Whether the side playing move `ply` (0 is White's first) is `color`.
public func movedBy(_ ply: Int, _ color: Color) -> Bool {
  (ply % 2 == 0) == (color == .w)
}

/// What the engine said of each move in your trees, by position and move.
public func lossesIn(_ reps: [Repertoire]) -> [String: Double] {
  var out: [String: Double] = [:]
  for rep in reps {
    for node in rep.nodes.values {
      if let lost = node.lost { out["\(positionKey(node.fenBefore)) \(node.san)"] = lost }
    }
  }
  return out
}

/// A played line by kind for the player of `color`, with your trees' stored losses.
public func playedKinds(_ index: ReferenceIndex, _ sans: [String], _ color: Color, _ losses: [String: Double]) -> [MoveKind] {
  let fens = walkSan(sans, START_FEN).fens
  let lost = sans.indices.map { i in i < fens.count ? losses["\(positionKey(fens[i])) \(sans[i])"] : nil }
  return lineKinds(index, sans, color, lost)
}
