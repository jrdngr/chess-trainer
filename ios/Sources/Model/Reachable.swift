import ChessCore

/// Reachability, for the nudges: could one position still become another?

struct PlacedPiece {
  var square: String
  var type: Character
  var color: Color
}

/// The pieces on a FEN's board, read straight from the text: this runs thousands of times.
func placed(_ fen: String) -> [PlacedPiece] {
  let board = fen.split(separator: " ", omittingEmptySubsequences: false)[0]
  var out: [PlacedPiece] = []
  for (i, row) in board.split(separator: "/", omittingEmptySubsequences: false).enumerated() {
    var file = 0
    for ch in row {
      if let n = ch.wholeNumberValue, ch >= "1", ch <= "8" {
        file += n
        continue
      }
      let lower = Character(ch.lowercased())
      let letter = Character(UnicodeScalar(97 + file)!)
      out.append(PlacedPiece(square: "\(letter)\(8 - i)", type: lower, color: ch == lower ? .b : .w))
      file += 1
    }
  }
  return out
}

/// One side's pawns as a stable string, for comparing structures.
func pawnsOf(_ fen: String, _ color: Color) -> String {
  placed(fen)
    .filter { $0.type == "p" && $0.color == color }
    .map(\.square)
    .sorted()
    .joined(separator: ",")
}

/// Could a game standing at `from` still arrive at `to`?
///
/// Only what cannot be undone is checked: pawns go forward and sideways only by
/// capturing, pieces once taken stay taken, castling once lost is lost. It errs
/// toward "still reachable", so a move is never marked red for closing a line
/// it has not actually closed.
public func reachable(_ from: String, _ to: String) -> Bool {
  let a = placed(from)
  let b = placed(to)
  func rights(_ fen: String) -> String {
    let parts = fen.split(separator: " ", omittingEmptySubsequences: false)
    return parts.count > 2 ? String(parts[2]) : "-"
  }
  let had = rights(from)
  for right in rights(to) where right != "-" && !had.contains(right) { return false }
  for color in [Color.w, .b] {
    for type: Character in ["n", "b", "r", "q"] {
      func count(_ pieces: [PlacedPiece]) -> Int { pieces.filter { $0.color == color && $0.type == type }.count }
      if count(b) > count(a) { return false }
    }
    let pawnsA = a.filter { $0.color == color && $0.type == "p" }.map(coords)
    let pawnsB = b.filter { $0.color == color && $0.type == "p" }.map(coords)
    if !pawnsCanBecome(pawnsA, pawnsB, color) { return false }
  }
  return true
}

private func coords(_ piece: PlacedPiece) -> (Int, Int) {
  let chars = Array(piece.square.unicodeScalars)
  return (Int(chars[0].value) - 97, Int(chars[1].value) - 48)
}

/// Can every pawn in the target come from its own pawn in the source? A pawn
/// moves up its file, or across one file per rank it gains by capturing.
private func pawnsCanBecome(_ from: [(Int, Int)], _ to: [(Int, Int)], _ color: Color) -> Bool {
  if to.count > from.count { return false }
  func can(_ src: (Int, Int), _ dst: (Int, Int)) -> Bool {
    let gain = color == .w ? dst.1 - src.1 : src.1 - dst.1
    return gain >= 0 && abs(dst.0 - src.0) <= gain
  }
  var owner = [Int](repeating: -1, count: from.count)
  func assign(_ t: Int, _ seen: inout [Bool]) -> Bool {
    for s in 0..<from.count {
      if seen[s] || !can(from[s], to[t]) { continue }
      seen[s] = true
      if owner[s] < 0 || assign(owner[s], &seen) {
        owner[s] = t
        return true
      }
    }
    return false
  }
  return to.indices.allSatisfy { t in
    var seen = [Bool](repeating: false, count: from.count)
    return assign(t, &seen)
  }
}
