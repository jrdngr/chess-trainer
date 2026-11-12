import Book
import ChessCore
import Shared

/// Play on the board: building a Playbook by playing the moves in.
///
/// The board offers the book's most played moves as arrows, one of them
/// highlighted, and the style you pick decides which. Only book moves are
/// offered, so following the arrows never leaves the book.

public struct BookChoice: Equatable, Sendable {
  public var san: String
  /// Share of the book's games at the position, 0 to 1.
  public var share: Double
}

/// The book moves here, most played first: those at least `BOOK_SHARE` of games choose.
public func bookChoices(_ index: ReferenceIndex, _ fen: String) -> [BookChoice] {
  let entry = lookup(index, fen)
  let total = totalGamesAt(entry)
  guard let entry, total > 0 else { return [] }
  return entry.moves
    .map { BookChoice(san: $0.san, share: $0.games / total) }
    .filter { $0.share >= BOOK_SHARE }
    .jsSorted { $1.share - $0.share }
}

public enum Style: String, Sendable, CaseIterable {
  case popular, solid, attack, gambit, fianchetto
}

public let STYLES: [(id: Style, label: String)] = [
  (.popular, "Popular"), (.solid, "Solid"), (.attack, "Attack"), (.gambit, "Gambit"), (.fianchetto, "Fianchetto"),
]

/// How far past a move the book is followed to see where it leads: the reply
/// and your next move.
private let LOOKAHEAD = 2

private let FIANCHETTO: Set<String> = ["g3", "b3", "g6", "b6", "Bg2", "Bb2", "Bg7", "Bb7"]

/// Where a move leads if both sides keep to the book's most played moves.
private func leadsTo(_ index: ReferenceIndex, _ path: [String], _ san: String) -> [String] {
  var line = path + [san]
  var fen = walkSan(line).fens.last!
  for _ in 0..<LOOKAHEAD {
    guard let next = bookChoices(index, fen).first, let move = applySan(fen, next.san) else { break }
    line.append(move.san)
    fen = move.after
  }
  return line
}

/// The names a line reaches past `from` plies, in order.
private func namesPast(_ index: ReferenceIndex, _ line: [String], _ from: Int) -> [String] {
  walkSan(line).fens.dropFirst(from + 1).compactMap { nameAt(index, $0)?.name }.filter { !$0.isEmpty }
}

private func isGambit(_ name: String) -> Bool {
  name.contains("Gambit") && !name.hasPrefix("Queen's Gambit") && !name.contains("Declined")
}

/// The move a style highlights among the book moves here, or nil when the
/// style finds nothing that fits. Most played breaks every tie.
public func stylePick(_ index: ReferenceIndex, _ tree: OpeningTree, _ path: [String], _ choices: [BookChoice], _ style: Style) -> String? {
  guard let first = choices.first else { return nil }
  if style == .popular { return first.san }
  let ply = path.count
  let scored = choices.map { choice -> (san: String, share: Double, score: Double?) in
    let line = leadsTo(index, path, choice.san)
    let names = namesPast(index, line, ply)
    var score: Double?
    switch style {
    case .solid, .attack:
      let node = deepestNodeAlong(tree, line)
      if let sharpness = node.flatMap({ entryForNode(pickerCatalog(tree), $0) })?.sharpness {
        score = Double(style == .solid ? -sharpness : sharpness)
      }
    case .gambit:
      score = names.contains(where: isGambit) ? 1 : nil
    default:
      score = FIANCHETTO.contains(choice.san) || names.contains { $0.contains("Fianchetto") } ? 1 : nil
    }
    return (choice.san, choice.share, score)
  }
  let fitting = scored.filter { $0.score != nil }.jsSorted { a, b in
    let s = b.score! - a.score!
    return s != 0 ? s : b.share - a.share
  }
  return fitting.first?.san
}

/// The styles worth showing here: Popular always, and every other one that
/// would highlight a different move, or is the one picked.
public func shownStyles(_ picks: [Style: String], _ picked: Style) -> [Style] {
  STYLES.map(\.id).filter { id in
    id == .popular || id == picked || (picks[id] != nil && picks[id] != picks[.popular])
  }
}

