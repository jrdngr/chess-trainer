/// The backup engine's own board: 0x88 squares, moves packed into numbers,
/// make and unmake in place. `src/engine/basic/board.ts`.

let PAWN = 1, KNIGHT = 2, BISHOP = 3, ROOK = 4, QUEEN = 5, KING = 6
/// Set on a piece code for Black.
let BLACK = 8
let WHITE_SIDE = 0, BLACK_SIDE = 1

/// Move flags.
let CAPTURE = 1, EN_PASSANT = 2, CASTLE = 4, DOUBLE_PUSH = 8

private let KNIGHT_STEPS = [33, 31, 18, 14, -33, -31, -18, -14]
private let KING_STEPS = [1, -1, 16, -16, 15, 17, -15, -17]
private let DIAGONALS = [15, 17, -15, -17]
private let LINES = [1, -1, 16, -16]
private let PIECE_CHARS = Array(" pnbrqk")

/// Castling rights kept after a move touches a square.
private let CASTLE_KEEP: [Int] = {
  var keep = [Int](repeating: 15, count: 128)
  keep[0x04] = 15 & ~3
  keep[0x00] = 15 & ~2
  keep[0x07] = 15 & ~1
  keep[0x74] = 15 & ~12
  keep[0x70] = 15 & ~8
  keep[0x77] = 15 & ~4
  return keep
}()

/// Zobrist keys from a fixed seed, so every run hashes alike.
private struct Zobrist {
  var pieces: [UInt64], castle: [UInt64], ep: [UInt64], side: UInt64
  init() {
    var seed: UInt32 = 0x9e37_79b9
    func next() -> UInt64 {
      seed ^= seed << 13
      seed ^= seed >> 17
      seed ^= seed << 5
      return UInt64(seed)
    }
    func key() -> UInt64 { next() | next() << 32 }
    pieces = (0..<(16 * 128)).map { _ in key() }
    castle = (0..<16).map { _ in key() }
    ep = (0..<8).map { _ in key() }
    side = key()
  }
}
private let Z = Zobrist()

@inline(__always) func fromOf(_ m: Int) -> Int { m & 127 }
@inline(__always) func toOf(_ m: Int) -> Int { (m >> 7) & 127 }
@inline(__always) func promoOf(_ m: Int) -> Int { (m >> 14) & 7 }
@inline(__always) func flagsOf(_ m: Int) -> Int { m >> 17 }
@inline(__always) private func pack(_ from: Int, _ to: Int, _ promo: Int, _ flags: Int) -> Int {
  from | (to << 7) | (promo << 14) | (flags << 17)
}
@inline(__always) func onBoard(_ sq: Int) -> Bool { sq & 0x88 == 0 }
@inline(__always) func fileOf(_ sq: Int) -> Int { sq & 7 }
@inline(__always) func rankOf(_ sq: Int) -> Int { sq >> 4 }

private func squareName(_ sq: Int) -> String {
  String(UnicodeScalar(UInt8(97 + fileOf(sq)))) + String(rankOf(sq) + 1)
}

private func parseSquare(_ name: String) -> Int {
  let u = Array(name.utf8)
  return (Int(u[1]) - 49) * 16 + (Int(u[0]) - 97)
}

func moveToUci(_ m: Int) -> String {
  let promo = promoOf(m)
  return squareName(fromOf(m)) + squareName(toOf(m)) + (promo != 0 ? String(PIECE_CHARS[promo]) : "")
}

final class Position {
  var sq = [Int](repeating: 0, count: 128)
  /// 0 White, 1 Black.
  var side = WHITE_SIDE
  /// 1 White short, 2 White long, 4 Black short, 8 Black long.
  var castling = 0
  var ep = -1
  var halfmove = 0
  var kings = [0, 0]
  var key: UInt64 = 0
  private var history: [Int] = []
  /// Keys before each move played, for repetitions and taking moves back.
  private(set) var past: [UInt64] = []

