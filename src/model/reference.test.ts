import { describe, expect, it } from 'vitest';
import { applySan, positionKey, walkSan, START_FEN } from '../chess/core';
import {
  buildReferenceIndex,
  buildRefTree,
  formatGameCount,
  lookup,
  openingNameForPath,
  totalGamesAt,
} from './reference';
import { referenceIndex } from './referenceIndex';

describe('reference tree', () => {
  it('merges shared prefixes across paths', () => {
    const tree = buildRefTree(['e4:44 c5:42 Nf3:70', 'e4:44 e5:23']);
    expect([...tree.keys()]).toEqual(['e4']);
    expect([...tree.get('e4')!.children.keys()].sort()).toEqual(['c5', 'e5']);
  });

  it('inherits the result split from the parent when omitted', () => {
    const tree = buildRefTree(['e4:44:40/30/30 c5:42']);
    expect(tree.get('e4')!.children.get('c5')!.wdl).toEqual([40, 30, 30]);
  });
});

describe('reference index', () => {
  const index = buildReferenceIndex({
    paths: ['e4:60 c5:50 Nf3:80', 'e4:60 e5:50', 'd4:40 d5:100'],
    openingNames: { 'e4 c5': { eco: 'B20', name: 'Sicilian Defence' } },
    games: [],
    totalGames: 1000,
  });

  it('splits games between siblings in proportion to their share', () => {
    const start = lookup(index, START_FEN)!;
    expect(start.moves.map((m) => m.san)).toEqual(['e4', 'd4']);
    expect(start.moves[0].games).toBe(600);
    expect(start.moves[1].games).toBe(400);
  });

  it('never shows a child more popular than its parent', () => {
    const afterE4 = lookup(index, walkSan(['e4']).fens.at(-1)!)!;
    expect(totalGamesAt(afterE4)).toBeLessThanOrEqual(600);
  });

  it('resolves opening names onto positions', () => {
    const key = positionKey(walkSan(['e4', 'c5']).fens.at(-1)!);
    expect(index.names.get(key)).toEqual({ eco: 'B20', name: 'Sicilian Defence' });
    expect(openingNameForPath(index, ['e4', 'c5', 'Nf3'])?.name).toBe('Sicilian Defence');
    expect(openingNameForPath(index, ['d4'])).toBeNull();
  });

  it('skips illegal authored moves rather than throwing', () => {
    const broken = buildReferenceIndex({
      paths: ['e4:50 Qh5:20 e5:99'],
      openingNames: {},
      games: [],
      totalGames: 10,
    });
    expect(lookup(broken, START_FEN)!.moves.map((m) => m.san)).toEqual(['e4']);
  });
});

describe('the seeded database', () => {
  const index = referenceIndex();

  it('covers the main first moves with believable shares', () => {
    const start = lookup(index, START_FEN)!;
    const total = totalGamesAt(start);
    const e4 = start.moves.find((m) => m.san === 'e4')!;
    expect(start.moves.length).toBeGreaterThan(4);
    expect(e4.games / total).toBeGreaterThan(0.3);
    expect(e4.games / total).toBeLessThan(0.6);
  });

  it('knows the Najdorf', () => {
    const najdorf = walkSan('e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6'.split(' ')).fens.at(-1)!;
    const entry = lookup(index, najdorf)!;
    expect(entry.opening).toBe('Sicilian: Najdorf');
    expect(entry.eco).toBe('B90');
    expect(entry.moves.map((m) => m.san)).toEqual(
      expect.arrayContaining(['Be3', 'Bg5', 'Be2', 'Bc4', 'f4', 'h3']),
    );
  });

  it('attaches master games to positions those games reach', () => {
    const opera = walkSan(['e4', 'e5', 'Nf3', 'd6']).fens.at(-1)!;
    const entry = lookup(index, opera)!;
    expect(entry.topGames?.some((g) => g.white.startsWith('Morphy'))).toBe(true);
  });

  it('has no entry for an off-book position', () => {
    const silly = walkSan(['a4', 'h5', 'b4']).fens.at(-1)!;
    expect(lookup(index, silly)).toBeNull();
  });
});

describe('formatting', () => {
  it('abbreviates game counts', () => {
    expect(formatGameCount(420)).toBe('420');
    expect(formatGameCount(4200)).toBe('4.2k');
    expect(formatGameCount(42000)).toBe('42k');
    expect(formatGameCount(4_200_000)).toBe('4.2M');
  });
});

describe('transposed positions', () => {
  it('merges the moves of every route into one entry', () => {
    // Two move orders reaching the same position, each with a continuation the
    // other does not have. Overwriting would lose one of them.
    const index = buildReferenceIndex({
      paths: [
        'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 Nc6 Bg5',
        'e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 Nf6 Nc3 d6 Be3',
      ],
      totalGames: 1000,
      openingNames: {},
      games: [],
    });
    let fen = START_FEN;
    for (const san of 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 Nc6'.split(' ')) {
      fen = applySan(fen, san)!.after;
    }
    const sans = lookup(index, fen)?.moves.map((m) => m.san) ?? [];
    expect(sans).toContain('Bg5');
    expect(sans).toContain('Be3');
  });

  it('conserves the games when two routes rejoin', () => {
    // Both move orders lead here, so the split upstream and the merge here
    // cancel out: the position is as popular as the games that reach it,
    // neither inflated by counting each route nor halved by keeping only one.
    const index = buildReferenceIndex({
      paths: ['d4 Nf6 c4 e6 Nf3 d5', 'd4 Nf6 Nf3 e6 c4 d5'],
      totalGames: 1000,
      openingNames: {},
      games: [],
    });
    let fen = START_FEN;
    for (const san of 'd4 Nf6 c4 e6 Nf3'.split(' ')) fen = applySan(fen, san)!.after;
    const entry = lookup(index, fen);
    expect(entry?.moves).toHaveLength(1);
    expect(totalGamesAt(entry)).toBe(1000);
  });

  it('keeps the King’s Indian branching the seed data authors', () => {
    // The real index, which is what Opening Run draws from: after the King's
    // Indian move order there must be more than one thing White can do, or
    // every run of it is the same game.
    const index = referenceIndex();
    let fen = START_FEN;
    for (const san of 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6'.split(' ')) fen = applySan(fen, san)!.after;
    const sans = lookup(index, fen)?.moves.map((m) => m.san) ?? [];
    expect(sans.length).toBeGreaterThanOrEqual(4);
    expect(sans).toEqual(expect.arrayContaining(['Nf3', 'f3', 'Be2']));
  });
});
