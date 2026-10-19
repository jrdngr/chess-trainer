/**
 * The backup engine's own board: 0x88 squares, moves packed into numbers, and
 * make/unmake in place.
 *
 * chess.js builds a fresh position for every move it is asked about, which is
 * fine for the app and far too slow for a search that wants to look at a few
 * hundred thousand positions a second. Nothing here imports anything, so the
 * whole engine can run inside a worker on its own.
 */

export const PAWN = 1;
export const KNIGHT = 2;
export const BISHOP = 3;
export const ROOK = 4;
export const QUEEN = 5;
export const KING = 6;
/** Set on a piece code for Black. */
export const BLACK = 8;

export const WHITE_SIDE = 0;
export const BLACK_SIDE = 1;

/** Move flags. */
export const CAPTURE = 1;
export const EN_PASSANT = 2;
export const CASTLE = 4;
export const DOUBLE_PUSH = 8;

const KNIGHT_STEPS = [33, 31, 18, 14, -33, -31, -18, -14];
const KING_STEPS = [1, -1, 16, -16, 15, 17, -15, -17];
const DIAGONALS = [15, 17, -15, -17];
const LINES = [1, -1, 16, -16];

const PIECE_CHARS = ' pnbrqk';

/** Castling rights kept after a move touches a square: rooks and kings losing theirs. */
const CASTLE_KEEP = new Uint8Array(128).fill(15);
CASTLE_KEEP[0x04] = 15 & ~3; // e1
CASTLE_KEEP[0x00] = 15 & ~2; // a1
CASTLE_KEEP[0x07] = 15 & ~1; // h1
CASTLE_KEEP[0x74] = 15 & ~12; // e8
CASTLE_KEEP[0x70] = 15 & ~8; // a8
CASTLE_KEEP[0x77] = 15 & ~4; // h8

/** Zobrist keys, two 32-bit halves each, from a fixed seed so every run hashes alike. */
let seed = 0x9e3779b9;
function random32(): number {
  seed ^= seed << 13;
  seed ^= seed >>> 17;
  seed ^= seed << 5;
  return seed | 0;
}
const ZOBRIST_LO = Int32Array.from({ length: 16 * 128 }, random32);
const ZOBRIST_HI = Int32Array.from({ length: 16 * 128 }, random32);
const CASTLE_LO = Int32Array.from({ length: 16 }, random32);
const CASTLE_HI = Int32Array.from({ length: 16 }, random32);
const EP_LO = Int32Array.from({ length: 8 }, random32);
const EP_HI = Int32Array.from({ length: 8 }, random32);
const SIDE_LO = random32();
const SIDE_HI = random32();

export const fromOf = (m: number) => m & 127;
export const toOf = (m: number) => (m >> 7) & 127;
export const promoOf = (m: number) => (m >> 14) & 7;
export const flagsOf = (m: number) => m >> 17;

const pack = (from: number, to: number, promo: number, flags: number) => from | (to << 7) | (promo << 14) | (flags << 17);

export const onBoard = (sq: number) => (sq & 0x88) === 0;
export const fileOf = (sq: number) => sq & 7;
export const rankOf = (sq: number) => sq >> 4;

function squareName(sq: number): string {
  return String.fromCharCode(97 + fileOf(sq)) + String(rankOf(sq) + 1);
}

function parseSquare(name: string): number {
  return (Number(name[1]) - 1) * 16 + (name.charCodeAt(0) - 97);
}

export function moveToUci(m: number): string {
  const promo = promoOf(m);
  return squareName(fromOf(m)) + squareName(toOf(m)) + (promo ? PIECE_CHARS[promo] : '');
}

export class Position {
  readonly sq = new Int8Array(128);
  /** 0 White, 1 Black. */
  side = WHITE_SIDE;
  /** 1 White short, 2 White long, 4 Black short, 8 Black long. */
  castling = 0;
  ep = -1;
  halfmove = 0;
  readonly kings = [0, 0];
  /** Zobrist key of the position, low and high halves. */
  keyLo = 0;
  keyHi = 0;
  private readonly history: number[] = [];
  /** Keys before each move played, for repetitions and for taking moves back. */
  readonly pastLo: number[] = [];
  readonly pastHi: number[] = [];

