import BasicWorker from './basic/basic.worker?worker&inline';
import { search, type DepthResult, type SearchOptions } from './basic/search';
import type { Engine, EngineLimits, EngineSnapshot } from './types';

/**
 * The backup engine, for when Stockfish has not started (yet).
 *
 * A small alpha-beta searcher of its own (see `basic/search.ts`), run in a
 * worker so a search never freezes the screen. Nowhere near Stockfish, but
 * it looks through every capture before it scores a position, so it no
 * longer counts a piece as won when it can simply be taken back.
 */

/** How long a search runs when the caller only names a depth. */
const DEFAULT_MS = 1000;
/** The longest any search runs: it rarely gets deeper for waiting, and callers give up on slow answers. */
const MAX_MS = 2000;
/** Without a worker the search blocks the page, so it gets much less time. */
const MAIN_THREAD_MS = 300;

function snapshotOf(fen: string, result: DepthResult | null, thinking: boolean): EngineSnapshot {
  // The search scores for the side to move; the app wants White's view.
  const sign = fen.split(' ')[1] === 'b' ? -1 : 1;
  return {
    lines: (result?.lines ?? []).map((line, i) => ({
      multipv: i + 1,
      depth: result!.depth,
      cp: line.mate === null ? sign * Math.max(-2000, Math.min(2000, line.score)) : null,
      mate: line.mate === null ? null : sign * line.mate,
      pv: line.pv,
    })),
    depth: result?.depth ?? 0,
    nodes: result?.nodes ?? 0,
    thinking,
    fen,
  };
}

function optionsOf(limits: EngineLimits): SearchOptions {
  return {
    maxDepth: limits.depth ?? 64,
    timeMs: Math.max(50, Math.min(limits.movetime ?? DEFAULT_MS, MAX_MS)),
    multiPv: limits.multiPv ?? 3,
    searchmoves: limits.searchmoves,
  };
}

interface Running {
  id: number;
  fen: string;
  options: SearchOptions;
  onUpdate: (snap: EngineSnapshot) => void;
}

export function createHeuristicEngine(): Engine {
  /** Undefined until first asked for; null where workers cannot start. */
  let worker: Worker | null | undefined;
  let running: Running | null = null;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let ids = 0;

  const onMessage = (event: MessageEvent<{ id: number; result: DepthResult | null; done: boolean }>) => {
    const { id, result, done } = event.data;
    if (!running || running.id !== id) return;
    const { fen, onUpdate } = running;
    if (done) running = null;
    onUpdate(snapshotOf(fen, result, !done));
  };

  const spawn = (): Worker | null => {
    if (typeof Worker === 'undefined') return null;
    try {
      const made = new BasicWorker();
      made.onmessage = onMessage;
      made.onerror = () => {
        // No worker after all (a page that blocks them): finish this search here.
        made.terminate();
        worker = null;
        if (running) here(running);
      };
      return made;
    } catch {
      return null;
    }
  };

  const here = (run: Running) => {
    timer = setTimeout(() => {
      if (running !== run) return;
      running = null;
      const result = search(run.fen, { ...run.options, timeMs: Math.min(run.options.timeMs, MAIN_THREAD_MS) });
      run.onUpdate(snapshotOf(run.fen, result, false));
    }, 20);
  };

  /** A search in a worker cannot be interrupted, only thrown away with its worker. */
  const halt = () => {
    if (timer) clearTimeout(timer);
    if (running && worker) {
      worker.terminate();
      worker = undefined;
    }
    running = null;
  };

  return {
    backend: 'heuristic',
    async ready() {
      return true;
    },
    analyse(fen, limits, onUpdate) {
      halt();
      const run: Running = { id: ++ids, fen, options: optionsOf(limits), onUpdate };
      running = run;
      onUpdate({ lines: [], depth: 0, nodes: 0, thinking: true, fen });
      if (worker === undefined) worker = spawn();
      if (worker) worker.postMessage({ id: run.id, fen, options: run.options });
      else here(run);
    },
    stop() {
      halt();
    },
    dispose() {
      halt();
      worker?.terminate();
      worker = undefined;
    },
  };
}
