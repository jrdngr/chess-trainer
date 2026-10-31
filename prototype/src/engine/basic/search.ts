import { CAPTURE, flagsOf, fromOf, moveToUci, Position, promoOf, toOf } from './board';
import { evaluate, insufficientMaterial, PIECE_VALUE } from './evaluate';

/**
 * The backup engine's search: alpha-beta with iterative deepening, a capture
 * search at the leaves so it never stops looking with a piece hanging, and
 * the usual ordering tricks (last iteration's best line first, captures by
 * what they win, killer moves, history) so the cut-offs come early.
 *
 * It searches one whole depth at a time, and a depth that runs out of time
 * is thrown away: every line reported comes from the same finished depth,
 * which is what comparing two moves' scores needs.
 */

export const MATE = 30000;
const MATE_BOUND = MATE - 1000;
const MAX_PLY = 64;
const INF = 32000;

export interface RootLine {
  uci: string;
  /** Centipawns for the side to move at the root. */
  score: number;
  /** Mate in this many moves, positive for the side to move; null when there is none. */
  mate: number | null;
  pv: string[];
}

export interface DepthResult {
  depth: number;
  nodes: number;
  lines: RootLine[];
}

export interface SearchOptions {
  maxDepth: number;
  timeMs: number;
  multiPv: number;
  /** Only these root moves (UCI). */
  searchmoves?: string[];
  /** After each finished depth. */
  onDepth?: (result: DepthResult) => void;
  now?: () => number;
}

class OutOfTime extends Error {}

/**
 * Positions already searched, shared by every search on this page: the
 * same position reached by another order of moves, and the next depth of
 * the same search, start from the best move found last time.
 */
const TT_SIZE = 1 << 19;
const ttLo = new Int32Array(TT_SIZE);
const ttHi = new Int32Array(TT_SIZE);
const ttMove = new Int32Array(TT_SIZE);
const ttScore = new Int16Array(TT_SIZE);
const ttDepth = new Int8Array(TT_SIZE);
/** 0 empty, then whether the score is exact, a lower bound or an upper bound. */
const ttFlag = new Uint8Array(TT_SIZE);
const EXACT = 1;
const LOWER = 2;
const UPPER = 3;

/** Mate scores are kept counted from the stored position, not the root. */
const toTT = (score: number, ply: number) => (score > MATE_BOUND ? score + ply : score < -MATE_BOUND ? score - ply : score);
const fromTT = (score: number, ply: number) => (score > MATE_BOUND ? score - ply : score < -MATE_BOUND ? score + ply : score);

function mateIn(score: number): number | null {
  if (score > MATE_BOUND) return Math.ceil((MATE - score) / 2);
  if (score < -MATE_BOUND) return -Math.ceil((MATE + score) / 2);
  return null;
}

/** The deepest finished search of a position, or null when it has no legal moves. */
export function search(fen: string, options: SearchOptions): DepthResult | null {
  return new Searcher(new Position(fen), options).run();
}

class Searcher {
  private nodes = 0;
  private readonly deadline: number;
  private readonly now: () => number;
  private readonly killers = Array.from({ length: MAX_PLY }, () => [0, 0]);
  private readonly history = new Int32Array(128 * 128);
  private readonly pvTable = Array.from({ length: MAX_PLY }, () => new Int32Array(MAX_PLY));
  private readonly pvLength = new Int32Array(MAX_PLY);
  /** Last iteration's line for the root move being searched, tried first all the way down. */
  private previousPv: number[] = [];
  private followPv = false;
  private timed = false;

  constructor(
    private readonly pos: Position,
    private readonly options: SearchOptions,
  ) {
    this.now = options.now ?? (() => Date.now());
    this.deadline = this.now() + options.timeMs;
  }

