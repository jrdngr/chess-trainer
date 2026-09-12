import { useEffect, useMemo, useRef, useState } from 'react';
import { applyUci } from '../chess/core';
import { createHeuristicEngine } from './heuristic';
import { createStockfishEngine } from './stockfish';
import type { Engine, EngineBackend, EngineLimits, EngineSnapshot } from './types';

let singleton: Engine | null = null;
let backendPromise: Promise<EngineBackend> | null = null;

/**
 * One engine per page. Tries real Stockfish first and falls back to the
 * heuristic evaluator if the worker cannot start (some sandboxes block it).
 */
export function getEngine(): { engine: Engine; backend: Promise<EngineBackend> } {
  if (!singleton) {
    const stockfish = createStockfishEngine();
    singleton = stockfish;
    backendPromise = stockfish.ready().then((ok) => {
      if (ok) return 'stockfish' as const;
      stockfish.dispose();
      singleton = createHeuristicEngine();
      return 'heuristic' as const;
    });
  }
  return { engine: singleton, backend: backendPromise! };
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
    return () => {
      cancelled = true;
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
