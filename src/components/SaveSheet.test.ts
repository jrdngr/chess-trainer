import { describe, expect, it } from 'vitest';
import { pawns, plyLabel, snippet } from './SaveSheet';

const LINE = 'e4 e5 Nf3 Nc6 Bc4 Bc5 d3 Nf6 Ng5'.split(' ');

describe('the Save sheet’s line text', () => {
  it('shortens a long part of the line to where it starts and ends', () => {
    expect(snippet(LINE, 0, 8)).toBe('1.e4 … 4.d3 Nf6');
    expect(snippet(LINE, 0, 9)).toBe('1.e4 … 5.Ng5');
  });

  it('writes a short part out in full, numbered from where it starts', () => {
    expect(snippet(LINE, 8, 9)).toBe('5.Ng5');
    expect(snippet(LINE, 7, 9)).toBe('4...Nf6 5.Ng5');
    expect(plyLabel(LINE, 7)).toBe('4...Nf6');
  });

  it('gives evals in pawns from the side saving the line', () => {
    expect(pawns(-60, 'w')).toBe('−0.6');
    expect(pawns(-60, 'b')).toBe('+0.6');
    expect(pawns(9990, 'w')).toBe('Mate');
  });
});
