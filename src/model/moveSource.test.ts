import { describe, expect, it } from 'vitest';
import { growthSource, normalizeSources, sourceLabel, SOURCE_LABELS } from './moveSource';
import { MAX_LIFTED, PREPARED_FLOOR, withFloor } from './prepFloor';
import { referenceIndex } from './referenceIndex';
import { addLine, createRepertoire, nodeAtLine } from './repertoire';
import type { MoveSource, Repertoire } from './types';

const index = referenceIndex();
const KID = ['d4', 'Nf6', 'c4', 'g6', 'Nc3', 'Bg7', 'e4', 'd6'];

describe('source labels', () => {
  it('names every source', () => {
    expect(Object.keys(SOURCE_LABELS)).toHaveLength(11);
    expect(sourceLabel('manual')).toBe('Entered by hand');
    expect(sourceLabel('import')).toBe('Imported games');
    expect(sourceLabel('board')).toBe('Play on the board');
  });

  it("labels Growth's moves by whether the book has them", () => {
    const rep = addLine(createRepertoire('B', 'b', 'r_g'), [...KID, 'e5'], growthSource(index)).rep;
    expect(nodeAtLine(rep, KID)!.source).toBe('growth');
    expect(nodeAtLine(rep, [...KID, 'e5'])!.source).toBe('engine');
  });
});

describe('upgrading saved sources', () => {
  function legacy(line: string[], source: string): Repertoire {
    return addLine(createRepertoire('B', 'b', 'r_old'), line, source as MoveSource).rep;
  }

  it('reads the old reference as Book, or Engine where the book lacks the move', () => {
    const reps = normalizeSources({ r_old: legacy([...KID, 'e5'], 'reference') }, index, false);
    expect(nodeAtLine(reps.r_old, KID)!.source).toBe('book');
    expect(nodeAtLine(reps.r_old, [...KID, 'e5'])!.source).toBe('engine');
  });

  it('reads pgn as Analysis and games by whether anything was imported', () => {
    expect(nodeAtLine(normalizeSources({ r_old: legacy(['d4'], 'pgn') }, index, false).r_old, ['d4'])!.source).toBe(
      'analysis',
    );
    expect(nodeAtLine(normalizeSources({ r_old: legacy(['d4'], 'games') }, index, true).r_old, ['d4'])!.source).toBe(
      'import',
    );
    expect(nodeAtLine(normalizeSources({ r_old: legacy(['d4'], 'games') }, index, false).r_old, ['d4'])!.source).toBe(
      'play',
    );
  });

  it('leaves current labels alone', () => {
    const reps = { r_old: legacy(KID, 'manual') };
    expect(normalizeSources(reps, index, false)).toBe(reps);
  });
});

describe('the floor for prepared replies', () => {
  it('lifts a rare prepared move to the floor and scales the rest', () => {
    const shares = withFloor([990, 10, 0], [true, false, true]);
    expect(shares[2]).toBeCloseTo(PREPARED_FLOOR, 9);
    expect(shares.reduce((a, b) => a + b, 0)).toBeCloseTo(1, 9);
    expect(shares[0] / shares[1]).toBeCloseTo(99, 6);
  });

  it('leaves a move already above the floor where the book has it', () => {
    expect(withFloor([60, 40], [true, true])).toEqual([0.6, 0.4]);
  });

  it('caps what the lifted moves take between them', () => {
    const shares = withFloor([1000, 1, 1, 1, 1, 1], [true, true, true, true, true, true]);
    for (const share of shares.slice(1)) expect(share).toBeCloseTo(MAX_LIFTED / 5, 9);
    expect(shares[0]).toBeCloseTo(1 - MAX_LIFTED, 9);
  });
});
