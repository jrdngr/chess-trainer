import { BISHOP, BLACK, BLACK_SIDE, fileOf, KING, KNIGHT, PAWN, type Position, QUEEN, rankOf, ROOK } from './board';

/**
 * The backup engine's view of a position, in centipawns for the side to move.
 *
 * Piece values and square tables are PeSTO's (Ronald Friederich's tuned
 * tables, as published on the Chess Programming Wiki), blended between a
 * middlegame and an endgame set by how much material is left. On top: a
 * bishop pair, pawn structure (doubled, isolated, passed) and a pawn shield
 * in front of a castled king.
 */

const MG_VALUE = [0, 82, 337, 365, 477, 1025, 0];
const EG_VALUE = [0, 94, 281, 297, 512, 936, 0];
const PHASE = [0, 0, 1, 1, 2, 4, 0];

// Tables run a8..h8, a7..h7, … a1..h1, from White's side.
// prettier-ignore
const MG_TABLES: number[][] = [
  [],
  [
      0,   0,   0,   0,   0,   0,  0,   0,
     98, 134,  61,  95,  68, 126, 34, -11,
     -6,   7,  26,  31,  65,  56, 25, -20,
    -14,  13,   6,  21,  23,  12, 17, -23,
    -27,  -2,  -5,  12,  17,   6, 10, -25,
    -26,  -4,  -4, -10,   3,   3, 33, -12,
    -35,  -1, -20, -23, -15,  24, 38, -22,
      0,   0,   0,   0,   0,   0,  0,   0,
  ],
  [
    -167, -89, -34, -49,  61, -97, -15, -107,
     -73, -41,  72,  36,  23,  62,   7,  -17,
     -47,  60,  37,  65,  84, 129,  73,   44,
      -9,  17,  19,  53,  37,  69,  18,   22,
     -13,   4,  16,  13,  28,  19,  21,   -8,
     -23,  -9,  12,  10,  19,  17,  25,  -16,
     -29, -53, -12,  -3,  -1,  18, -14,  -19,
    -105, -21, -58, -33, -17, -28, -19,  -23,
  ],
  [
    -29,   4, -82, -37, -25, -42,   7,  -8,
    -26,  16, -18, -13,  30,  59,  18, -47,
    -16,  37,  43,  40,  35,  50,  37,  -2,
     -4,   5,  19,  50,  37,  37,   7,  -2,
     -6,  13,  13,  26,  34,  12,  10,   4,
      0,  15,  15,  15,  14,  27,  18,  10,
      4,  15,  16,   0,   7,  21,  33,   1,
    -33,  -3, -14, -21, -13, -12, -39, -21,
  ],
  [
     32,  42,  32,  51, 63,  9,  31,  43,
     27,  32,  58,  62, 80, 67,  26,  44,
     -5,  19,  26,  36, 17, 45,  61,  16,
    -24, -11,   7,  26, 24, 35,  -8, -20,
    -36, -26, -12,  -1,  9, -7,   6, -23,
    -45, -25, -16, -17,  3,  0,  -5, -33,
    -44, -16, -20,  -9, -1, 11,  -6, -71,
    -19, -13,   1,  17, 16,  7, -37, -26,
  ],
  [
    -28,   0,  29,  12,  59,  44,  43,  45,
    -24, -39,  -5,   1, -16,  57,  28,  54,
    -13, -17,   7,   8,  29,  56,  47,  57,
    -27, -27, -16, -16,  -1,  17,  -2,   1,
     -9, -26,  -9, -10,  -2,  -4,   3,  -3,
    -14,   2, -11,  -2,  -5,   2,  14,   5,
    -35,  -8,  11,   2,   8,  15,  -3,   1,
     -1, -18,  -9,  10, -15, -25, -31, -50,
  ],
  [
    -65,  23,  16, -15, -56, -34,   2,  13,
     29,  -1, -20,  -7,  -8,  -4, -38, -29,
     -9,  24,   2, -16, -20,   6,  22, -22,
    -17, -20, -12, -27, -30, -25, -14, -36,
    -49,  -1, -27, -39, -46, -44, -33, -51,
    -14, -14, -22, -46, -44, -30, -15, -27,
      1,   7,  -8, -64, -43, -16,   9,   8,
    -15,  36,  12, -54,   8, -28,  24,  14,
  ],
];

