import { describe, expect, it } from 'vitest';
import { Chess } from 'chess.js';
import { OPENING_PATHS, OPENING_NAMES } from './openingPaths';

describe('seed validation', () => {
  it('every path is legal', () => {
    const bad: string[] = [];
    for (const path of OPENING_PATHS) {
      const c = new Chess();
      const tokens = path.trim().split(/\s+/);
      for (const t of tokens) {
        const san = t.split(':')[0];
        try { c.move(san); } catch { bad.push(`${san} in: ${path.slice(0, 90)}`); break; }
      }
    }
    expect(bad).toEqual([]);
  });
  it('every opening name prefix is legal', () => {
    const bad: string[] = [];
    for (const line of Object.keys(OPENING_NAMES)) {
      const c = new Chess();
      for (const san of line.split(/\s+/)) {
        try { c.move(san); } catch { bad.push(`${san} in: ${line}`); break; }
      }
    }
    expect(bad).toEqual([]);
  });
});
