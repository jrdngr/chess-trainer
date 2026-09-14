import { describe, expect, it } from 'vitest';
import { positionKey, START_FEN } from '../chess/core';
import { HORIZON, justRun, keysAlong, lineParts, lineStaleness, markSeen, NOTHING_SEEN, staleness } from './freshness';
import { addLine, createRepertoire, leafLines } from './repertoire';
import type { Repertoire } from './types';

const CLASSICAL = 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5';
const SAMISCH = 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f3 O-O Be3 e5';
const SICILIAN = 'e4 c5 Nf3 d6 d4 cxd4';

function rep(lines: string[]): Repertoire {
  let out = createRepertoire('Black', 'b', 'r_b');
  for (const line of lines) out = addLine(out, line.split(' '), 'reference').rep;
  return out;
}

function tipOf(r: Repertoire, line: string): string {
  return leafLines(r).find((l) => l.sans.join(' ') === line)!.tipId;
}

describe('remembering what was seen', () => {
  it('stamps every position a line reaches, but not the start', () => {
    const at = markSeen({}, ['e4', 'c5'], 4);
    expect(Object.keys(at)).toHaveLength(2);
    expect(at[positionKey(START_FEN)]).toBeUndefined();
    expect(keysAlong(['e4', 'c5'])).toHaveLength(2);
    // A later round overwrites, an unrelated one leaves alone.
    const later = markSeen(at, ['e4'], 5);
    expect(later[keysAlong(['e4'])[0]]).toBe(5);
    expect(later[keysAlong(['e4', 'c5'])[1]]).toBe(4);
  });

  it('reads a position as stale by how many rounds ago it was seen', () => {
    const seen = { at: markSeen({}, ['e4'], 3), round: 3 };
    const key = keysAlong(['e4'])[0];
    expect(staleness(seen, key)).toBe(0);
    expect(staleness({ ...seen, round: 4 }, key)).toBeCloseTo(1 / HORIZON, 5);
    expect(staleness({ ...seen, round: 3 + HORIZON }, key)).toBe(1);
    expect(staleness({ ...seen, round: 30 }, key)).toBe(1);
    expect(staleness(NOTHING_SEEN, key)).toBe(1);
  });
});

describe('a line in two parts', () => {
  it('splits where the line last parts from the rest of the prep', () => {
    const r = rep([CLASSICAL, SAMISCH]);
    const { head, tail } = lineParts(r, tipOf(r, CLASSICAL));
    // Eight shared plies, then Nf3 and what follows is Classical's own.
    expect(head).toHaveLength(8);
    expect(tail).toHaveLength(4);
  });

  it('is all tail when there is nothing to be a variation of', () => {
    const r = rep([CLASSICAL]);
    const { head, tail } = lineParts(r, tipOf(r, CLASSICAL));
    expect(head).toHaveLength(0);
    expect(tail).toHaveLength(12);
  });

  it('costs the same line most, a variation of it less, another opening nothing', () => {
    const r = rep([CLASSICAL, SAMISCH, SICILIAN]);
    const seen = { at: markSeen({}, CLASSICAL.split(' '), 1), round: 1 };
    const same = lineStaleness(seen, r, tipOf(r, CLASSICAL));
    const variation = lineStaleness(seen, r, tipOf(r, SAMISCH));
    const other = lineStaleness(seen, r, tipOf(r, SICILIAN));
    expect(same).toBe(0);
    expect(variation).toBeGreaterThan(same);
    expect(variation).toBeLessThan(other);
    expect(other).toBe(1);
  });

  it('knows which line the last round was drawn on', () => {
    const r = rep([CLASSICAL, SAMISCH]);
    const seen = { at: markSeen({}, CLASSICAL.split(' '), 2), round: 2 };
    expect(justRun(seen, r, tipOf(r, CLASSICAL))).toBe(true);
    expect(justRun(seen, r, tipOf(r, SAMISCH))).toBe(false);
    // A round later it was not the last round.
    expect(justRun({ ...seen, round: 3 }, r, tipOf(r, CLASSICAL))).toBe(false);
  });
});