  constructor(fen: string) {
    const [placement, turn, castling, ep, halfmove] = fen.trim().split(/\s+/);
    let rank = 7;
    let file = 0;
    for (const ch of placement) {
      if (ch === '/') {
        rank -= 1;
        file = 0;
      } else if (ch >= '1' && ch <= '8') {
        file += Number(ch);
      } else {
        const lower = ch.toLowerCase();
        const type = PIECE_CHARS.indexOf(lower);
        const black = ch === lower;
        const square = rank * 16 + file;
        this.sq[square] = type | (black ? BLACK : 0);
        if (type === KING) this.kings[black ? 1 : 0] = square;
        file += 1;
      }
    }
    this.side = turn === 'b' ? BLACK_SIDE : WHITE_SIDE;
    this.castling =
      (castling?.includes('K') ? 1 : 0) |
      (castling?.includes('Q') ? 2 : 0) |
      (castling?.includes('k') ? 4 : 0) |
      (castling?.includes('q') ? 8 : 0);
    this.ep = ep && ep !== '-' ? parseSquare(ep) : -1;
    this.halfmove = Number(halfmove) || 0;
    this.rehash();
  }

  private rehash() {
    let lo = 0;
    let hi = 0;
    for (let s = 0; s < 128; s++) {
      if (s & 0x88 || !this.sq[s]) continue;
      lo ^= ZOBRIST_LO[this.sq[s] * 128 + s];
      hi ^= ZOBRIST_HI[this.sq[s] * 128 + s];
    }
    lo ^= CASTLE_LO[this.castling];
    hi ^= CASTLE_HI[this.castling];
    if (this.ep >= 0) {
      lo ^= EP_LO[fileOf(this.ep)];
      hi ^= EP_HI[fileOf(this.ep)];
    }
    if (this.side === BLACK_SIDE) {
      lo ^= SIDE_LO;
      hi ^= SIDE_HI;
    }
    this.keyLo = lo;
    this.keyHi = hi;
  }

  private toggle(piece: number, s: number) {
    this.keyLo ^= ZOBRIST_LO[piece * 128 + s];
    this.keyHi ^= ZOBRIST_HI[piece * 128 + s];
  }

  /** This position came up before, since the last capture or pawn move. */
  repeated(): boolean {
    const n = this.pastLo.length;
    for (let i = n - 2; i >= 0 && i >= n - this.halfmove; i -= 2) {
      if (this.pastLo[i] === this.keyLo && this.pastHi[i] === this.keyHi) return true;
    }
    return false;
  }

  /** Is this square attacked by the given side? */
  attacked(target: number, by: number): boolean {
    const sq = this.sq;
    const colour = by === BLACK_SIDE ? BLACK : 0;
    // Pawns attack diagonally forward, so look diagonally backward from the target.
    if (by === WHITE_SIDE) {
      if (onBoard(target - 15) && sq[target - 15] === PAWN) return true;
      if (onBoard(target - 17) && sq[target - 17] === PAWN) return true;
    } else {
      if (onBoard(target + 15) && sq[target + 15] === (PAWN | BLACK)) return true;
      if (onBoard(target + 17) && sq[target + 17] === (PAWN | BLACK)) return true;
    }
    for (const step of KNIGHT_STEPS) {
      const s = target + step;
      if (onBoard(s) && sq[s] === (KNIGHT | colour)) return true;
    }
    for (const step of KING_STEPS) {
      const s = target + step;
      if (onBoard(s) && sq[s] === (KING | colour)) return true;
    }
    for (const step of DIAGONALS) {
      for (let s = target + step; onBoard(s); s += step) {
        const p = sq[s];
        if (!p) continue;
        if (p === (BISHOP | colour) || p === (QUEEN | colour)) return true;
        break;
      }
    }
    for (const step of LINES) {
      for (let s = target + step; onBoard(s); s += step) {
        const p = sq[s];
        if (!p) continue;
        if (p === (ROOK | colour) || p === (QUEEN | colour)) return true;
        break;
      }
    }
    return false;
  }

  inCheck(side = this.side): boolean {
    return this.attacked(this.kings[side], side ^ 1);
  }