/// The arrows to draw: the three most played, with the highlighted move always among them.
public func arrowChoices(_ choices: [BookChoice], _ highlight: String?) -> [BookChoice] {
  let top = Array(choices.prefix(3))
  guard let highlight, !highlight.isEmpty, !top.contains(where: { $0.san == highlight }) else { return top }
  guard let picked = choices.first(where: { $0.san == highlight }) else { return top }
  return Array(top.prefix(2)) + [picked]
}

/* ── goals ── */

/// One of the opening's three jobs for a side.
public struct BoardGoal: Equatable, Sendable {
  public var label: String
  public var value: String
  /// The value names pieces or squares, rather than saying something in words.
  public var moves: Bool
}

private let HOME: [Color: [(square: String, piece: PieceType)]] = [
  .w: [("b1", .n), ("c1", .b), ("f1", .b), ("g1", .n)],
  .b: [("b8", .n), ("c8", .b), ("f8", .b), ("g8", .n)],
]

/// Where one side stands on the opening's three jobs: the minor pieces still
/// at home, whether it has castled, and the center pawns against the other
/// side's. Read off the position alone.
public func goals(_ fen: String, _ color: Color) -> [BoardGoal] {
  let pieces = piecesFromFen(fen)
  func at(_ square: String) -> BoardPiece? { pieces.first { $0.square == square } }

  let home = HOME[color]!.filter { home in
    guard let p = at(home.square) else { return false }
    return p.color == color && p.type == home.piece
  }
  let develop = home.isEmpty ? "done" : home.map { $0.piece.rawValue.uppercased() + $0.square }.joined(separator: " ")

  let rank: Character = color == .w ? "1" : "8"
  let king = pieces.first { $0.type == .k && $0.color == color }
  let parts = fen.split(separator: " ", omittingEmptySubsequences: false)
  let rights = parts.count > 2 ? String(parts[2]) : "-"
  let canCastle = rights.contains { color == .w ? "KQ".contains($0) : "kq".contains($0) }
  let castled = king.map { k in
    Array(k.square)[1] == rank && ["g", "h", "b", "c"].contains(Array(k.square)[0]) && !canCastle
  } ?? false
  let castle = castled ? "done" : canCastle ? "not yet" : "no"

  func center(_ side: Color) -> String {
    pieces
      .filter { p in
        let sq = Array(p.square)
        return p.type == .p && p.color == side && "de".contains(sq[0]) && "3456".contains(sq[1])
      }
      .map(\.square)
      .sorted()
      .joined(separator: " ")
  }
  let mine = center(color)
  let theirs = center(color.other)
  let centerText = mine.isEmpty && theirs.isEmpty ? "—" : "\(mine.isEmpty ? "—" : mine) vs \(theirs.isEmpty ? "—" : theirs)"

  return [
    BoardGoal(label: "Develop", value: develop, moves: !home.isEmpty),
    BoardGoal(label: "Castle", value: castle, moves: false),
    BoardGoal(label: "Center", value: centerText, moves: true),
  ]
}

/// Whose move it is after a line.
public func turnAfter(_ sans: [String]) -> Color {
  fenTurn(walkSan(sans).fens.last!)
}

/// How a judged move reads on the board editor: past `SCORE_SLIGHT` given away it is dubious,
/// past `BLUNDER_LIMIT` a blunder.
public enum MoveQuality: Sendable { case dubious, blunder }

public func moveQuality(_ lost: Double) -> MoveQuality? {
  lost > BLUNDER_LIMIT ? .blunder : lost > SCORE_SLIGHT ? .dubious : nil
}

/// How many moves at the start of a line a tree already holds.
public func savedPlies(_ rep: Playbook?, _ sans: [String]) -> Int {
  guard let rep else { return 0 }
  var parent: String?
  for (i, san) in sans.enumerated() {
    guard let node = findChildBySan(rep, parent, san) else { return i }
    parent = node.id
  }
  return sans.count
}
