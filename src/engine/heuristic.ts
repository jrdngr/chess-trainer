import { legalMoves, positionStatus, type PieceType } from '../chess/core';
import { Chess } from 'chess.js';
import type { Engine, EngineLimits } from './types';

/**
 * A tiny deterministic evaluator used when the real engine cannot start.
 * It is not a serious engine — it exists so every analysis surface still has
 * something to show rather than an empty panel.
 */
const VALUE: Record<PieceType, number> = { p: 100, n: 320, b: 330, r: 500, q: 900, k: 0 };

const PAWN_ADVANCE = [0, 5, 10, 20, 35, 60, 90, 0];
const CENTRE = [0.0, 0.3, 0.6, 1.0, 1.0, 0.6, 0.3, 0.0];

function evaluate(fen: string): number {
  const chess = new Chess(fen);
  let score = 0;
  for (const row of chess.board()) {
    for (const sq of row) {
      if (!sq) continue;
      const type = sq.type as PieceType;
      const file = sq.square.charCodeAt(0) - 97;
      const rank = Number(sq.square[1]) - 1;
      let value = VALUE[type];
      if (type === 'p') value += PAWN_ADVANCE[sq.color === 'w' ? rank : 7 - rank];
      if (type === 'n' || type === 'b') value += CENTRE[file] * CENTRE[rank] * 22;
      score += sq.color === 'w' ? value : -value;
    }
  }
  const status = positionStatus(fen);
  if (status.checkmate) return chess.turn() === 'w' ? -100000 : 100000;
  if (status.draw || status.stalemate) return 0;
  return score;
}

function negamax(fen: string, depth: number, alpha: number, beta: number): number {
  if (depth === 0) return evaluate(fen);
  const moves = legalMoves(fen);
  if (!moves.length) return evaluate(fen);
  const white = fen.split(' ')[1] === 'w';
  let best = white ? -Infinity : Infinity;
  // Captures first for a little pruning benefit.
  moves.sort((a, b) => (b.captured ? 1 : 0) - (a.captured ? 1 : 0));
  for (const move of moves) {
    const score = negamax(move.after, depth - 1, alpha, beta);
    if (white) {
      best = Math.max(best, score);
      alpha = Math.max(alpha, score);
    } else {
      best = Math.min(best, score);
      beta = Math.min(beta, score);
    }
    if (beta <= alpha) break;
  }
  return best;
}

export function createHeuristicEngine(): Engine {
  let timer: ReturnType<typeof setTimeout> | undefined;
  return {
    backend: 'heuristic',
    async ready() {
      return true;
    },
    analyse(fen, limits: EngineLimits, onUpdate) {
      if (timer) clearTimeout(timer);
      const multiPv = limits.multiPv ?? 3;
      onUpdate({ lines: [], depth: 0, nodes: 0, thinking: true, fen });
      timer = setTimeout(() => {
        const only = limits.searchmoves?.length ? new Set(limits.searchmoves) : null;
        const scored = legalMoves(fen)
          .filter((move) => !only || only.has(move.uci))
          .map((move) => ({ move, score: negamax(move.after, 2, -Infinity, Infinity) }))
          .sort((a, b) => (fen.split(' ')[1] === 'w' ? b.score - a.score : a.score - b.score))
          .slice(0, multiPv);
        onUpdate({
          lines: scored.map((s, i) => ({
            multipv: i + 1,
            depth: 3,
            cp: Math.max(-2000, Math.min(2000, Math.round(s.score))),
            mate: null,
            pv: [s.move.uci],
          })),
          depth: 3,
          nodes: 0,
          thinking: false,
          fen,
        });
      }, 20);
    },
    stop() {
      if (timer) clearTimeout(timer);
    },
    dispose() {
      if (timer) clearTimeout(timer);
    },
  };
}

