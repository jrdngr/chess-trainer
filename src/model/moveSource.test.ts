import { describe, expect, it } from 'vitest';
import { addedByYou, growthSource, normalizeSources, sourceLabel, SOURCE_LABELS } from './moveSource';
import { MAX_LIFTED, PREPARED_FLOOR, withFloor } from './prepFloor';
import { rareReason, rareReplies } from './rareReplies';
import { openingTree } from './openingTree';
import { referenceIndex } from './referenceIndex';
import { addLine, createRepertoire, nodeAtLine } from './repertoire';
import type { MoveSource, Repertoire } from './types';

const index = referenceIndex();
const KID = ['d4', 'Nf6', 'c4', 'g6', 'Nc3', 'Bg7', 'e4', 'd6'];

describe('source labels', () => {
  it('names every source', () => {
    expect(Object.keys(SOURCE_LABELS)).toHaveLength(10);
    expect(sourceLabel('manual')).toBe('Entered by hand');
    expect(sourceLabel('import')).toBe('Imported games');
  });

  it('tells your additions from the book and the engine', () => {
    for (const source of ['manual', 'analysis', 'import', 'play', 'tidy'] as MoveSource[]) {
      expect(addedByYou(source)).toBe(true);
    }
    for (const source of ['picker', 'book', 'growth', 'engine', 'seed'] as MoveSource[]) {
      expect(addedByYou(source)).toBe(false);
    }
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

describe('replies strong players rarely choose', () => {
  const tree = openingTree(index);
  const root = tree.root;

  function rep(): Repertoire {
    let r = createRepertoire('Black', 'b', 'r_rare');
    r = addLine(r, [...KID, 'Nf3', 'O-O'], 'book').rep;
    r = addLine(r, [...KID, 'e5', 'dxe5'], 'manual').rep;
    return r;
  }

  it('lists a reply you added that the book lacks, and not the book’s', () => {
    const found = rareReplies([rep()], index, tree, root, 1);
    expect(found.map((reply) => reply.san)).toEqual(['e5']);
    expect(found[0].removes).toBe(2);
    expect(rareReason(found[0])).toBe('Entered by hand · strong players never choose it');
  });

  it('leaves out a rare reply that came from the engine', () => {
    const r = addLine(createRepertoire('Black', 'b', 'r_eng'), [...KID, 'e5'], 'engine').rep;
    expect(rareReplies([r], index, tree, root, 1)).toEqual([]);
  });

  it('drops a kept reply until something under it is newer', () => {
    const r = rep();
    const e5 = nodeAtLine(r, [...KID, 'e5'])!;
    const later = Math.max(...Object.values(r.nodes).map((n) => n.addedAt)) + 1;
    const kept = { ...r, nodes: { ...r.nodes, [e5.id]: { ...e5, keptAt: later } } };
    expect(rareReplies([kept], index, tree, root, 1)).toEqual([]);
    const grown = addLine(kept, [...KID, 'e5', 'dxe5', 'dxe5'], 'manual').rep;
    const tip = nodeAtLine(grown, [...KID, 'e5', 'dxe5', 'dxe5'])!;
    const newer = { ...grown, nodes: { ...grown.nodes, [tip.id]: { ...tip, addedAt: later + 1 } } };
    // 7.dxe5 is listed in its own right; 5.e5 comes back because it is newer under it.
    expect(rareReplies([newer], index, tree, root, 1).map((reply) => reply.san)).toEqual(['e5', 'dxe5']);
  });
});
