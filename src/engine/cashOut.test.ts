import { describe, expect, it } from 'vitest';
import { pickTrade } from './cashOut';
import type { EngineLine } from './types';

// White is a bishop up; Nxe6 fxe6 trades knights.
const fen = 'r5k1/5ppp/4n3/8/3N4/8/5PPP/R4BK1 w - - 0 1';
const line = (multipv: number, cp: number, pv: string[]): EngineLine => ({ multipv, depth: 12, cp, mate: null, pv });

describe('pickTrade', () => {
  it('offers a capture that is taken straight back when well ahead', () => {
    const lines = [line(1, 320, ['a1a7', 'a8a7']), line(2, 300, ['d4e6', 'f7e6'])];
    expect(pickTrade(fen, lines, 'w')).toEqual({ from: 'd4', to: 'e6', san: 'Nxe6' });
  });

  it('says nothing when the lead is small', () => {
    expect(pickTrade(fen, [line(1, 150, ['d4e6', 'f7e6'])], 'w')).toBeNull();
  });

  it('skips a trade that costs too much against the best move', () => {
    expect(pickTrade(fen, [line(1, 400, ['f1c4', 'a8a2']), line(2, 300, ['d4e6', 'f7e6'])], 'w')).toBeNull();
  });

  it('skips a capture that is not taken back', () => {
    expect(pickTrade(fen, [line(1, 400, ['d4e6', 'g8h8'])], 'w')).toBeNull();
  });

  it('reads the lead from your side', () => {
    expect(pickTrade(fen, [line(1, 300, ['d4e6', 'f7e6'])], 'b')).toBeNull();
  });
});