  init(_ fen: String) {
    let parts = fen.split(separator: " ").map(String.init)
    var rank = 7, file = 0
    for ch in parts[0] {
      if ch == "/" {
        rank -= 1
        file = 0
      } else if let n = ch.wholeNumberValue {
        file += n
      } else {
        let lower = Character(ch.lowercased())
        let type = PIECE_CHARS.firstIndex(of: lower)!
        let black = ch == lower
        let square = rank * 16 + file
        sq[square] = type | (black ? BLACK : 0)
        if type == KING { kings[black ? 1 : 0] = square }
        file += 1
      }
    }
    side = parts.count > 1 && parts[1] == "b" ? BLACK_SIDE : WHITE_SIDE
    let c = parts.count > 2 ? parts[2] : "-"
    castling = (c.contains("K") ? 1 : 0) | (c.contains("Q") ? 2 : 0) | (c.contains("k") ? 4 : 0) | (c.contains("q") ? 8 : 0)
    ep = parts.count > 3 && parts[3] != "-" ? parseSquare(parts[3]) : -1
    halfmove = parts.count > 4 ? Int(parts[4]) ?? 0 : 0
    rehash()
  }

  private func rehash() {
    var k: UInt64 = 0
    for s in 0..<128 where s & 0x88 == 0 && sq[s] != 0 { k ^= Z.pieces[sq[s] * 128 + s] }
    k ^= Z.castle[castling]
    if ep >= 0 { k ^= Z.ep[fileOf(ep)] }
    if side == BLACK_SIDE { k ^= Z.side }
    key = k
  }

  @inline(__always) private func toggle(_ piece: Int, _ s: Int) { key ^= Z.pieces[piece * 128 + s] }

  /// This position came up before, since the last capture or pawn move.
  func repeated() -> Bool {
    let n = past.count
    var i = n - 2
    while i >= 0 && i >= n - halfmove {
      if past[i] == key { return true }
      i -= 2
    }
    return false
  }

  /// Is this square attacked by the given side?
  func attacked(_ target: Int, by: Int) -> Bool {
    let colour = by == BLACK_SIDE ? BLACK : 0
    if by == WHITE_SIDE {
      if onBoard(target - 15) && sq[target - 15] == PAWN { return true }
      if onBoard(target - 17) && sq[target - 17] == PAWN { return true }
    } else {
      if onBoard(target + 15) && sq[target + 15] == (PAWN | BLACK) { return true }
      if onBoard(target + 17) && sq[target + 17] == (PAWN | BLACK) { return true }
    }
    for step in KNIGHT_STEPS {
      let s = target + step
      if onBoard(s) && sq[s] == (KNIGHT | colour) { return true }
    }
    for step in KING_STEPS {
      let s = target + step
      if onBoard(s) && sq[s] == (KING | colour) { return true }
    }
    for step in DIAGONALS {
      var s = target + step
      while onBoard(s) {
        let p = sq[s]
        if p != 0 {
          if p == (BISHOP | colour) || p == (QUEEN | colour) { return true }
          break
        }
        s += step
      }
    }
    for step in LINES {
      var s = target + step
      while onBoard(s) {
        let p = sq[s]
        if p != 0 {
          if p == (ROOK | colour) || p == (QUEEN | colour) { return true }
          break
        }
        s += step
      }
    }
    return false
  }

  func inCheck(_ who: Int? = nil) -> Bool {
    let s = who ?? side
    return attacked(kings[s], by: s ^ 1)
  }

