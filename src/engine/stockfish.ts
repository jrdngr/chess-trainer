import type { Engine, EngineLimits, EngineLine, EngineSnapshot } from './types';

/**
 * Real Stockfish, running in a Web Worker.
 *
 * The bundled build is the asm.js one: it is a single self-contained script
 * with no WebAssembly and no runtime fetches, which is what makes it usable
 * inside sandboxes that block network requests. If the worker cannot start,
 * `ready()` resolves false and the caller falls back to the heuristic engine.
 */
const ENGINE_URL = `${import.meta.env.BASE_URL}engine/stockfish.js`;

interface Pending {
  fen: string;
  onUpdate: (snap: EngineSnapshot) => void;
  limits: EngineLimits;
}

export function createStockfishEngine(): Engine {
  let worker: Worker | null = null;
  let readyPromise: Promise<boolean> | null = null;
  let current: Pending | null = null;
  let lines = new Map<number, EngineLine>();
  let depth = 0;
  let nodes = 0;
  let searching = false;
  let queued: Pending | null = null;

  const emit = (thinking: boolean) => {
    if (!current) return;
    current.onUpdate({
      lines: [...lines.values()].sort((a, b) => a.multipv - b.multipv),
      depth,
      nodes,
      thinking,
      fen: current.fen,
    });
  };

  const handleLine = (text: string) => {
    if (text.startsWith('info')) {
      if (!text.includes(' pv ')) return;
      const mpMatch = /multipv (\d+)/.exec(text);
      const dMatch = /depth (\d+)/.exec(text);
      const nMatch = /nodes (\d+)/.exec(text);
      const cpMatch = /score cp (-?\d+)/.exec(text);
      const mateMatch = /score mate (-?\d+)/.exec(text);
      const pvMatch = / pv (.+)$/.exec(text);
      if (!pvMatch) return;
      const multipv = mpMatch ? Number(mpMatch[1]) : 1;
      const d = dMatch ? Number(dMatch[1]) : 0;
      if (dMatch) depth = Math.max(depth, d);
      if (nMatch) nodes = Number(nMatch[1]);
      // Stockfish reports from the side to move; normalise to White's view.
      const whiteToMove = current?.fen.split(' ')[1] !== 'b';
      const sign = whiteToMove ? 1 : -1;
      lines.set(multipv, {
        multipv,
        depth: d,
        cp: cpMatch ? sign * Number(cpMatch[1]) : null,
        mate: mateMatch ? sign * Number(mateMatch[1]) : null,
        pv: pvMatch[1].trim().split(/\s+/),
      });
      emit(true);
    } else if (text.startsWith('bestmove')) {
      searching = false;
      emit(false);
      if (queued) {
        const next = queued;
        queued = null;
        start(next);
      }
    }
  };

  const start = (pending: Pending) => {
    if (!worker) return;
    current = pending;
    lines = new Map();
    depth = 0;
    nodes = 0;
    searching = true;
    const multiPv = pending.limits.multiPv ?? 3;
    worker.postMessage(`setoption name MultiPV value ${multiPv}`);
    worker.postMessage(`position fen ${pending.fen}`);
    if (pending.limits.movetime) worker.postMessage(`go movetime ${pending.limits.movetime}`);
    else worker.postMessage(`go depth ${pending.limits.depth ?? 14}`);
    emit(true);
  };

  return {
    backend: 'stockfish',

    ready() {
      if (readyPromise) return readyPromise;
      readyPromise = new Promise<boolean>((resolve) => {
        let settled = false;
        const finish = (ok: boolean) => {
          if (settled) return;
          settled = true;
          resolve(ok);
        };
        try {
          worker = new Worker(ENGINE_URL);
        } catch {
          finish(false);
          return;
        }
        worker.onerror = () => finish(false);
        worker.onmessage = (event: MessageEvent) => {
          const text = typeof event.data === 'string' ? event.data : String(event.data ?? '');
          if (text.includes('uciok')) {
            // Note: do not touch the Threads option. This build is compiled
            // single-threaded (min = max = 1) and setting it wedges the engine
            // before it ever answers isready.
            worker?.postMessage('setoption name Hash value 16');
            worker?.postMessage('isready');
          } else if (text.includes('readyok')) {
            finish(true);
          } else {
            handleLine(text);
          }
        };
        worker.postMessage('uci');
        // asm.js Stockfish takes a moment to compile; be patient but bounded.
        setTimeout(() => finish(false), 12_000);
      });
      return readyPromise;
    },

    analyse(fen, limits, onUpdate) {
      const pending: Pending = { fen, limits, onUpdate };
      if (!worker) {
        onUpdate({ lines: [], depth: 0, nodes: 0, thinking: false, fen });
        return;
      }
      if (searching) {
        queued = pending;
        worker.postMessage('stop');
      } else {
        start(pending);
      }
    },

    stop() {
      queued = null;
      worker?.postMessage('stop');
    },

    dispose() {
      worker?.terminate();
      worker = null;
      readyPromise = null;
    },
  };
}