  /**
   * Every move the side to move can make, leaving its own king in check
   * included: the search finds those out by making them, which is cheaper
   * than proving every move legal up front. With `capturesOnly`, captures
   * and queen promotions.
   */
  pseudoMoves(capturesOnly = false): number[] {
    const out: number[] = [];
    const sq = this.sq;
    const us = this.side === BLACK_SIDE ? BLACK : 0;
    const forward = this.side === WHITE_SIDE ? 16 : -16;
    const startRank = this.side === WHITE_SIDE ? 1 : 6;
    const lastRank = this.side === WHITE_SIDE ? 7 : 0;
    const enemy = (p: number) => p !== 0 && (p & BLACK) !== us;

    const pawnTo = (from: number, to: number, flags: number) => {
      if (rankOf(to) === lastRank) {
        out.push(pack(from, to, QUEEN, flags));
        if (!capturesOnly) {
          out.push(pack(from, to, KNIGHT, flags));
          out.push(pack(from, to, ROOK, flags));
          out.push(pack(from, to, BISHOP, flags));
        }
      } else {
        out.push(pack(from, to, 0, flags));
      }
    };

    for (let from = 0; from < 128; from++) {
      if (from & 0x88) {
        from += 7;
        continue;
      }
      const piece = sq[from];
      if (!piece || (piece & BLACK) !== us) continue;
      const type = piece & 7;

      if (type === PAWN) {
        const one = from + forward;
        if (onBoard(one) && !sq[one]) {
          if (!capturesOnly || rankOf(one) === lastRank) pawnTo(from, one, 0);
          const two = one + forward;
          if (!capturesOnly && rankOf(from) === startRank && !sq[two]) out.push(pack(from, two, 0, DOUBLE_PUSH));
        }
        for (const side of [forward - 1, forward + 1]) {
          const to = from + side;
          if (!onBoard(to)) continue;
          if (enemy(sq[to])) pawnTo(from, to, CAPTURE);
          else if (to === this.ep) out.push(pack(from, to, 0, CAPTURE | EN_PASSANT));
        }
        continue;
      }

      if (type === KNIGHT || type === KING) {
        for (const step of type === KNIGHT ? KNIGHT_STEPS : KING_STEPS) {
          const to = from + step;
          if (!onBoard(to)) continue;
          const target = sq[to];
          if (!target) {
            if (!capturesOnly) out.push(pack(from, to, 0, 0));
          } else if (enemy(target)) {
            out.push(pack(from, to, 0, CAPTURE));
          }
        }
        if (type === KING && !capturesOnly) this.castleMoves(from, out);
        continue;
      }

      const steps = type === BISHOP ? DIAGONALS : type === ROOK ? LINES : KING_STEPS;
      for (const step of steps) {
        for (let to = from + step; onBoard(to); to += step) {
          const target = sq[to];
          if (!target) {
            if (!capturesOnly) out.push(pack(from, to, 0, 0));
            continue;
          }
          if (enemy(target)) out.push(pack(from, to, 0, CAPTURE));
          break;
        }
      }
    }
    return out;
  }

  private castleMoves(from: number, out: number[]) {
    const sq = this.sq;
    const them = this.side ^ 1;
    if (this.side === WHITE_SIDE && from === 0x04) {
      if (this.castling & 1 && !sq[0x05] && !sq[0x06] && sq[0x07] === ROOK) {
        if (!this.attacked(0x04, them) && !this.attacked(0x05, them)) out.push(pack(0x04, 0x06, 0, CASTLE));
      }
      if (this.castling & 2 && !sq[0x03] && !sq[0x02] && !sq[0x01] && sq[0x00] === ROOK) {
        if (!this.attacked(0x04, them) && !this.attacked(0x03, them)) out.push(pack(0x04, 0x02, 0, CASTLE));
      }
    } else if (this.side === BLACK_SIDE && from === 0x74) {
      if (this.castling & 4 && !sq[0x75] && !sq[0x76] && sq[0x77] === (ROOK | BLACK)) {
        if (!this.attacked(0x74, them) && !this.attacked(0x75, them)) out.push(pack(0x74, 0x76, 0, CASTLE));
      }
      if (this.castling & 8 && !sq[0x73] && !sq[0x72] && !sq[0x71] && sq[0x70] === (ROOK | BLACK)) {
        if (!this.attacked(0x74, them) && !this.attacked(0x73, them)) out.push(pack(0x74, 0x72, 0, CASTLE));
      }
    }
  }

