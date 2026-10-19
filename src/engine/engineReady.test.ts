import { describe, expect, it } from 'vitest';
import type { Engine } from './types';
import { engineReady, getEngine } from './useEngine';

const FEN = 'r2qkb1r/pp2pppp/2n2n2/3p1b2/3P4/2N2NP1/PP2PPBP/R1BQK2R b KQkq - 2 7';

const finalLines = (engine: Engine) =>
  new Promise<number>((resolve) =>
    engine.analyse(FEN, { depth: 5, multiPv: 4 }, (snap) => {
      if (!snap.thinking) resolve(snap.lines.length);
    }),
  );

describe('engineReady', () => {
  it('hands over the engine that took Stockfish’s place when it cannot start', async () => {
    // No worker here, so Stockfish is disposed and the heuristic stands in.
    const stale = getEngine().engine;
    const engine = await engineReady();
    expect(stale.backend).toBe('stockfish');
    expect(engine.backend).toBe('heuristic');
    // The engine taken before waiting has nothing to say: the opponent froze on it.
    expect(await finalLines(stale)).toBe(0);
    expect(await finalLines(engine)).toBeGreaterThan(0);
  });
});
