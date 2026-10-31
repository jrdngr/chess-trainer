import { search } from './basic/search';
import { snapshotOf } from './heuristic';
import type { EngineSnapshot } from './types';
import type { StockfishEngine } from './stockfish';

/**
 * Browser tests set `__CHESS_TEST__ = { engineDepth }` before the page loads.
 * Every engine the page makes is then the backup engine searching to that
 * fixed depth on the main thread, with no clock: the same position always
 * gets the same answer, so a scripted run replays exactly. Never set in use.
 */
export function testEngineDepth(): number | null {
  const test = (globalThis as { __CHESS_TEST__?: { engineDepth?: unknown } }).__CHESS_TEST__;
  return typeof test?.engineDepth === 'number' ? test.engineDepth : null;
}

export function createTestEngine(depth: number): StockfishEngine {
  let timer: ReturnType<typeof setTimeout> | undefined;
  return {
    backend: 'heuristic',
    async ready() {
      return true;
    },
    async loaded() {
      return true;
    },
    analyse(fen, limits, onUpdate: (snap: EngineSnapshot) => void) {
      if (timer) clearTimeout(timer);
      timer = setTimeout(() => {
        timer = undefined;
        const result = search(fen, {
          maxDepth: Math.min(limits.depth ?? depth, depth),
          timeMs: Number.MAX_SAFE_INTEGER,
          now: () => 0,
          multiPv: limits.multiPv ?? 3,
          searchmoves: limits.searchmoves,
        });
        onUpdate(snapshotOf(fen, result, false));
      }, 0);
    },
    stop() {
      if (timer) clearTimeout(timer);
      timer = undefined;
    },
    dispose() {
      if (timer) clearTimeout(timer);
    },
  };
}
