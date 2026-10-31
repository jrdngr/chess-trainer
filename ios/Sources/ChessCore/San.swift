import Foundation

extension Board {
  /// chess.js `_moveToSan`: `moves` is the legal list the move was drawn from.
  func san(_ move: RawMove, among moves: [RawMove]) -> String {
    var out = sanCore(move, among: moves)
    let after = made(move)
    if after.inCheck { out += after.moves().isEmpty ? "#" : "+" }
    return out
  }

  /// The SAN without its check or mate mark: what `strippedSan` compares against.
  func sanCore(_ move: RawMove, among moves: [RawMove]) -> String {
    var out: String
    if move.flags & Flag.kside != 0 {
      out = "O-O"
    } else if move.flags & Flag.qside != 0 {
      out = "O-O-O"
    } else {
      out = ""
      if move.piece != .p { out += move.piece.rawValue.uppercased() + disambiguator(move, moves) }
      if move.flags & (Flag.capture | Flag.epCapture) != 0 {
        if move.piece == .p { out += String(algebraic(move.from).first!) }
        out += "x"
      }
      out += algebraic(move.to)
      if let promotion = move.promotion { out += "=" + promotion.rawValue.uppercased() }
    }
    return out
  }

  private func disambiguator(_ move: RawMove, _ moves: [RawMove]) -> String {
    var ambiguities = 0, sameRank = 0, sameFile = 0
    for other in moves where other.piece == move.piece && other.from != move.from && other.to == move.to {
      ambiguities += 1
      if rank(move.from) == rank(other.from) { sameRank += 1 }
      if file(move.from) == file(other.from) { sameFile += 1 }
    }
    guard ambiguities > 0 else { return "" }
    let square = algebraic(move.from)
    if sameRank > 0 && sameFile > 0 { return square }
    if sameFile > 0 { return String(square.last!) }
    return String(square.first!)
  }

  /// chess.js `_moveFromSan`, permissive: exact SAN first, then the loose forms.
  func move(fromSan text: String) -> RawMove? {
    var clean = strippedSan(text)
    if clean == "0-0" { clean = "O-O" } else if clean == "0-0-0" { clean = "O-O-O" }
    var candidates = legal(for: inferPieceType(clean))
    for move in candidates where clean == strippedSan(sanCore(move, among: candidates)) { return move }

    let strictSquares = #/([pnbrqkPNBRQK])?([a-h][1-8])x?-?([a-h][1-8])([qrbnQRBN])?/#
    let loose = #/([pnbrqkPNBRQK])?([a-h]?[1-8]?)x?-?([a-h][1-8])([qrbnQRBN])?/#
    var piece: String?, from: String?, to: String?, promotion: String?
    if let m = clean.firstMatch(of: strictSquares) {
      piece = m.1.map(String.init); from = String(m.2); to = String(m.3); promotion = m.4.map(String.init)
    } else if let m = clean.firstMatch(of: loose) {
      piece = m.1.map(String.init); from = String(m.2); to = String(m.3); promotion = m.4.map(String.init)
    }
    if from == "" { from = nil }
    let overly = from?.count == 1
    guard let to else { return nil }
    candidates = legal(for: piece?.lowercased() ?? inferPieceType(clean))
    let pieceOK = { (m: RawMove) in piece == nil || piece!.lowercased() == m.piece.rawValue }
    let promoOK = { (m: RawMove) in promotion == nil || promotion!.lowercased() == m.promotion?.rawValue }
    for m in candidates {
      if from == nil {
        if clean == replacingFirstX(strippedSan(sanCore(m, among: candidates))) { return m }
      } else if pieceOK(m), ox88(from!) == m.from, ox88(to) == m.to, promoOK(m) {
        return m
      } else if overly {
        let square = algebraic(m.from)
        if pieceOK(m), ox88(to) == m.to, from == String(square.first!) || from == String(square.last!), promoOK(m) {
          return m
        }
      }
    }
    return nil
  }
}

extension Board {
  /// chess.js filters by a piece letter; one that names no piece matches nothing.
  fileprivate func legal(for piece: String?) -> [RawMove] {
    guard let piece, !piece.isEmpty else { return moves() }
    guard let type = PieceType(rawValue: piece) else { return [] }
    return moves(piece: type)
  }
}

/// `String.replace('x', '')` touches the first match only.
private func replacingFirstX(_ text: String) -> String {
  guard let at = text.range(of: "x") else { return text }
  return text.replacingCharacters(in: at, with: "")
}

/// chess.js `strippedSan`: the first "=" out, and a check mark with any "?!" after it off the end.
/// Written out by hand: a Swift Regex here made reading a move a hundred times slower.
func strippedSan(_ move: String) -> String {
  var chars = Array(move.unicodeScalars)
  if let eq = chars.firstIndex(of: "=") { chars.remove(at: eq) }
  while let last = chars.last, last == "?" || last == "!" { chars.removeLast() }
  if let last = chars.last, last == "+" || last == "#" { chars.removeLast() }
  var out = String.UnicodeScalarView()
  out.append(contentsOf: chars)
  return String(out)
}

/// Whether two squares appear in order: chess.js's `/[a-h]\d.*[a-h]\d/`.
private func twoSquares(_ san: String) -> Bool {
  let u = Array(san.utf8)
  var found = 0
  var i = 0
  while i + 1 < u.count {
    if (97...104).contains(u[i]) && (48...57).contains(u[i + 1]) {
      found += 1
      if found == 2 { return true }
      i += 2
    } else {
      i += 1
    }
  }
  return false
}

/// chess.js `inferPieceType`.
func inferPieceType(_ san: String) -> String? {
  guard let first = san.first else { return "" }
  if ("a"..."h").contains(first) {
    if twoSquares(san) { return nil }
    return "p"
  }
  let lower = first.lowercased()
  return lower == "o" ? "k" : lower
}
