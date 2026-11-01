/// The engine's own board: bitboards (one 64-bit set per piece, square 0 is
/// a1, 63 is h8) beside a square-by-square array for "what stands here",
/// moves packed into numbers, make and unmake in place.

let PAWN = 1, KNIGHT = 2, BISHOP = 3, ROOK = 4, QUEEN = 5, KING = 6
/// Set on a piece code for Black.
let BLACK = 8
let WHITE_SIDE = 0, BLACK_SIDE = 1

/// Move flags.
let CAPTURE = 1, EN_PASSANT = 2, CASTLE = 4, DOUBLE_PUSH = 8

private let PIECE_CHARS = Array(" pnbrqk")

typealias Bitboard = UInt64

@inline(__always) func bit(_ sq: Int) -> Bitboard { 1 << UInt64(sq) }
@inline(__always) func fileOf(_ sq: Int) -> Int { sq & 7 }
@inline(__always) func rankOf(_ sq: Int) -> Int { sq >> 3 }

/// Takes the lowest square off a set and returns it.
@inline(__always) func popLowest(_ b: inout Bitboard) -> Int {
  let sq = b.trailingZeroBitCount
  b &= b &- 1
  return sq
}

/* ── attack tables ── */

private func stepTable(_ steps: [(Int, Int)]) -> [Bitboard] {
  (0..<64).map { sq -> Bitboard in
    var b: Bitboard = 0
    for (df, dr) in steps {
      let f = fileOf(sq) + df, r = rankOf(sq) + dr
      if f >= 0 && f < 8 && r >= 0 && r < 8 { b |= bit(r * 8 + f) }
    }
    return b
  }
}

let KNIGHT_ATTACKS = stepTable([(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)])
let KING_ATTACKS = stepTable([(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)])
/// The squares a pawn of each side attacks from a square.
let PAWN_ATTACKS = [stepTable([(-1, 1), (1, 1)]), stepTable([(-1, -1), (1, -1)])]

/// Rays out from each square, one per direction. The first four run toward
/// higher squares (N, E, NE, NW), the last four toward lower (S, W, SW, SE).
private let DIRECTIONS = [(0, 1), (1, 0), (1, 1), (-1, 1), (0, -1), (-1, 0), (-1, -1), (1, -1)]
private let RAYS: [[Bitboard]] = DIRECTIONS.map { (d: (Int, Int)) -> [Bitboard] in
  let (df, dr) = d
  return (0..<64).map { sq -> Bitboard in
    var b: Bitboard = 0
    var f = fileOf(sq) + df, r = rankOf(sq) + dr
    while f >= 0 && f < 8 && r >= 0 && r < 8 {
      b |= bit(r * 8 + f)
      f += df
      r += dr
    }
    return b
  }
}

@inline(__always) private func ray(_ dir: Int, _ sq: Int, _ occupied: Bitboard) -> Bitboard {
  let r = RAYS[dir][sq]
  let blockers = r & occupied
  if blockers == 0 { return r }
  let first = dir < 4 ? blockers.trailingZeroBitCount : 63 - blockers.leadingZeroBitCount
  return r ^ RAYS[dir][first]
}

@inline(__always) func rookAttacks(_ sq: Int, _ occupied: Bitboard) -> Bitboard {
  ray(0, sq, occupied) | ray(1, sq, occupied) | ray(4, sq, occupied) | ray(5, sq, occupied)
}

@inline(__always) func bishopAttacks(_ sq: Int, _ occupied: Bitboard) -> Bitboard {
  ray(2, sq, occupied) | ray(3, sq, occupied) | ray(6, sq, occupied) | ray(7, sq, occupied)
}

/// Castling rights kept after a move touches a square.
private let CASTLE_KEEP: [Int] = {
  var keep = [Int](repeating: 15, count: 64)
  keep[4] = 15 & ~3
  keep[0] = 15 & ~2
  keep[7] = 15 & ~1
  keep[60] = 15 & ~12
  keep[56] = 15 & ~8
  keep[63] = 15 & ~4
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
    pieces = (0..<(16 * 64)).map { _ in key() }
    castle = (0..<16).map { _ in key() }
    ep = (0..<8).map { _ in key() }
    side = key()
  }
}
private let Z = Zobrist()

/* ── moves ── */

