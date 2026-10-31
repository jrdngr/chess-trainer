/// A chess position, laid out the way chess.js lays it out (0x88, a8 first),
/// so move order, SAN and FEN come out exactly as the prototype's.

public enum Color: String, Sendable, Codable {
  case w, b
  public var other: Color { self == .w ? .b : .w }
}

public enum PieceType: String, Sendable, Codable, CaseIterable {
  case p, n, b, r, q, k
}

struct Piece: Equatable {
  var type: PieceType
  var color: Color
}

enum Flag {
  static let normal = 1
  static let capture = 2
  static let bigPawn = 4
  static let epCapture = 8
  static let promotion = 16
  static let kside = 32
  static let qside = 64
}

struct RawMove {
  var color: Color
  var from: Int
  var to: Int
  var piece: PieceType
  var captured: PieceType?
  var promotion: PieceType?
  var flags: Int
}

func rank(_ sq: Int) -> Int { sq >> 4 }
func file(_ sq: Int) -> Int { sq & 15 }

func algebraic(_ sq: Int) -> String {
  let f = file(sq), r = rank(sq)
  return String(UnicodeScalar(UInt8(97 + f))) + String(8 - r)
}

func ox88(_ square: String) -> Int? {
  let chars = Array(square.utf8)
  guard chars.count == 2, (97...104).contains(chars[0]), (49...56).contains(chars[1]) else { return nil }
  let f = Int(chars[0]) - 97
  let r = 8 - (Int(chars[1]) - 48)
  return r * 16 + f
}

struct Board {
  var squares = [Piece?](repeating: nil, count: 128)
  var turn: Color = .w
  var castling: [Color: Int] = [.w: 0, .b: 0]
  var ep: Int? = nil
  var halfMoves = 0
  var moveNumber = 1
  var kings: [Color: Int] = [:]

  static let rooks: [Color: [(square: Int, flag: Int)]] = [
    .w: [(112, Flag.qside), (119, Flag.kside)],
    .b: [(0, Flag.qside), (7, Flag.kside)],
  ]

  init?(fen: String) {
    let tokens = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    guard tokens.count == 6,
      let half = Int(tokens[4]), half >= 0,
      let number = Int(tokens[5]), number > 0,
      tokens[1] == "w" || tokens[1] == "b"
    else { return nil }
    let rows = tokens[0].split(separator: "/", omittingEmptySubsequences: false)
    guard rows.count == 8 else { return nil }
    for (r, row) in rows.enumerated() {
      var f = 0
      var lastDigit = false
      for ch in row {
        if let n = ch.wholeNumberValue {
          guard !lastDigit, (1...8).contains(n) else { return nil }
          f += n
          lastDigit = true
        } else {
          guard let type = PieceType(rawValue: ch.lowercased()), f < 8 else { return nil }
          let color: Color = ch.isUppercase ? .w : .b
          let sq = r * 16 + f
          if type == .k {
            guard kings[color] == nil else { return nil }
            kings[color] = sq
          }
          squares[sq] = Piece(type: type, color: color)
          f += 1
          lastDigit = false
        }
      }
      guard f == 8 else { return nil }
    }
    guard kings[.w] != nil, kings[.b] != nil else { return nil }
    turn = tokens[1] == "b" ? .b : .w
    let rights = tokens[2]
    guard rights == "-" || rights.allSatisfy({ "KQkq".contains($0) }) else { return nil }
    if rights.contains("K") { castling[.w]! |= Flag.kside }
    if rights.contains("Q") { castling[.w]! |= Flag.qside }
    if rights.contains("k") { castling[.b]! |= Flag.kside }
    if rights.contains("q") { castling[.b]! |= Flag.qside }
    if tokens[3] != "-" {
      guard let sq = ox88(tokens[3]), rank(sq) == (turn == .w ? 2 : 5) else { return nil }
      ep = sq
    }
    halfMoves = half
    moveNumber = number
  }

  /// The FEN, with the en passant square only when a legal capture uses it.
  var fen: String {
    var out = ""
    var empty = 0
    var i = 0
    while i <= 119 {
      if let piece = squares[i] {
        if empty > 0 { out += String(empty); empty = 0 }
        out += piece.color == .w ? piece.type.rawValue.uppercased() : piece.type.rawValue
      } else {
        empty += 1
      }
      if (i + 1) & 0x88 != 0 {
        if empty > 0 { out += String(empty) }
        if i != 119 { out += "/" }
        empty = 0
        i += 8
      }
      i += 1
    }
    var rights = ""
    if castling[.w]! & Flag.kside != 0 { rights += "K" }
    if castling[.w]! & Flag.qside != 0 { rights += "Q" }
    if castling[.b]! & Flag.kside != 0 { rights += "k" }
    if castling[.b]! & Flag.qside != 0 { rights += "q" }
    if rights.isEmpty { rights = "-" }
    return [out, turn.rawValue, rights, epText, String(halfMoves), String(moveNumber)].joined(separator: " ")
  }

