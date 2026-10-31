import type { EngineLimits, EngineSnapshot } from './types';
import { getEngine } from './useEngine';

/**
 * One background search at a time.
 *
 * There is one engine per page, and starting a search stops whatever it was
 * doing. Questions asked in the background — is this off-book move sound,
 * what would the engine play past the book — wait their turn here rather than
 * cutting each other off, which left the one cut off waiting for an answer
 * that was never coming.
 */

let tail: Promise<unknown> = Promise.resolve();

/**
 * Search a position, resolved with the settled snapshot, or null when the
 * engine never settles (none at all, or it stalled).
 */
export function queueSearch(fen: string, limits: EngineLimits, giveUpMs: number): Promise<EngineSnapshot | null> {
  const run = tail.then(
    () =>
      new Promise<EngineSnapshot | null>((resolve) => {
        const { backend } = getEngine();
        void backend.then(() => {
          const engine = getEngine().engine;
          let done = false;
          engine.analyse(fen, limits, (snap) => {
            if (done || snap.thinking || snap.fen !== fen) return;
            done = true;
            resolve(snap);
          });
          setTimeout(() => {
            if (done) return;
            done = true;
            engine.stop();
            resolve(null);
          }, giveUpMs);
        });
      }),
  );
  tail = run.catch(() => null);
  return run;
}