@inline(__always) func fromOf(_ m: Int) -> Int { m & 63 }
@inline(__always) func toOf(_ m: Int) -> Int { (m >> 6) & 63 }
@inline(__always) func promoOf(_ m: Int) -> Int { (m >> 12) & 7 }
@inline(__always) func flagsOf(_ m: Int) -> Int { m >> 15 }
@inline(__always) private func pack(_ from: Int, _ to: Int, _ promo: Int, _ flags: Int) -> Int {
  from | (to << 6) | (promo << 12) | (flags << 15)
}

private func squareName(_ sq: Int) -> String {
  String(UnicodeScalar(UInt8(97 + fileOf(sq)))) + String(rankOf(sq) + 1)
}

private func parseSquare(_ name: String) -> Int {
  let u = Array(name.utf8)
  return (Int(u[1]) - 49) * 8 + (Int(u[0]) - 97)
}

func moveToUci(_ m: Int) -> String {
  let promo = promoOf(m)
  return squareName(fromOf(m)) + squareName(toOf(m)) + (promo != 0 ? String(PIECE_CHARS[promo]) : "")
}

/* ── the position ── */

final class Position {
  /// The piece code on each square, 0 when empty.
  var board = [Int](repeating: 0, count: 64)
  /// One set per piece code.
  var pieces = [Bitboard](repeating: 0, count: 16)
  /// Every piece of each side.
  var bySide: [Bitboard] = [0, 0]
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

  var occupied: Bitboard { bySide[0] | bySide[1] }

  @inline(__always) func set(_ side: Int, _ type: Int) -> Bitboard {
    pieces[type | (side == BLACK_SIDE ? BLACK : 0)]
  }

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
        put(type | (black ? BLACK : 0), rank * 8 + file)
        if type == KING { kings[black ? 1 : 0] = rank * 8 + file }
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

  @inline(__always) private func put(_ piece: Int, _ s: Int) {
    board[s] = piece
    pieces[piece] |= bit(s)
    bySide[piece >> 3] |= bit(s)
  }

  @inline(__always) private func remove(_ piece: Int, _ s: Int) {
    board[s] = 0
    pieces[piece] &= ~bit(s)
    bySide[piece >> 3] &= ~bit(s)
  }

  private func rehash() {
    var k: UInt64 = 0
    for s in 0..<64 where board[s] != 0 { k ^= Z.pieces[board[s] * 64 + s] }
    k ^= Z.castle[castling]
    if ep >= 0 { k ^= Z.ep[fileOf(ep)] }
    if side == BLACK_SIDE { k ^= Z.side }
    key = k
  }

  @inline(__always) private func toggle(_ piece: Int, _ s: Int) { key ^= Z.pieces[piece * 64 + s] }

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

  /// Every piece of the given side that attacks this square.
  func attackers(_ target: Int, by: Int, _ occupied: Bitboard) -> Bitboard {
    let queens = set(by, QUEEN)
    return (PAWN_ATTACKS[by ^ 1][target] & set(by, PAWN))
      | (KNIGHT_ATTACKS[target] & set(by, KNIGHT))
      | (KING_ATTACKS[target] & set(by, KING))
      | (bishopAttacks(target, occupied) & (set(by, BISHOP) | queens))
      | (rookAttacks(target, occupied) & (set(by, ROOK) | queens))
  }

  /// Is this square attacked by the given side?
  func attacked(_ target: Int, by: Int) -> Bool {
    attackers(target, by: by, occupied) != 0
  }

  func inCheck(_ who: Int? = nil) -> Bool {
    let s = who ?? side
    return attacked(kings[s], by: s ^ 1)
  }