  /// Every move the side to move can make, its own king left in check included.
  /// With `capturesOnly`, captures and queen promotions.
  func pseudoMoves(_ capturesOnly: Bool = false) -> [Int] {
    var out: [Int] = []
    out.reserveCapacity(48)
    let us = side == BLACK_SIDE ? BLACK : 0
    let forward = side == WHITE_SIDE ? 16 : -16
    let startRank = side == WHITE_SIDE ? 1 : 6
    let lastRank = side == WHITE_SIDE ? 7 : 0
    func enemy(_ p: Int) -> Bool { p != 0 && (p & BLACK) != us }
    func pawnTo(_ from: Int, _ to: Int, _ flags: Int) {
      if rankOf(to) == lastRank {
        out.append(pack(from, to, QUEEN, flags))
        if !capturesOnly {
          out.append(pack(from, to, KNIGHT, flags))
          out.append(pack(from, to, ROOK, flags))
          out.append(pack(from, to, BISHOP, flags))
        }
      } else {
        out.append(pack(from, to, 0, flags))
      }
    }
    var from = 0
    while from < 128 {
      if from & 0x88 != 0 { from += 8; continue }
      defer { from += 1 }
      let piece = sq[from]
      if piece == 0 || (piece & BLACK) != us { continue }
      let type = piece & 7
      if type == PAWN {
        let one = from + forward
        if onBoard(one) && sq[one] == 0 {
          if !capturesOnly || rankOf(one) == lastRank { pawnTo(from, one, 0) }
          let two = one + forward
          if !capturesOnly && rankOf(from) == startRank && sq[two] == 0 { out.append(pack(from, two, 0, DOUBLE_PUSH)) }
        }
        for d in [forward - 1, forward + 1] {
          let to = from + d
          if !onBoard(to) { continue }
          if enemy(sq[to]) { pawnTo(from, to, CAPTURE) } else if to == ep { out.append(pack(from, to, 0, CAPTURE | EN_PASSANT)) }
        }
        continue
      }
      if type == KNIGHT || type == KING {
        for step in type == KNIGHT ? KNIGHT_STEPS : KING_STEPS {
          let to = from + step
          if !onBoard(to) { continue }
          let target = sq[to]
          if target == 0 {
            if !capturesOnly { out.append(pack(from, to, 0, 0)) }
          } else if enemy(target) {
            out.append(pack(from, to, 0, CAPTURE))
          }
        }
        if type == KING && !capturesOnly { castleMoves(from, &out) }
        continue
      }
      let steps = type == BISHOP ? DIAGONALS : type == ROOK ? LINES : KING_STEPS
      for step in steps {
        var to = from + step
        while onBoard(to) {
          let target = sq[to]
          if target == 0 {
            if !capturesOnly { out.append(pack(from, to, 0, 0)) }
            to += step
            continue
          }
          if enemy(target) { out.append(pack(from, to, 0, CAPTURE)) }
          break
        }
      }
    }
    return out
  }

  private func castleMoves(_ from: Int, _ out: inout [Int]) {
    let them = side ^ 1
    if side == WHITE_SIDE && from == 0x04 {
      if castling & 1 != 0 && sq[0x05] == 0 && sq[0x06] == 0 && sq[0x07] == ROOK && !attacked(0x04, by: them) && !attacked(0x05, by: them) {
        out.append(pack(0x04, 0x06, 0, CASTLE))
      }
      if castling & 2 != 0 && sq[0x03] == 0 && sq[0x02] == 0 && sq[0x01] == 0 && sq[0x00] == ROOK && !attacked(0x04, by: them) && !attacked(0x03, by: them) {
        out.append(pack(0x04, 0x02, 0, CASTLE))
      }
    } else if side == BLACK_SIDE && from == 0x74 {
      if castling & 4 != 0 && sq[0x75] == 0 && sq[0x76] == 0 && sq[0x77] == (ROOK | BLACK) && !attacked(0x74, by: them) && !attacked(0x75, by: them) {
        out.append(pack(0x74, 0x76, 0, CASTLE))
      }
      if castling & 8 != 0 && sq[0x73] == 0 && sq[0x72] == 0 && sq[0x71] == 0 && sq[0x70] == (ROOK | BLACK) && !attacked(0x74, by: them) && !attacked(0x73, by: them) {
        out.append(pack(0x74, 0x72, 0, CASTLE))
      }
    }
  }