  run(): DepthResult | null {
    const only = this.options.searchmoves?.length ? new Set(this.options.searchmoves) : null;
    let roots = this.pos.legalMoves().filter((m) => !only || only.has(moveToUci(m)));
    if (!roots.length) return null;
    const multiPv = Math.max(1, Math.min(this.options.multiPv, roots.length));
    const start = this.now();

    let best: DepthResult | null = null;
    let pvs = new Map<number, number[]>();
    const maxDepth = Math.max(1, Math.min(this.options.maxDepth, MAX_PLY - 8));
    for (let depth = 1; depth <= maxDepth; depth++) {
      // The first depth always finishes, so there is an answer however tight the time.
      this.timed = depth > 1;
      const scored: { move: number; score: number; exact: boolean; pv: number[] }[] = [];
      try {
        for (const move of roots) {
          const exact = scored.filter((s) => s.exact).sort((a, b) => b.score - a.score);
          const floor = exact.length >= multiPv ? exact[multiPv - 1].score : -INF;
          this.previousPv = pvs.get(move) ?? [];
          this.followPv = this.previousPv.length > 1;
          this.pos.make(move);
          let score: number;
          if (floor === -INF) {
            score = -this.negamax(depth - 1, -INF, INF, 1, true);
          } else {
            // Only worth an exact score if it might make the top lines.
            score = -this.negamax(depth - 1, -floor - 1, -floor, 1, true);
            if (score > floor) score = -this.negamax(depth - 1, -INF, -floor, 1, true);
          }
          this.pos.unmake(move);
          const pv = [move, ...Array.from(this.pvTable[1].subarray(1, this.pvLength[1]))];
          scored.push({ move, score, exact: score > floor, pv });
        }
      } catch (error) {
        if (error instanceof OutOfTime) break;
        throw error;
      }

      scored.sort((a, b) => (a.exact === b.exact ? b.score - a.score : a.exact ? -1 : 1));
      roots = scored.map((s) => s.move);
      pvs = new Map(scored.map((s) => [s.move, s.pv]));
      best = {
        depth,
        nodes: this.nodes,
        lines: scored.slice(0, multiPv).map((s) => ({
          uci: moveToUci(s.move),
          score: s.score,
          mate: mateIn(s.score),
          pv: s.pv.map(moveToUci),
        })),
      };
      this.options.onDepth?.(best);
      if (Math.abs(best.lines[0].score) > MATE_BOUND && depth >= 4) break;
      // The next depth costs several times this one: not worth starting if it cannot finish.
      if (this.now() - start > this.options.timeMs * 0.45) break;
    }
    return best;
  }

  private tick() {
    if ((++this.nodes & 1023) === 0 && this.timed && this.now() > this.deadline) throw new OutOfTime();
  }

  private negamax(depth: number, alpha: number, beta: number, ply: number, allowNull: boolean): number {
    this.tick();
    this.pvLength[ply] = ply;
    const pos = this.pos;
    if (pos.halfmove >= 100 || pos.repeated() || insufficientMaterial(pos)) return 0;
    if (ply >= MAX_PLY - 1) return evaluate(pos);

    const inCheck = pos.inCheck();
    if (inCheck) depth++;
    if (depth <= 0) return this.quiesce(alpha, beta, ply);

    const slot = pos.keyLo & (TT_SIZE - 1);
    const hit = ttFlag[slot] !== 0 && ttLo[slot] === pos.keyLo && ttHi[slot] === pos.keyHi;
    const hashMove = hit ? ttMove[slot] : 0;
    // Only off the main line: taking a stored score there would cut its variation short.
    if (hit && beta - alpha === 1 && ttDepth[slot] >= depth) {
      const stored = fromTT(ttScore[slot], ply);
      const flag = ttFlag[slot];
      if (flag === EXACT || (flag === LOWER && stored >= beta) || (flag === UPPER && stored <= alpha)) return stored;
    }
    const alphaAtStart = alpha;

    if (allowNull && !inCheck && depth >= 3 && beta < MATE_BOUND && pos.hasPieces(pos.side) && evaluate(pos) >= beta) {
      pos.makeNull();
      const score = -this.negamax(depth - 3, -beta, -beta + 1, ply + 1, false);
      pos.unmakeNull();
      if (score >= beta) return score;
    }

    const moves = this.order(pos.pseudoMoves(), ply, hashMove);
    let legal = 0;
    let best = -INF;
    let bestMove = 0;
    for (const move of moves) {
      if (!pos.make(move)) continue;
      legal++;
      const quiet = !(flagsOf(move) & CAPTURE) && !promoOf(move);
      let score: number;
      if (legal === 1) {
        score = -this.negamax(depth - 1, -beta, -alpha, ply + 1, true);
      } else {
        // Late quiet moves rarely matter: look at them a little shallower first.
        const reduce = depth >= 3 && legal > 4 && quiet && !inCheck && !pos.inCheck() ? 1 : 0;
        score = -this.negamax(depth - 1 - reduce, -alpha - 1, -alpha, ply + 1, true);
        if (score > alpha && (reduce || score < beta)) score = -this.negamax(depth - 1, -beta, -alpha, ply + 1, true);
      }
      pos.unmake(move);

      if (score > best) {
        best = score;
        bestMove = move;
      }
      if (score > alpha) {
        alpha = score;
        const row = this.pvTable[ply];
        row[ply] = move;
        const child = this.pvTable[ply + 1];
        for (let i = ply + 1; i < this.pvLength[ply + 1]; i++) row[i] = child[i];
        this.pvLength[ply] = Math.max(ply + 1, this.pvLength[ply + 1]);
        if (score >= beta) {
          if (quiet) {
            const k = this.killers[ply];
            if (k[0] !== move) {
              k[1] = k[0];
              k[0] = move;
            }
            this.history[fromOf(move) * 128 + toOf(move)] += depth * depth;
          }
          this.store(slot, depth, score, LOWER, move, ply);
          return score;
        }
      }
    }
    if (!legal) return inCheck ? -MATE + ply : 0;
    this.store(slot, depth, best, best > alphaAtStart ? EXACT : UPPER, bestMove, ply);
    return best;
  }