  private var epText: String {
    guard let ep else { return "-" }
    let bigPawn = ep + (turn == .w ? 16 : -16)
    for sq in [bigPawn + 1, bigPawn - 1] where sq & 0x88 == 0 {
      guard let piece = squares[sq], piece.color == turn, piece.type == .p else { continue }
      let after = made(RawMove(color: turn, from: sq, to: ep, piece: .p, captured: .p, flags: Flag.epCapture))
      if !after.kingAttacked(turn) { return algebraic(ep) }
    }
    return "-"
  }

  func attacked(by color: Color, _ square: Int) -> Bool {
    // Pawns, knights and kings by their offsets; sliders by rays.
    let pawnFrom = color == .w ? [square + 15, square + 17] : [square - 15, square - 17]
    for sq in pawnFrom where sq & 0x88 == 0 {
      if squares[sq] == Piece(type: .p, color: color) { return true }
    }
    for offset in pieceOffsets[.n]! {
      let sq = square + offset
      if sq & 0x88 == 0, squares[sq] == Piece(type: .n, color: color) { return true }
    }
    for offset in pieceOffsets[.k]! {
      let sq = square + offset
      if sq & 0x88 == 0, squares[sq] == Piece(type: .k, color: color) { return true }
    }
    for offset in pieceOffsets[.q]! {
      let diagonal = abs(offset) == 15 || abs(offset) == 17
      var sq = square + offset
      while sq & 0x88 == 0 {
        if let piece = squares[sq] {
          if piece.color == color, piece.type == .q || piece.type == (diagonal ? .b : .r) { return true }
          break
        }
        sq += offset
      }
    }
    return false
  }

  func kingAttacked(_ color: Color) -> Bool {
    guard let king = kings[color] else { return false }
    return attacked(by: color.other, king)
  }

  /// The position after a move, as chess.js `_makeMove` leaves it.
  func made(_ move: RawMove) -> Board {
    var next = self
    let us = turn, them = us.other
    next.squares[move.to] = next.squares[move.from]
    next.squares[move.from] = nil
    if move.flags & Flag.epCapture != 0 {
      next.squares[us == .b ? move.to - 16 : move.to + 16] = nil
    }
    if let promotion = move.promotion {
      next.squares[move.to] = Piece(type: promotion, color: us)
    }
    if next.squares[move.to]?.type == .k {
      next.kings[us] = move.to
      if move.flags & Flag.kside != 0 {
        next.squares[move.to - 1] = next.squares[move.to + 1]
        next.squares[move.to + 1] = nil
      } else if move.flags & Flag.qside != 0 {
        next.squares[move.to + 1] = next.squares[move.to - 2]
        next.squares[move.to - 2] = nil
      }
      next.castling[us] = 0
    }
    if next.castling[us]! != 0 {
      for rook in Board.rooks[us]! where move.from == rook.square && next.castling[us]! & rook.flag != 0 {
        next.castling[us]! ^= rook.flag
        break
      }
    }
    if next.castling[them]! != 0 {
      for rook in Board.rooks[them]! where move.to == rook.square && next.castling[them]! & rook.flag != 0 {
        next.castling[them]! ^= rook.flag
        break
      }
    }
    next.ep = nil
    if move.flags & Flag.bigPawn != 0 {
      let left = move.to - 1, right = move.to + 1
      let enemyPawn = Piece(type: .p, color: them)
      if (left & 0x88 == 0 && next.squares[left] == enemyPawn) || (right & 0x88 == 0 && next.squares[right] == enemyPawn) {
        next.ep = us == .b ? move.to - 16 : move.to + 16
      }
    }
    if move.piece == .p || move.flags & (Flag.capture | Flag.epCapture) != 0 {
      next.halfMoves = 0
    } else {
      next.halfMoves += 1
    }
    if us == .b { next.moveNumber += 1 }
    next.turn = them
    return next
  }
}

let pieceOffsets: [PieceType: [Int]] = [
  .n: [-18, -33, -31, -14, 18, 33, 31, 14],
  .b: [-17, -15, 17, 15],
  .r: [-16, 1, 16, -1],
  .q: [-17, -16, -15, 1, 17, 16, 15, -1],
  .k: [-17, -16, -15, 1, 17, 16, 15, -1],
]
