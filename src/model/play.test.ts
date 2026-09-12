import { describe, expect, it } from 'vitest';
import { chooseMove, levelById, LEVELS, openingLine } from './play';
import { mulberry32 } from './session';
import type { EngineLine } from '../engine/types';

function line(multipv: number, first: string): EngineLine {
  return { multipv, depth: 10, cp: 0, mate: null, pv: [first, 'e7e5'] };
}

const CANDIDATES = [line(1, 'e2e4'), line(2, 'd2d4'), line(3, 'g1f3'), line(4, 'c2c4')];

describe('levels', () => {
  it('gets harder all the way down the list', () => {
    for (let i = 1; i < LEVELS.length; i += 1) {
      expect(LEVELS[i].depth).toBeGreaterThan(LEVELS[i - 1].depth);
      expect(LEVELS[i].slip).toBeLessThan(LEVELS[i - 1].slip);
    }
  });

  it('falls back to a middling level for an unknown id', () => {
    expect(levelById('nonsense').id).toBe('club');
    expect(levelById('full').id).toBe('full');
  });

  it('never handicaps the top level', () => {
    expect(LEVELS[LEVELS.length - 1].slip).toBe(0);
  });
});

describe('choosing a move', () => {
  it('always takes the best line when it cannot slip', () => {
    const level = { ...levelById('club'), slip: 0 };
    for (let seed = 1; seed < 20; seed += 1) {
      expect(chooseMove(CANDIDATES, level, mulberry32(seed))).toBe('e2e4');
    }
  });

  it('returns null when there is nothing to play', () => {
    expect(chooseMove([], levelById('club'), Math.random)).toBeNull();
    expect(
      chooseMove([{ multipv: 1, depth: 1, cp: 0, mate: null, pv: [] }], levelById('club'), Math.random),
    ).toBeNull();
  });

  it('takes the only move on offer however weak it is', () => {
    const weak = levelById('casual');
    expect(chooseMove([line(1, 'a2a3')], weak, mulberry32(3))).toBe('a2a3');
  });

  it('plays the best move most of the time even at the weakest level', () => {
    const weak = levelById('casual');
    let best = 0;
    const runs = 400;
    for (let seed = 0; seed < runs; seed += 1) {
      if (chooseMove(CANDIDATES, weak, mulberry32(seed)) === 'e2e4') best += 1;
    }
    // Weights are 0.35 for the best and 0.325/0.1625/0.08 for the rest, so the
    // best move is still the single most likely — it just is not a certainty.
    expect(best / runs).toBeGreaterThan(0.2);
    expect(best / runs).toBeLessThan(0.6);
  });

  it('slips less as the level rises', () => {
    const rate = (id: string) => {
      let best = 0;
      for (let seed = 0; seed < 400; seed += 1) {
        if (chooseMove(CANDIDATES, levelById(id), mulberry32(seed)) === 'e2e4') best += 1;
      }
      return best / 400;
    };
    expect(rate('strong')).toBeGreaterThan(rate('club'));
    expect(rate('club')).toBeGreaterThan(rate('casual'));
  });

  it('ignores the order the engine reported lines in', () => {
    const shuffled = [CANDIDATES[2], CANDIDATES[0], CANDIDATES[3], CANDIDATES[1]];
    const level = { ...levelById('club'), slip: 0 };
    expect(chooseMove(shuffled, level, mulberry32(1))).toBe('e2e4');
  });
});

describe('keeping the opening', () => {
  const moves = ['e4', 'c5', 'Nf3', 'd6', 'd4', 'cxd4', 'Nxd4', 'Nf6', 'Nc3', 'a6'];

  it('ends a White line on a White move', () => {
    const line = openingLine(moves, 'w', 6);
    expect(line).toEqual(['e4', 'c5', 'Nf3', 'd6', 'd4']);
  });

  it('ends a Black line on a Black move', () => {
    const line = openingLine(moves, 'b', 5);
    expect(line).toEqual(['e4', 'c5', 'Nf3', 'd6']);
  });

  it('keeps the whole game when it is shorter than the cut', () => {
    expect(openingLine(['e4', 'e5', 'Nf3'], 'w', 16)).toEqual(['e4', 'e5', 'Nf3']);
  });

  it('gives back nothing for a game with no moves', () => {
    expect(openingLine([], 'w')).toEqual([]);
    expect(openingLine([], 'b')).toEqual([]);
  });

  it('drops a lone White move when Black is the one saving it', () => {
    expect(openingLine(['e4'], 'b')).toEqual([]);
  });
});
