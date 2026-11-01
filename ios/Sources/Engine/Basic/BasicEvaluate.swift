/// The engine's view of a position, in centipawns for the side to
/// move: PeSTO's values and tables blended by phase, a bishop pair, pawn
/// structure and a king shield. `src/engine/basic/evaluate.ts`.

private let MG_VALUE = [0, 82, 337, 365, 477, 1025, 0]
private let EG_VALUE = [0, 94, 281, 297, 512, 936, 0]
private let PHASE = [0, 0, 1, 1, 2, 4, 0]

/// Piece value plus square, per piece code and square.
private let TABLES: (mg: [[Int]], eg: [[Int]]) = {
  var mg = [[Int]](repeating: [Int](repeating: 0, count: 64), count: 16)
  var eg = mg
  for type in PAWN...KING {
    for sq in 0..<64 {
      // The tables run from a8, as White sees the board.
      let white = sq ^ 56
      let black = sq
      mg[type][sq] = MG_VALUE[type] + MG_TABLES[type][white]
      eg[type][sq] = EG_VALUE[type] + EG_TABLES[type][white]
      mg[type | BLACK][sq] = MG_VALUE[type] + MG_TABLES[type][black]
      eg[type | BLACK][sq] = EG_VALUE[type] + EG_TABLES[type][black]
    }
  }
  return (mg, eg)
}()

private let FILE_A: Bitboard = 0x0101_0101_0101_0101
private let FILES: [Bitboard] = (0..<8).map { FILE_A << UInt64($0) }

/// The squares in front of a pawn on its own file and both neighbours.
private let PASSED_MASK: [[Bitboard]] = (0..<2).map { side in
  (0..<64).map { sq in
    var mask: Bitboard = 0
    let f = fileOf(sq)
    for nf in max(0, f - 1)...min(7, f + 1) {
      for r in 0..<8 where side == 0 ? r > rankOf(sq) : r < rankOf(sq) { mask |= bit(r * 8 + nf) }
    }
    return mask
  }
}

/// Material values for ordering captures and pruning hopeless ones.
let PIECE_VALUE = [0, 100, 320, 330, 500, 900, 20000]

private let PASSED_MG = [0, 5, 10, 15, 25, 40, 60, 0]
private let PASSED_EG = [0, 10, 20, 35, 60, 100, 150, 0]

func evaluate(_ pos: Position) -> Int {
  var mg = 0, eg = 0, phase = 0
  for side in 0..<2 {
    let sign = side == 1 ? -1 : 1
    for type in PAWN...KING {
      let code = type | (side == 1 ? BLACK : 0)
      var set = pos.pieces[code]
      phase += PHASE[type] * set.nonzeroBitCount
      while set != 0 {
        let s = popLowest(&set)
        mg += sign * TABLES.mg[code][s]
        eg += sign * TABLES.eg[code][s]
      }
    }
    if pos.set(side, BISHOP).nonzeroBitCount >= 2 {
      mg += sign * 30
      eg += sign * 50
    }
    let pawns = pos.set(side, PAWN)
    let enemyPawns = pos.set(side ^ 1, PAWN)
    var files = [Int](repeating: 0, count: 8)
    for f in 0..<8 { files[f] = (pawns & FILES[f]).nonzeroBitCount }
    for f in 0..<8 where files[f] > 1 {
      mg -= sign * 10 * (files[f] - 1)
      eg -= sign * 20 * (files[f] - 1)
    }
    var each = pawns
    while each != 0 {
      let s = popLowest(&each)
      let f = fileOf(s)
      let isolated = (f == 0 || files[f - 1] == 0) && (f == 7 || files[f + 1] == 0)
      if isolated {
        mg -= sign * 12
        eg -= sign * 15
      }
      if PASSED_MASK[side][s] & enemyPawns == 0 {
        let advance = side == 1 ? 7 - rankOf(s) : rankOf(s)
        mg += sign * PASSED_MG[advance]
        eg += sign * PASSED_EG[advance]
      }
    }
    mg += sign * kingShield(pos, side)
  }
  let mgPhase = min(phase, 24)
  let score = Double(mg * mgPhase + eg * (24 - mgPhase)) / 24
  return Int(jsRound(pos.side == BLACK_SIDE ? -score : score))
}

/// `Math.round`, halves toward +infinity.
private func jsRound(_ x: Double) -> Double {
  let down = x.rounded(.down)
  return x - down >= 0.5 ? down + 1 : down
}

/// Pawns in front of a king tucked away on either wing, middlegame only.
private func kingShield(_ pos: Position, _ side: Int) -> Int {
  let king = pos.kings[side]
  let homeRank = side == 1 ? 7 : 0
  if rankOf(king) != homeRank { return 0 }
  let f = fileOf(king)
  if f >= 3 && f <= 4 { return 0 }
  let own = side == 1 ? PAWN | BLACK : PAWN
  let step = side == 1 ? -8 : 8
  var score = 0
  for df in -1...1 {
    let nf = f + df
    if nf < 0 || nf > 7 { continue }
    let base = homeRank * 8 + nf
    if pos.board[base + step] == own {
      score += 12
    } else if pos.board[base + 2 * step] == own {
      score += 6
    } else {
      score -= 10
    }
  }
  return score
}

/// Only kings, or a king and one minor piece against a bare king.
func insufficientMaterial(_ pos: Position) -> Bool {
  let heavy = pos.pieces[PAWN] | pos.pieces[PAWN | BLACK] | pos.pieces[ROOK] | pos.pieces[ROOK | BLACK]
    | pos.pieces[QUEEN] | pos.pieces[QUEEN | BLACK]
  if heavy != 0 { return false }
  let minors = pos.pieces[KNIGHT] | pos.pieces[KNIGHT | BLACK] | pos.pieces[BISHOP] | pos.pieces[BISHOP | BLACK]
  return minors.nonzeroBitCount <= 1
}
