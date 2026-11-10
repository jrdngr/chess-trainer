/// The engine's view of a position, in centipawns for the side to
/// move: PeSTO's values and tables blended by phase, a bishop pair, pawn
/// structure, a king shield and the terms in BasicTerms.swift.

private let MG_VALUE = [0, 82, 337, 365, 477, 1025, 0]
private let EG_VALUE = [0, 94, 281, 297, 512, 936, 0]
private let PHASE = [0, 0, 1, 1, 2, 4, 0]

/// Evaluation tables in flat buffers, like the attack tables.
private struct EvalTables: @unchecked Sendable {
  /// Piece value plus square, piece code * 64 + square.
  let mg: UnsafeMutablePointer<Int>
  let eg: UnsafeMutablePointer<Int>
  /// The squares in front of a pawn on its own file and both neighbours, side * 64 + square.
  let passed: UnsafeMutablePointer<Bitboard>
  let files: UnsafeMutablePointer<Bitboard>
  /// The files either side of each file.
  let neighbours: UnsafeMutablePointer<Bitboard>

  init() {
    mg = .allocate(capacity: 16 * 64)
    eg = .allocate(capacity: 16 * 64)
    mg.initialize(repeating: 0, count: 16 * 64)
    eg.initialize(repeating: 0, count: 16 * 64)
    for type in PAWN...KING {
      for sq in 0..<64 {
        // The tables run from a8, as White sees the board.
        let white = sq ^ 56
        let black = sq
        mg[type << 6 | sq] = MG_VALUE[type] + MG_TABLES[type][white]
        eg[type << 6 | sq] = EG_VALUE[type] + EG_TABLES[type][white]
        mg[(type | BLACK) << 6 | sq] = MG_VALUE[type] + MG_TABLES[type][black]
        eg[(type | BLACK) << 6 | sq] = EG_VALUE[type] + EG_TABLES[type][black]
      }
    }
    files = .allocate(capacity: 8)
    neighbours = .allocate(capacity: 8)
    for f in 0..<8 { files[f] = 0x0101_0101_0101_0101 << UInt64(f) }
    for f in 0..<8 { neighbours[f] = (f > 0 ? files[f - 1] : 0) | (f < 7 ? files[f + 1] : 0) }
    passed = .allocate(capacity: 128)
    for side in 0..<2 {
      for sq in 0..<64 {
        var mask: Bitboard = 0
        let f = fileOf(sq)
        for nf in max(0, f - 1)...min(7, f + 1) {
          for r in 0..<8 where side == 0 ? r > rankOf(sq) : r < rankOf(sq) { mask |= bit(r * 8 + nf) }
        }
        passed[side << 6 | sq] = mask
      }
    }
  }
}

private let EVAL = EvalTables()

/// Material values for ordering captures and pruning hopeless ones.
let PIECE_VALUE = [0, 100, 320, 330, 500, 900, 20000]

private let PASSED_MG = [0, 5, 10, 15, 25, 40, 60, 0]
private let PASSED_EG = [0, 10, 20, 35, 60, 100, 150, 0]

func evaluate(_ pos: Position) -> Int {
  let t = EVAL
  var mg = 0, eg = 0, phase = 0
  for side in 0..<2 {
    let sign = side == 1 ? -1 : 1
    for type in PAWN...KING {
      let code = type | (side == 1 ? BLACK : 0)
      var each = pos.pieces[code]
      phase += PHASE[type] * each.nonzeroBitCount
      while each != 0 {
        let s = popLowest(&each)
        mg += sign * t.mg[code << 6 | s]
        eg += sign * t.eg[code << 6 | s]
      }
    }
    if pos.set(side, BISHOP).nonzeroBitCount >= 2 {
      mg += sign * 30
      eg += sign * 50
    }
    let pawns = pos.set(side, PAWN)
    let enemyPawns = pos.set(side ^ 1, PAWN)
    for f in 0..<8 {
      let count = (pawns & t.files[f]).nonzeroBitCount
      if count > 1 {
        mg -= sign * 10 * (count - 1)
        eg -= sign * 20 * (count - 1)
      }
    }
    var each = pawns
    while each != 0 {
      let s = popLowest(&each)
      if pawns & t.neighbours[fileOf(s)] == 0 {
        mg -= sign * 12
        eg -= sign * 15
      }
      if t.passed[side << 6 | s] & enemyPawns == 0 {
        let advance = side == 1 ? 7 - rankOf(s) : rankOf(s)
        mg += sign * PASSED_MG[advance]
        eg += sign * PASSED_EG[advance]
      }
    }
    mg += sign * kingShield(pos, side)
  }
  let extra = termScore(pos)
  mg += extra.mg
  eg += extra.eg
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
