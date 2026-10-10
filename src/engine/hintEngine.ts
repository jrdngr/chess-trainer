import type { Color } from '../chess/core';
import { createHeuristicEngine } from './heuristic';
import { createStockfishEngine } from './stockfish';
import type { Engine, EngineLimits, EngineSnapshot } from './types';

/**
 * The hints' own engine, for the lenses and the cards.
 *
 * The page's engine is busy judging your moves and finding the opponent's,
 * and a search there stops whatever it was doing, so asking it for a hint
 * mid-game could leave a judgement waiting forever. A second worker costs
 * some memory and nothing else, and only starts the first time a hint asks.
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

/** One search at a time on the hints' engine, null when it never settles. */
export function hintSearch(fen: string, limits: EngineLimits): Promise<EngineSnapshot | null> {
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

/** A line's score from one side's point of view, mates as very large. */
export function lineScore(line: { cp: number | null; mate: number | null } | undefined, color: Color): number | null {
  if (!line) return null;
  const white = line.mate !== null ? Math.sign(line.mate) * 100000 : (line.cp ?? 0);
  return color === 'w' ? white : -white;
}
