import { useEffect, useState } from 'react';
import { legalMoves, PIECE_VALUES, type Color, type Square } from '../chess/core';
import { hintSearch, lineScore } from './hintEngine';
import type { EngineLine } from './types';

/**
 * Cash out: when you are well ahead, a trade that keeps the lead.
 *
 * Every trade takes the other side's counterplay with it, so the side that is
 * ahead wants pieces off. The card looks at the engine's best few moves for a
 * capture of a piece that is taken straight back, near enough in value to be a
 * trade, and costing next to nothing against the best move.
 */

/** How far ahead, in centipawns from your side, before trades are suggested. */
export const CASH_OUT_FROM = 200;
/** How much worse than the best move a trade may be. */
export const CASH_OUT_SLACK = 30;

export interface Trade {
  from: Square;
  to: Square;
  san: string;
}

/** The trade worth offering among the engine's lines, if any. */
export function pickTrade(fen: string, lines: EngineLine[], me: Color): Trade | null {
  const best = lineScore(lines[0], me);
  if (best === null || best < CASH_OUT_FROM) return null;
  const moves = legalMoves(fen);
  for (const line of lines) {
    const score = lineScore(line, me);
    if (score === null || best - score > CASH_OUT_SLACK || score < CASH_OUT_FROM) continue;
    const move = moves.find((m) => m.uci === line.pv[0]);
    if (!move?.captured || move.captured === 'p' || move.piece === 'k') continue;
    // Taken straight back, by a piece of about the same worth: a trade, not a win of material.
    if (line.pv[1]?.slice(2, 4) !== move.to) continue;
    if (Math.abs(PIECE_VALUES[move.captured] - PIECE_VALUES[move.piece]) > 1) continue;
    return { from: move.from, to: move.to, san: move.san };
  }
  return null;
}

const cache = new Map<string, Promise<Trade | null>>();

export function cashOut(fen: string, me: Color): Promise<Trade | null> {
  const key = `${fen.split(' ').slice(0, 2).join(' ')}|${me}`;
  let found = cache.get(key);
  if (!found) {
    found = hintSearch(fen, { movetime: 600, multiPv: 4 }).then((snap) =>
      snap ? pickTrade(fen, snap.lines, me) : null,
    );
    cache.set(key, found);
    if (cache.size > 200) cache.delete(cache.keys().next().value!);
  }
  return found;
}

/** The trade to offer here, once known; nothing is asked until `enabled`. */
export function useCashOut(fen: string, me: Color, enabled: boolean): Trade | null {
  const [state, setState] = useState<{ fen: string; trade: Trade | null } | null>(null);
  useEffect(() => {
    if (!enabled) return;
    let live = true;
    void cashOut(fen, me).then((trade) => {
      if (live) setState({ fen, trade });
    });
    return () => {
      live = false;
    };
  }, [fen, me, enabled]);
  return enabled && state && state.fen === fen ? state.trade : null;
}
