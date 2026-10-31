/// The backup engine's view of a position, in centipawns for the side to
/// move: PeSTO's values and tables blended by phase, a bishop pair, pawn
/// structure and a king shield. `src/engine/basic/evaluate.ts`.

private let MG_VALUE = [0, 82, 337, 365, 477, 1025, 0]
private let EG_VALUE = [0, 94, 281, 297, 512, 936, 0]
private let PHASE = [0, 0, 1, 1, 2, 4, 0]

/// Piece value plus square, per piece code and 0x88 square.
private let TABLES: (mg: [[Int]], eg: [[Int]]) = {
  var mg = [[Int]](repeating: [Int](repeating: 0, count: 128), count: 16)
  var eg = mg
  for type in PAWN...KING {
    for sq in 0..<128 where sq & 0x88 == 0 {
      let white = (7 - rankOf(sq)) * 8 + fileOf(sq)
      let black = rankOf(sq) * 8 + fileOf(sq)
      mg[type][sq] = MG_VALUE[type] + MG_TABLES[type][white]
      eg[type][sq] = EG_VALUE[type] + EG_TABLES[type][white]
      mg[type | BLACK][sq] = MG_VALUE[type] + MG_TABLES[type][black]
      eg[type | BLACK][sq] = EG_VALUE[type] + EG_TABLES[type][black]
    }
  }
  return (mg, eg)
}()

/// Material values for ordering captures and pruning hopeless ones.
let PIECE_VALUE = [0, 100, 320, 330, 500, 900, 20000]

private let PASSED_MG = [0, 5, 10, 15, 25, 40, 60, 0]
private let PASSED_EG = [0, 10, 20, 35, 60, 100, 150, 0]

func evaluate(_ pos: Position) -> Int {
  let sq = pos.sq
  var mg = 0, eg = 0, phase = 0
  var bishops = [0, 0]
  var pawnFiles = [[Int](repeating: 0, count: 8), [Int](repeating: 0, count: 8)]
  var pawnSquares: [[Int]] = [[], []]
  for s in 0..<128 where s & 0x88 == 0 {
    let p = sq[s]
    if p == 0 { continue }
    let type = p & 7
    let side = p & BLACK != 0 ? 1 : 0
    let sign = side == 1 ? -1 : 1
    mg += sign * TABLES.mg[p][s]
    eg += sign * TABLES.eg[p][s]
    phase += PHASE[type]
    if type == BISHOP {
      bishops[side] += 1
    } else if type == PAWN {
      pawnFiles[side][fileOf(s)] += 1
      pawnSquares[side].append(s)
    }
  }
  for side in 0..<2 {
    let sign = side == 1 ? -1 : 1
    if bishops[side] >= 2 {
      mg += sign * 30
      eg += sign * 50
    }
    let files = pawnFiles[side]
    for f in 0..<8 where files[f] > 1 {
      mg -= sign * 10 * (files[f] - 1)
      eg -= sign * 20 * (files[f] - 1)
    }
    for s in pawnSquares[side] {
      let f = fileOf(s)
      let isolated = (f == 0 || files[f - 1] == 0) && (f == 7 || files[f + 1] == 0)
      if isolated {
        mg -= sign * 12
        eg -= sign * 15
      }
      if passed(pos, s, side) {
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

/// No enemy pawn ahead of this one on its own file or either neighbour.
private func passed(_ pos: Position, _ s: Int, _ side: Int) -> Bool {
  let enemyPawn = side == 1 ? PAWN : PAWN | BLACK
  let step = side == 1 ? -16 : 16
  let f = fileOf(s)
  var ahead = s + step
  while ahead >= 0 && ahead < 128 {
    for df in -1...1 {
      let nf = f + df
      if nf < 0 || nf > 7 { continue }
      let at = ahead - f + nf
      if at >= 0 && at < 128 && pos.sq[at] == enemyPawn { return false }
    }
    ahead += step
  }
  return true
}

/// Pawns in front of a king tucked away on either wing, middlegame only.
private func kingShield(_ pos: Position, _ side: Int) -> Int {
  let king = pos.kings[side]
  let homeRank = side == 1 ? 7 : 0
  if rankOf(king) != homeRank { return 0 }
  let f = fileOf(king)
  if f >= 3 && f <= 4 { return 0 }
  let own = side == 1 ? PAWN | BLACK : PAWN
  let step = side == 1 ? -16 : 16
  var score = 0
  for df in -1...1 {
    let nf = f + df
    if nf < 0 || nf > 7 { continue }
    let base = homeRank * 16 + nf
    if pos.sq[base + step] == own {
      score += 12
    } else if pos.sq[base + 2 * step] == own {
      score += 6
    } else {
      score -= 10
    }
  }
  return score
}

/// Only kings, or a king and one minor piece against a bare king.
func insufficientMaterial(_ pos: Position) -> Bool {
  var minors = 0
  for s in 0..<128 where s & 0x88 == 0 {
    let type = pos.sq[s] & 7
    if type == 0 || type == KING { continue }
    if type == PAWN || type == ROOK || type == QUEEN { return false }
    if type == KNIGHT || type == BISHOP { minors += 1 }
    if minors > 1 { return false }
  }
  return true
}