  /// Every move the side to move can make, its own king left in check included.
  /// With `capturesOnly`, captures and queen promotions.
  func pseudoMoves(_ capturesOnly: Bool = false) -> [Int] {
    var out: [Int] = []
    out.reserveCapacity(capturesOnly ? 16 : 48)
    let us = side, them = side ^ 1
    let own = bySide[us], enemy = bySide[them], occ = own | enemy
    let targets = capturesOnly ? enemy : ~own

    // Pawns.
    let forward = us == WHITE_SIDE ? 8 : -8
    let startRank = us == WHITE_SIDE ? 1 : 6
    let lastRank = us == WHITE_SIDE ? 7 : 0
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
    var pawns = set(us, PAWN)
    while pawns != 0 {
      let from = popLowest(&pawns)
      let one = from + forward
      if board[one] == 0 {
        if !capturesOnly || rankOf(one) == lastRank { pawnTo(from, one, 0) }
        let two = one + forward
        if !capturesOnly && rankOf(from) == startRank && board[two] == 0 { out.append(pack(from, two, 0, DOUBLE_PUSH)) }
      }
      var hits = PAWN_ATTACKS[us][from] & enemy
      while hits != 0 { pawnTo(from, popLowest(&hits), CAPTURE) }
      if ep >= 0 && PAWN_ATTACKS[us][from] & bit(ep) != 0 { out.append(pack(from, ep, 0, CAPTURE | EN_PASSANT)) }
    }

    // Pieces.
    for type in KNIGHT...KING {
      var from = set(us, type)
      while from != 0 {
        let f = popLowest(&from)
        let attacks: Bitboard
        switch type {
        case KNIGHT: attacks = KNIGHT_ATTACKS[f]
        case BISHOP: attacks = bishopAttacks(f, occ)
        case ROOK: attacks = rookAttacks(f, occ)
        case QUEEN: attacks = bishopAttacks(f, occ) | rookAttacks(f, occ)
        default: attacks = KING_ATTACKS[f]
        }
        var to = attacks & targets
        while to != 0 {
          let t = popLowest(&to)
          out.append(pack(f, t, 0, enemy & bit(t) != 0 ? CAPTURE : 0))
        }
      }
    }
    if !capturesOnly { castleMoves(&out) }
    return out
  }

  private func castleMoves(_ out: inout [Int]) {
    let them = side ^ 1
    let occ = occupied
    if side == WHITE_SIDE && kings[0] == 4 {
      if castling & 1 != 0 && occ & (bit(5) | bit(6)) == 0 && board[7] == ROOK && !attacked(4, by: them) && !attacked(5, by: them) {
        out.append(pack(4, 6, 0, CASTLE))
      }
      if castling & 2 != 0 && occ & (bit(1) | bit(2) | bit(3)) == 0 && board[0] == ROOK && !attacked(4, by: them) && !attacked(3, by: them) {
        out.append(pack(4, 2, 0, CASTLE))
      }
    } else if side == BLACK_SIDE && kings[1] == 60 {
      if castling & 4 != 0 && occ & (bit(61) | bit(62)) == 0 && board[63] == (ROOK | BLACK) && !attacked(60, by: them) && !attacked(61, by: them) {
        out.append(pack(60, 62, 0, CASTLE))
      }
      if castling & 8 != 0 && occ & (bit(57) | bit(58) | bit(59)) == 0 && board[56] == (ROOK | BLACK) && !attacked(60, by: them) && !attacked(59, by: them) {
        out.append(pack(60, 58, 0, CASTLE))
      }
    }
  }

  /// Play a move. False, with the move already taken back, when it leaves the mover in check.
  func make(_ m: Int) -> Bool {
    let from = fromOf(m), to = toOf(m), flags = flagsOf(m)
    let piece = board[from]
    let forward = side == WHITE_SIDE ? 8 : -8
    let capturedAt = flags & EN_PASSANT != 0 ? to - forward : to
    let captured = board[capturedAt]
    history.append(captured | (castling << 4) | ((ep + 1) << 8) | (halfmove << 16))
    past.append(key)

    if captured != 0 {
      toggle(captured, capturedAt)
      remove(captured, capturedAt)
    }
    toggle(piece, from)
    remove(piece, from)
    let promo = promoOf(m)
    let landed = promo != 0 ? promo | (piece & BLACK) : piece
    put(landed, to)
    toggle(landed, to)

    if piece & 7 == KING {
      kings[side] = to
      if flags & CASTLE != 0 {
        let (rookFrom, rookTo) = to > from ? (to + 1, to - 1) : (to - 2, to + 1)
        let rook = board[rookFrom]
        toggle(rook, rookFrom)
        toggle(rook, rookTo)
        remove(rook, rookFrom)
        put(rook, rookTo)
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
    let moved = board[to]
    let piece = promoOf(m) != 0 ? PAWN | (moved & BLACK) : moved
    let forward = side == WHITE_SIDE ? 8 : -8
    remove(moved, to)
    put(piece, from)
    let captured = state & 15
    if captured != 0 { put(captured, flags & EN_PASSANT != 0 ? to - forward : to) }
    if piece & 7 == KING {
      kings[side] = from
      if flags & CASTLE != 0 {
        let (rookFrom, rookTo) = to > from ? (to + 1, to - 1) : (to - 2, to + 1)
        let rook = board[rookTo]
        remove(rook, rookTo)
        put(rook, rookFrom)
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
    bySide[who] & ~(set(who, PAWN) | set(who, KING)) != 0
  }
}
