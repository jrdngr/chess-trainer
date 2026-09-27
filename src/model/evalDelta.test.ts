import { describe, expect, it } from 'vitest';
import { byDelta, deltaFor, deltaTone, formatDelta, whiteCp } from './evalDelta';

describe('what an answer does to the eval bar', () => {
  it('reads the change from the side playing the move', () => {
    // The bar at +0.4 for White; a move leaving it at +0.1.
    expect(deltaFor('w', 40, 10)).toBe(-30);
    // The same numbers for Black are a move that helps Black.
    expect(deltaFor('b', 40, 10)).toBe(30);
  });

  it('prints pawns, with near nothing as 0.0', () => {
    expect(formatDelta(-30)).toBe('−0.3');
    expect(formatDelta(125)).toBe('+1.3');
    expect(formatDelta(6)).toBe('0.0');
    expect(formatDelta(-4000)).toBe('−9.9');
    expect(deltaTone(-30)).toBe('bad');
    expect(deltaTone(30)).toBe('good');
    expect(deltaTone(-5)).toBe('even');
  });

  it('folds mates into a score past any position', () => {
    expect(whiteCp({ cp: null, mate: 3 })).toBeGreaterThan(9000);
    expect(whiteCp({ cp: null, mate: -2 })).toBeLessThan(-9000);
    // A quicker mate is worth more.
    expect(whiteCp({ cp: null, mate: 2 })!).toBeGreaterThan(whiteCp({ cp: null, mate: 5 })!);
    expect(whiteCp({ cp: 35, mate: null })).toBe(35);
    expect(whiteCp(undefined)).toBeNull();
  });
});

describe('the answers in the engine\'s order', () => {
  const moves = ['Ng5', 'Ne5', 'Ne3', 'g3', 'h3'].map((san) => ({ san }));
  const cps: Record<string, number | null> = { Ng5: -60, Ne5: -30, Ne3: -10, g3: -70, h3: null };
  it('puts the best delta on top and the unweighed last', () => {
    expect(byDelta(moves, (san) => cps[san]).map((m) => m.san)).toEqual(['Ne3', 'Ne5', 'Ng5', 'g3', 'h3']);
  });
  it('keeps the order it came in until the engine has weighed them', () => {
    expect(byDelta(moves, () => null).map((m) => m.san)).toEqual(['Ng5', 'Ne5', 'Ne3', 'g3', 'h3']);
  });
});