  /// Play a move. False, with the move already taken back, when it leaves the mover in check.
  func make(_ m: Int) -> Bool {
    let from = fromOf(m), to = toOf(m), flags = flagsOf(m)
    let piece = sq[from]
    let forward = side == WHITE_SIDE ? 16 : -16
    let capturedAt = flags & EN_PASSANT != 0 ? to - forward : to
    let captured = sq[capturedAt]
    history.append(captured | (castling << 4) | ((ep + 1) << 8) | (halfmove << 16))
    past.append(key)

    if captured != 0 { toggle(captured, capturedAt) }
    toggle(piece, from)
    sq[capturedAt] = 0
    sq[from] = 0
    let promo = promoOf(m)
    sq[to] = promo != 0 ? promo | (piece & BLACK) : piece
    toggle(sq[to], to)

    if piece & 7 == KING {
      kings[side] = to
      if flags & CASTLE != 0 {
        let (rookFrom, rookTo) = to > from ? (to + 1, to - 1) : (to - 2, to + 1)
        toggle(sq[rookFrom], rookFrom)
        toggle(sq[rookFrom], rookTo)
        sq[rookTo] = sq[rookFrom]
        sq[rookFrom] = 0
      }
    }
    key ^= Z.castle[castling]
    castling &= CASTLE_KEEP[from] & CASTLE_KEEP[to]
    key ^= Z.castle[castling] ^ Z.side
    if ep >= 0 { key ^= Z.ep[fileOf(ep)] }
    ep = flags & DOUBLE_PUSH != 0 ? from + forward : -1
    if ep >= 0 { key ^= Z.ep[fileOf(ep)] }
    halfmove = captured != 0 || piece & 7 == PAWN ? 0 : halfmove + 1
    side ^= 1
    if inCheck(side ^ 1) {
      unmake(m)
      return false
    }
    return true
  }

  func unmake(_ m: Int) {
    let state = history.removeLast()
    side ^= 1
    let from = fromOf(m), to = toOf(m), flags = flagsOf(m)
    let moved = sq[to]
    let piece = promoOf(m) != 0 ? PAWN | (moved & BLACK) : moved
    let forward = side == WHITE_SIDE ? 16 : -16
    sq[from] = piece
    sq[to] = 0
    sq[flags & EN_PASSANT != 0 ? to - forward : to] = state & 15
    if piece & 7 == KING {
      kings[side] = from
      if flags & CASTLE != 0 {
        let (rookFrom, rookTo) = to > from ? (to + 1, to - 1) : (to - 2, to + 1)
        sq[rookFrom] = sq[rookTo]
        sq[rookTo] = 0
      }
    }
    castling = (state >> 4) & 15
    ep = ((state >> 8) & 255) - 1
    halfmove = state >> 16
    key = past.removeLast()
  }

  /// Pass, for null-move pruning.
  func makeNull() {
    history.append((castling << 4) | ((ep + 1) << 8) | (halfmove << 16))
    past.append(key)
    if ep >= 0 { key ^= Z.ep[fileOf(ep)] }
    key ^= Z.side
    ep = -1
    side ^= 1
  }

  func unmakeNull() {
    let state = history.removeLast()
    side ^= 1
    ep = ((state >> 8) & 255) - 1
    key = past.removeLast()
  }

  /// The legal moves, for the root.
  func legalMoves() -> [Int] {
    pseudoMoves().filter { m in
      guard make(m) else { return false }
      unmake(m)
      return true
    }
  }

  /// Any knight, bishop, rook or queen left for this side.
  func hasPieces(_ who: Int) -> Bool {
    let colour = who == BLACK_SIDE ? BLACK : 0
    for s in 0..<128 where s & 0x88 == 0 {
      let p = sq[s]
      if p != 0 && (p & BLACK) == colour && p & 7 != PAWN && p & 7 != KING { return true }
    }
    return false
  }
}