  private store(slot: number, depth: number, score: number, flag: number, move: number, ply: number) {
    const pos = this.pos;
    // Keep a deeper result for the same position over a shallower one.
    if (ttFlag[slot] && ttLo[slot] === pos.keyLo && ttHi[slot] === pos.keyHi && ttDepth[slot] > depth) return;
    ttLo[slot] = pos.keyLo;
    ttHi[slot] = pos.keyHi;
    ttMove[slot] = move;
    ttScore[slot] = toTT(score, ply);
    ttDepth[slot] = Math.min(depth, 127);
    ttFlag[slot] = flag;
  }

  private quiesce(alpha: number, beta: number, ply: number): number {
    this.tick();
    this.pvLength[ply] = ply;
    const pos = this.pos;
    const stand = evaluate(pos);
    if (stand >= beta || ply >= MAX_PLY - 1) return stand;
    if (stand > alpha) alpha = stand;
    let best = stand;
    for (const move of this.orderCaptures(pos.pseudoMoves(true))) {
      // Even winning the piece outright would not get back to alpha.
      const gain = PIECE_VALUE[pos.sq[toOf(move)] & 7] + (promoOf(move) ? 800 : 0);
      if (stand + gain + 200 < alpha && !promoOf(move)) continue;
      if (!pos.make(move)) continue;
      const score = -this.quiesce(-beta, -alpha, ply + 1);
      pos.unmake(move);
      if (score > best) best = score;
      if (score > alpha) {
        alpha = score;
        if (score >= beta) return score;
      }
    }
    return best;
  }

  /** Most valuable victim first, then least valuable attacker. */
  private captureScore(move: number): number {
    const sq = this.pos.sq;
    const victim = flagsOf(move) & CAPTURE ? PIECE_VALUE[sq[toOf(move)] & 7] || PIECE_VALUE[1] : 0;
    const attacker = PIECE_VALUE[sq[fromOf(move)] & 7];
    return victim * 10 - attacker / 100 + (promoOf(move) ? PIECE_VALUE[promoOf(move)] * 10 : 0);
  }

  private orderCaptures(moves: number[]): number[] {
    const keyed = moves.map((m) => ({ m, k: this.captureScore(m) }));
    keyed.sort((a, b) => b.k - a.k);
    return keyed.map((x) => x.m);
  }

  private order(moves: number[], ply: number, hashMove: number): number[] {
    let pvMove = 0;
    if (this.followPv) {
      this.followPv = false;
      const wanted = this.previousPv[ply];
      if (wanted && moves.includes(wanted)) {
        pvMove = wanted;
        this.followPv = true;
      }
    }
    const [k0, k1] = this.killers[ply];
    const keyed = moves.map((m) => {
      let k: number;
      if (m === pvMove) k = 2e9;
      else if (m === hashMove) k = 1e9;
      else if (flagsOf(m) & CAPTURE || promoOf(m)) k = 1e8 + this.captureScore(m);
      else if (m === k0) k = 9e7;
      else if (m === k1) k = 8e7;
      else k = this.history[fromOf(m) * 128 + toOf(m)];
      return { m, k };
    });
    keyed.sort((a, b) => b.k - a.k);
    return keyed.map((x) => x.m);
  }
}
