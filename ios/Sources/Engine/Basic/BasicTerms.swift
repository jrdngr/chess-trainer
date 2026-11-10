/// The parts of a position the piece-square tables can't see: how freely
/// the pieces move, rooks on open files, a king stuck in the middle, pieces
/// under threat and whose move it is. Weights were fitted to Stockfish's
/// scores of positions from the book; tempo's endgame weight is set by hand,
/// as the book has few endgames to fit it on.

private let FILE_A: Bitboard = 0x0101_0101_0101_0101

/// Middlegame and endgame scores of the terms, White's side.
@inline(__always) func termScore(_ pos: Position) -> (mg: Int, eg: Int) {
  let at = ATTACKS
  let occupied = pos.occupied
  var pawnAttacks = SIMD2<Bitboard>(0, 0)
  var minorAttacks = SIMD2<Bitboard>(0, 0)
  var rookAttacks = SIMD2<Bitboard>(0, 0)
  var all = SIMD2<Bitboard>(0, 0)
  for side in 0..<2 {
    var p = pos.set(side, PAWN)
    while p != 0 { pawnAttacks[side] |= at.pawn[side << 6 | popLowest(&p)] }
  }
  var mg = 0, both = 0
  for side in 0..<2 {
    let sign = side == 0 ? 1 : -1
    // Safe squares: not its own pieces, not covered by enemy pawns.
    let safe = ~pos.bySide[side] & ~pawnAttacks[side ^ 1]
    var mobility = 0
    var n = pos.set(side, KNIGHT)
    while n != 0 {
      let reach = at.knight[popLowest(&n)]
      minorAttacks[side] |= reach
      mobility += 3 * (reach & safe).nonzeroBitCount
    }
    var b = pos.set(side, BISHOP)
    while b != 0 {
      let reach = at.bishop(popLowest(&b), occupied)
      minorAttacks[side] |= reach
      mobility += 2 * (reach & safe).nonzeroBitCount
    }
    let ownPawns = pos.set(side, PAWN), enemyPawns = pos.set(side ^ 1, PAWN)
    var r = pos.set(side, ROOK)
    while r != 0 {
      let s = popLowest(&r)
      let reach = at.rook(s, occupied)
      rookAttacks[side] |= reach
      mobility += 2 * (reach & safe).nonzeroBitCount
      let file = FILE_A << UInt64(fileOf(s))
      if file & ownPawns == 0 { mg += sign * (file & enemyPawns == 0 ? 31 : 44) }
    }
    var q = pos.set(side, QUEEN)
    var queenReach: Bitboard = 0
    while q != 0 {
      let s = popLowest(&q)
      let reach = at.rook(s, occupied) | at.bishop(s, occupied)
      queenReach |= reach
      mobility += 2 * (reach & safe).nonzeroBitCount
    }
    all[side] = pawnAttacks[side] | at.king[pos.kings[side]] | minorAttacks[side] | rookAttacks[side] | queenReach
    both += sign * mobility
    // The king left in the middle with castling gone, while the enemy queen is on.
    let king = pos.kings[side]
    let rights = side == 0 ? pos.castling & 3 : pos.castling & 12
    if rights == 0 && fileOf(king) >= 2 && fileOf(king) <= 5 && pos.set(side ^ 1, QUEEN) != 0 { mg -= sign * 19 }
  }

  // Pieces attacked by something cheaper, or attacked and unguarded. The side to
  // move can save one; the side that just moved is worse off.
  for side in 0..<2 {
    let enemy = side ^ 1
    let minors = pos.set(side, KNIGHT) | pos.set(side, BISHOP)
    let rooks = pos.set(side, ROOK), queens = pos.set(side, QUEEN)
    let pieces = minors | rooks | queens
    let threatened = (pieces & pawnAttacks[enemy] | (rooks | queens) & minorAttacks[enemy] | queens & rookAttacks[enemy]
      | pieces & all[enemy] & ~all[side]).nonzeroBitCount
    if threatened == 0 { continue }
    let sign = side == 0 ? -1 : 1
    if side == pos.side {
      both += sign * (3 * threatened + (threatened >= 2 ? 3 : 0))
    } else {
      both += sign * 11 * threatened
    }
  }
  let tempo = pos.side == WHITE_SIDE ? 1 : -1
  return (mg + both + 44 * tempo, both + 15 * tempo)
}