// prettier-ignore
const EG_TABLES: number[][] = [
  [],
  [
      0,   0,   0,   0,   0,   0,   0,   0,
    178, 173, 158, 134, 147, 132, 165, 187,
     94, 100,  85,  67,  56,  53,  82,  84,
     32,  24,  13,   5,  -2,   4,  17,  17,
     13,   9,  -3,  -7,  -7,  -8,   3,  -1,
      4,   7,  -6,   1,   0,  -5,  -1,  -8,
     13,   8,   8,  10,  13,   0,   2,  -7,
      0,   0,   0,   0,   0,   0,   0,   0,
  ],
  [
    -58, -38, -13, -28, -31, -27, -63, -99,
    -25,  -8, -25,  -2,  -9, -25, -24, -52,
    -24, -20,  10,   9,  -1,  -9, -19, -41,
    -17,   3,  22,  22,  22,  11,   8, -18,
    -18,  -6,  16,  25,  16,  17,   4, -18,
    -23,  -3,  -1,  15,  10,  -3, -20, -22,
    -42, -20, -10,  -5,  -2, -20, -23, -44,
    -29, -51, -23, -15, -22, -18, -50, -64,
  ],
  [
    -14, -21, -11,  -8, -7,  -9, -17, -24,
     -8,  -4,   7, -12, -3, -13,  -4, -14,
      2,  -8,   0,  -1, -2,   6,   0,   4,
     -3,   9,  12,   9, 14,  10,   3,   2,
     -6,   3,  13,  19,  7,  10,  -3,  -9,
    -12,  -3,   8,  10, 13,   3,  -7, -15,
    -14, -18,  -7,  -1,  4,  -9, -15, -27,
    -23,  -9, -23,  -5, -9, -16,  -5, -17,
  ],
  [
    13, 10, 18, 15, 12,  12,   8,   5,
    11, 13, 13, 11, -3,   3,   8,   3,
     7,  7,  7,  5,  4,  -3,  -5,  -3,
     4,  3, 13,  1,  2,   1,  -1,   2,
     3,  5,  8,  4, -5,  -6,  -8, -11,
    -4,  0, -5, -1, -7, -12,  -8, -16,
    -6, -6,  0,  2, -9,  -9, -11,  -3,
    -9,  2,  3, -1, -5, -13,   4, -20,
  ],
  [
     -9,  22,  22,  27,  27,  19,  10,  20,
    -17,  20,  32,  41,  58,  25,  30,   0,
    -20,   6,   9,  49,  47,  35,  19,   9,
      3,  22,  24,  45,  57,  40,  57,  36,
    -18,  28,  19,  47,  31,  34,  39,  23,
    -16, -27,  15,   6,   9,  17,  10,   5,
    -22, -23, -30, -16, -16, -23, -36, -32,
    -33, -28, -22, -43,  -5, -32, -20, -41,
  ],
  [
    -74, -35, -18, -18, -11,  15,   4, -17,
    -12,  17,  14,  17,  17,  38,  23,  11,
     10,  17,  23,  15,  20,  45,  44,  13,
     -8,  22,  24,  27,  26,  33,  26,   3,
    -18,  -4,  21,  24,  27,  23,   9, -11,
    -19,  -3,  11,  21,  23,  16,   7,  -9,
    -27, -11,   4,  13,  14,   4,  -5, -17,
    -53, -34, -21, -11, -28, -14, -24, -43,
  ],
];

/** Piece value plus square, per piece code and 0x88 square, built once. */
const MG = Array.from({ length: 16 }, () => new Int16Array(128));
const EG = Array.from({ length: 16 }, () => new Int16Array(128));
for (let type = PAWN; type <= KING; type++) {
  for (let sq = 0; sq < 128; sq++) {
    if (sq & 0x88) continue;
    const white = (7 - rankOf(sq)) * 8 + fileOf(sq);
    const black = rankOf(sq) * 8 + fileOf(sq);
    MG[type][sq] = MG_VALUE[type] + MG_TABLES[type][white];
    EG[type][sq] = EG_VALUE[type] + EG_TABLES[type][white];
    MG[type | BLACK][sq] = MG_VALUE[type] + MG_TABLES[type][black];
    EG[type | BLACK][sq] = EG_VALUE[type] + EG_TABLES[type][black];
  }
}

