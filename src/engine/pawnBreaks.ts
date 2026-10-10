import { useEffect, useState } from 'react';
import type { Color, Square } from '../chess/core';
import { asMover, breakCandidates } from '../model/boardHints';
import { createHeuristicEngine } from './heuristic';
import { createStockfishEngine } from './stockfish';
import type { Engine, EngineLimits, EngineSnapshot } from './types';

/**
 * Each side's best pawn break, for the Pawns lens.
 *
 * The lens asks on its own engine. The page's engine is busy judging your
 * moves and finding the opponent's, and a search there stops whatever it was
 * doing, so holding a lens mid-game could leave a judgement waiting forever.
 * A second worker costs some memory and nothing else, and only starts the
 * first time the Pawns lens is held.
 */

let hint: { engine: Engine; ready: Promise<void> } | null = null;

function hintEngine() {
  if (!hint) {
    const stockfish = createStockfishEngine();
    const made: { engine: Engine; ready: Promise<void> } = { engine: stockfish, ready: Promise.resolve() };
    made.ready = stockfish.ready().then((ok) => {
      if (ok) return;
      stockfish.dispose();
      made.engine = createHeuristicEngine();
    });
    hint = made;
  }
  return hint;
}

let tail: Promise<unknown> = Promise.resolve();

/** One search at a time on the lens's engine, null when it never settles. */
function search(fen: string, limits: EngineLimits): Promise<EngineSnapshot | null> {
  const run = tail.then(
    () =>
      new Promise<EngineSnapshot | null>((resolve) => {
        const h = hintEngine();
        void h.ready.then(() => {
          let done = false;
          h.engine.analyse(fen, limits, (snap) => {
            if (done || snap.thinking || snap.fen !== fen) return;
            done = true;
            resolve(snap);
          });
          setTimeout(() => {
            if (done) return;
            done = true;
            h.engine.stop();
            resolve(null);
          }, 2500);
        });
      }),
  );
  tail = run.catch(() => null);
  return run;
}

const THINK_MS = 300;

/** How much worse than the best move a break may be and still be drawn. */
export const BREAK_SLACK = 150;

/** A score from one side's point of view, mates as very large. */
function scoreFor(snap: EngineSnapshot | null, color: Color): number | null {
  const line = snap?.lines[0];
  if (!line) return null;
  const white = line.mate !== null ? Math.sign(line.mate) * 100000 : (line.cp ?? 0);
  return color === 'w' ? white : -white;
}

export type Breaks = Partial<Record<Color, { from: Square; to: Square }>>;

async function bestBreak(fen: string, color: Color): Promise<{ from: Square; to: Square } | null> {
  const mover = asMover(fen, color);
  if (!mover) return null;
  const candidates = breakCandidates(mover, color);
  if (!candidates.length) return null;
  const all = await search(mover, { movetime: THINK_MS, multiPv: 1 });
  const only = await search(mover, { movetime: THINK_MS, multiPv: 1, searchmoves: candidates });
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