  /**
   * Play a move. Returns false, with the move already taken back, when it
   * leaves the mover's own king in check.
   */
  make(m: number): boolean {
    const sq = this.sq;
    const from = fromOf(m);
    const to = toOf(m);
    const flags = flagsOf(m);
    const piece = sq[from];
    const forward = this.side === WHITE_SIDE ? 16 : -16;
    const capturedAt = flags & EN_PASSANT ? to - forward : to;
    const captured = sq[capturedAt];

    this.history.push(captured | (this.castling << 4) | ((this.ep + 1) << 8) | (this.halfmove << 16));
    this.pastLo.push(this.keyLo);
    this.pastHi.push(this.keyHi);

    if (captured) this.toggle(captured, capturedAt);
    this.toggle(piece, from);
    sq[capturedAt] = 0;
    sq[from] = 0;
    const promo = promoOf(m);
    sq[to] = promo ? promo | (piece & BLACK) : piece;
    this.toggle(sq[to], to);

    if ((piece & 7) === KING) {
      this.kings[this.side] = to;
      if (flags & CASTLE) {
        const [rookFrom, rookTo] = to > from ? [to + 1, to - 1] : [to - 2, to + 1];
        this.toggle(sq[rookFrom], rookFrom);
        this.toggle(sq[rookFrom], rookTo);
        sq[rookTo] = sq[rookFrom];
        sq[rookFrom] = 0;
      }
    }

    this.keyLo ^= CASTLE_LO[this.castling];
    this.keyHi ^= CASTLE_HI[this.castling];
    this.castling &= CASTLE_KEEP[from] & CASTLE_KEEP[to];
    this.keyLo ^= CASTLE_LO[this.castling] ^ SIDE_LO;
    this.keyHi ^= CASTLE_HI[this.castling] ^ SIDE_HI;
    if (this.ep >= 0) {
      this.keyLo ^= EP_LO[fileOf(this.ep)];
      this.keyHi ^= EP_HI[fileOf(this.ep)];
    }
    this.ep = flags & DOUBLE_PUSH ? from + forward : -1;
    if (this.ep >= 0) {
      this.keyLo ^= EP_LO[fileOf(this.ep)];
      this.keyHi ^= EP_HI[fileOf(this.ep)];
    }
    this.halfmove = captured || (piece & 7) === PAWN ? 0 : this.halfmove + 1;
    this.side ^= 1;

    if (this.inCheck(this.side ^ 1)) {
      this.unmake(m);
      return false;
    }
    return true;
  }

  unmake(m: number) {
    const sq = this.sq;
    const state = this.history.pop()!;
    this.side ^= 1;
    const from = fromOf(m);
    const to = toOf(m);
    const flags = flagsOf(m);
    const moved = sq[to];
    const piece = promoOf(m) ? PAWN | (moved & BLACK) : moved;
    const forward = this.side === WHITE_SIDE ? 16 : -16;

    sq[from] = piece;
    sq[to] = 0;
    sq[flags & EN_PASSANT ? to - forward : to] = state & 15;

    if ((piece & 7) === KING) {
      this.kings[this.side] = from;
      if (flags & CASTLE) {
        const [rookFrom, rookTo] = to > from ? [to + 1, to - 1] : [to - 2, to + 1];
        sq[rookFrom] = sq[rookTo];
        sq[rookTo] = 0;
      }
    }

    this.castling = (state >> 4) & 15;
    this.ep = ((state >> 8) & 255) - 1;
    this.halfmove = state >>> 16;
    this.keyLo = this.pastLo.pop()!;
    this.keyHi = this.pastHi.pop()!;
  }

  /** Pass, for null-move pruning. */
  makeNull() {
    this.history.push((this.castling << 4) | ((this.ep + 1) << 8) | (this.halfmove << 16));
    this.pastLo.push(this.keyLo);
    this.pastHi.push(this.keyHi);
    if (this.ep >= 0) {
      this.keyLo ^= EP_LO[fileOf(this.ep)];
      this.keyHi ^= EP_HI[fileOf(this.ep)];
    }
    this.keyLo ^= SIDE_LO;
    this.keyHi ^= SIDE_HI;
    this.ep = -1;
    this.side ^= 1;
  }

  unmakeNull() {
    const state = this.history.pop()!;
    this.side ^= 1;
    this.ep = ((state >> 8) & 255) - 1;
    this.keyLo = this.pastLo.pop()!;
    this.keyHi = this.pastHi.pop()!;
  }

  /** The key worked out from scratch, to check the running one against. */
  freshKey(): [number, number] {
    const keep = [this.keyLo, this.keyHi];
    this.rehash();
    const fresh: [number, number] = [this.keyLo, this.keyHi];
    [this.keyLo, this.keyHi] = keep;
    return fresh;
  }

  /** The legal moves, for the root. */
  legalMoves(): number[] {
    return this.pseudoMoves().filter((m) => {
      if (!this.make(m)) return false;
      this.unmake(m);
      return true;
    });
  }

  /** Any knight, bishop, rook or queen left for this side: null moves are unsafe without. */
  hasPieces(side: number): boolean {
    const colour = side === BLACK_SIDE ? BLACK : 0;
    for (let s = 0; s < 128; s++) {
      if (s & 0x88) {
        s += 7;
        continue;
      }
      const p = this.sq[s];
      if (p && (p & BLACK) === colour && (p & 7) !== PAWN && (p & 7) !== KING) return true;
    }
    return false;
  }
}
