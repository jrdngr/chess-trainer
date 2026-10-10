import { useEffect, useState } from 'react';
import type { Color, Square } from '../chess/core';
import { asMover, breakCandidates } from '../model/boardHints';
import { hintSearch, lineScore } from './hintEngine';
import type { EngineSnapshot } from './types';

/**
 * Each side's best pawn break, for the Pawns lens, asked on the hints' own
 * engine so a held lens never interrupts the game.
 */

const THINK_MS = 300;

/** How much worse than the best move a break may be and still be drawn. */
export const BREAK_SLACK = 150;

const scoreFor = (snap: EngineSnapshot | null, color: Color) => lineScore(snap?.lines[0], color);

export type Breaks = Partial<Record<Color, { from: Square; to: Square }>>;

async function bestBreak(fen: string, color: Color): Promise<{ from: Square; to: Square } | null> {
  const mover = asMover(fen, color);
  if (!mover) return null;
  const candidates = breakCandidates(mover, color);
  if (!candidates.length) return null;
  const all = await hintSearch(mover, { movetime: THINK_MS, multiPv: 1 });
  const only = await hintSearch(mover, { movetime: THINK_MS, multiPv: 1, searchmoves: candidates });
  const best = scoreFor(all, color);
  const brk = scoreFor(only, color);
  const uci = only?.lines[0]?.pv[0];
  if (best === null || brk === null || !uci || !candidates.includes(uci)) return null;
  if (best - brk > BREAK_SLACK) return null;
  return { from: uci.slice(0, 2) as Square, to: uci.slice(2, 4) as Square };
}

const cache = new Map<string, Promise<Breaks>>();

export function pawnBreaks(fen: string): Promise<Breaks> {
  const key = fen.split(' ').slice(0, 2).join(' ');
  let found = cache.get(key);
  if (!found) {
    found = (async () => {
      const w = await bestBreak(fen, 'w');
      const b = await bestBreak(fen, 'b');
      return { ...(w ? { w } : {}), ...(b ? { b } : {}) };
    })();
    cache.set(key, found);
    if (cache.size > 200) cache.delete(cache.keys().next().value!);
  }
  return found;
}

/** The breaks for a position, once they are known; nothing is asked until `enabled`. */
export function usePawnBreaks(fen: string, enabled: boolean): Breaks | null {
  const [state, setState] = useState<{ fen: string; breaks: Breaks } | null>(null);
  useEffect(() => {
    if (!enabled) return;
    let live = true;
    void pawnBreaks(fen).then((breaks) => {
      if (live) setState({ fen, breaks });
    });
    return () => {
      live = false;
    };
  }, [fen, enabled]);
  return state && state.fen === fen ? state.breaks : null;
}