/** Material values for ordering captures and pruning hopeless ones. */
export const PIECE_VALUE = [0, 100, 320, 330, 500, 900, 20000];

const PASSED_MG = [0, 5, 10, 15, 25, 40, 60, 0];
const PASSED_EG = [0, 10, 20, 35, 60, 100, 150, 0];

export function evaluate(pos: Position): number {
  const sq = pos.sq;
  let mg = 0;
  let eg = 0;
  let phase = 0;
  const bishops = [0, 0];
  // Each side's pawns: how many on each file, and where each one stands.
  const pawnFiles = [new Int8Array(8), new Int8Array(8)];
  const pawnSquares: number[][] = [[], []];

  for (let s = 0; s < 128; s++) {
    if (s & 0x88) {
      s += 7;
      continue;
    }
    const p = sq[s];
    if (!p) continue;
    const type = p & 7;
    const side = p & BLACK ? 1 : 0;
    const sign = side ? -1 : 1;
    mg += sign * MG[p][s];
    eg += sign * EG[p][s];
    phase += PHASE[type];
    if (type === BISHOP) bishops[side]++;
    else if (type === PAWN) {
      pawnFiles[side][fileOf(s)]++;
      pawnSquares[side].push(s);
    }
  }

  for (let side = 0; side < 2; side++) {
    const sign = side ? -1 : 1;
    if (bishops[side] >= 2) {
      mg += sign * 30;
      eg += sign * 50;
    }
    const files = pawnFiles[side];
    for (let f = 0; f < 8; f++) {
      if (files[f] > 1) {
        mg -= sign * 10 * (files[f] - 1);
        eg -= sign * 20 * (files[f] - 1);
      }
    }
    for (const s of pawnSquares[side]) {
      const f = fileOf(s);
      const isolated = (f === 0 || !files[f - 1]) && (f === 7 || !files[f + 1]);
      if (isolated) {
        mg -= sign * 12;
        eg -= sign * 15;
      }
      if (passed(pos, s, side)) {
        const advance = side ? 7 - rankOf(s) : rankOf(s);
        mg += sign * PASSED_MG[advance];
        eg += sign * PASSED_EG[advance];
      }
    }
    mg += sign * kingShield(pos, side);
  }

  const mgPhase = Math.min(phase, 24);
  const score = (mg * mgPhase + eg * (24 - mgPhase)) / 24;
  return Math.round(pos.side === BLACK_SIDE ? -score : score);
}

/** No enemy pawn ahead of this one on its own file or either neighbour. */
function passed(pos: Position, s: number, side: number): boolean {
  const enemyPawn = side ? PAWN : PAWN | BLACK;
  const step = side ? -16 : 16;
  const f = fileOf(s);
  for (let ahead = s + step; ahead >= 0 && ahead < 128; ahead += step) {
    for (let df = -1; df <= 1; df++) {
      const nf = f + df;
      if (nf < 0 || nf > 7) continue;
      if (pos.sq[ahead - f + nf] === enemyPawn) return false;
    }
  }
  return true;
}

/** Pawns in front of a king tucked away on either wing, middlegame only. */
function kingShield(pos: Position, side: number): number {
  const king = pos.kings[side];
  const homeRank = side ? 7 : 0;
  if (rankOf(king) !== homeRank) return 0;
  const f = fileOf(king);
  if (f >= 3 && f <= 4) return 0;
  const own = side ? PAWN | BLACK : PAWN;
  const step = side ? -16 : 16;
  let score = 0;
  for (let df = -1; df <= 1; df++) {
    const nf = f + df;
    if (nf < 0 || nf > 7) continue;
    const base = homeRank * 16 + nf;
    if (pos.sq[base + step] === own) score += 12;
    else if (pos.sq[base + 2 * step] === own) score += 6;
    else score -= 10;
  }
  return score;
}

/** Only kings, or a king and one minor piece against a bare king: nobody can mate. */
export function insufficientMaterial(pos: Position): boolean {
  let minors = 0;
  for (let s = 0; s < 128; s++) {
    if (s & 0x88) {
      s += 7;
      continue;
    }
    const type = pos.sq[s] & 7;
    if (!type || type === KING) continue;
    if (type === PAWN || type === ROOK || type === QUEEN) return false;
    if (type === KNIGHT || type === BISHOP) minors++;
    if (minors > 1) return false;
  }
  return true;
}
