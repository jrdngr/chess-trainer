import { useEffect, useMemo, useRef, useState } from 'react';
import { applyUci } from '../chess/core';
import { createHeuristicEngine } from './heuristic';
import { createStockfishEngine } from './stockfish';
import type { Engine, EngineBackend, EngineLimits, EngineSnapshot } from './types';

let singleton: Engine | null = null;
let backendPromise: Promise<EngineBackend> | null = null;
const switched = new Set<(backend: EngineBackend) => void>();

/**
 * One engine per page. Tries real Stockfish first and falls back to the
 * heuristic evaluator if the worker cannot start (some sandboxes block it).
 * When Stockfish was only slow, it takes over the moment it answers.
 */
export function getEngine(): { engine: Engine; backend: Promise<EngineBackend> } {
  if (!singleton) {
    const stockfish = createStockfishEngine();
    singleton = stockfish;
    backendPromise = stockfish.ready().then((ok) => {
      if (ok) return 'stockfish' as const;
      // The backup is never disposed: a search already handed to it must still answer.
      singleton = createHeuristicEngine();
      void stockfish.loaded().then((late) => {
        if (!late) {
          stockfish.dispose();
          return;
        }
        singleton = stockfish;
        backendPromise = Promise.resolve('stockfish');
        for (const listener of switched) listener('stockfish');
      });
      return 'heuristic' as const;
    });
  }
  return { engine: singleton, backend: backendPromise! };
}

/** Called when the page's engine changes after it first settled. */
export function onEngineSwitch(listener: (backend: EngineBackend) => void): () => void {
  switched.add(listener);
  return () => switched.delete(listener);
}

/**
 * The page's engine once it has settled on a backend.
 *
 * Take the engine from here, not from `getEngine()` before waiting: when
 * Stockfish cannot start in time it is disposed and the heuristic takes its
 * place, and a search handed to the disposed one answers with nothing at all.
 */
export function engineReady(): Promise<Engine> {
  return getEngine().backend.then(() => getEngine().engine);
}

const EMPTY: EngineSnapshot = { lines: [], depth: 0, nodes: 0, thinking: false, fen: null };

export interface UseEngineOptions extends EngineLimits {
  enabled: boolean;
  /** Delay before starting a search, so scrubbing moves does not thrash it. */
  debounceMs?: number;
}

export function useEngine(fen: string | null, opts: UseEngineOptions) {
  const { enabled, debounceMs = 220, depth = 14, multiPv = 3, movetime } = opts;
  const [snapshot, setSnapshot] = useState<EngineSnapshot>(EMPTY);
  const [backend, setBackend] = useState<EngineBackend | null>(null);
  const engineRef = useRef<Engine | null>(null);

  useEffect(() => {
    if (!enabled) return;
    const { engine, backend: ready } = getEngine();
    engineRef.current = engine;
    let cancelled = false;
    void ready.then((b) => {
      if (!cancelled) {
        setBackend(b);
        engineRef.current = getEngine().engine;
      }
    });
    const unsubscribe = onEngineSwitch((b) => {
      if (cancelled) return;
      engineRef.current = getEngine().engine;
      setBackend(b);
    });
    return () => {
      cancelled = true;
      unsubscribe();
    };
  }, [enabled]);

  useEffect(() => {
    if (!enabled || !fen || !backend) {
      setSnapshot(EMPTY);
      return;
    }
    const engine = engineRef.current;
    if (!engine) return;
    const timer = setTimeout(() => {
      engine.analyse(fen, { depth, multiPv, movetime }, (snap) => setSnapshot(snap));
    }, debounceMs);
    return () => {
      clearTimeout(timer);
      engine.stop();
    };
  }, [enabled, fen, backend, depth, multiPv, movetime, debounceMs]);

  /** PVs converted to SAN for display. */
  const sanLines = useMemo(() => {
    if (!snapshot.fen) return [];
    return snapshot.lines.map((line) => {
      const sans: string[] = [];
      let cursor = snapshot.fen!;
      // Long enough for a caller to show several moves a side and slice it down.
      for (const uci of line.pv.slice(0, 24)) {
        const move = applyUci(cursor, uci);
        if (!move) break;
        sans.push(move.san);
        cursor = move.after;
      }
      return { ...line, sans };
    });
  }, [snapshot]);

  return { snapshot, sanLines, backend };
}
