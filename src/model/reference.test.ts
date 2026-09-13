import { describe, expect, it } from 'vitest';
import { applySan, positionKey, walkSan, START_FEN } from '../chess/core';
import {
  buildReferenceIndex,
  buildRefTree,
  deepestName,
  deepestNameForColor,
  familyName,
  formatGameCount,
  lookup,
  openingNameForPath,
  specificNameForColor,
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

describe('naming a line from one side', () => {
  const index = referenceIndex();

  it('prefers a name earned by the side that is asking', () => {
    // 1.e4 c5 has a name at both plies: "King's Pawn Opening" after e4 is
    // White's, "Sicilian Defence" after c5 is Black's.
    expect(deepestNameForColor(index, ['e4', 'c5'], 'b')?.name).toBe('Sicilian Defence');
    expect(deepestNameForColor(index, ['e4', 'c5'], 'w')?.name).not.toBe('Sicilian Defence');
  });

  it('falls back to the other side rather than giving no name', () => {
    // Nothing names 1.d4 Nf6 from Black's side, so White's name is better than
    // nothing — but it must still be the deepest one available.
    const black = deepestNameForColor(index, ['d4', 'Nf6'], 'b');
    expect(black).not.toBeNull();
    expect(black?.name).toBe(deepestName(index, ['d4', 'Nf6'])?.name);
  });

  it('goes as deep as the line allows', () => {
    const line = 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6'.split(' ');
    expect(deepestNameForColor(index, line, 'b')?.name).toContain("King's Indian");
  });

  it('returns nothing for a line that leaves the book at once', () => {
    expect(deepestNameForColor(index, ['a3', 'h6', 'a4'], 'w')).toBeNull();
  });

  it('stops at an illegal move rather than throwing', () => {
    expect(() => deepestNameForColor(index, ['e4', 'e4', 'e4'], 'w')).not.toThrow();
  });
});

describe('naming a line as the player\u2019s own opening', () => {
  const index = referenceIndex();

  it('gives nothing when the only name restates the first move', () => {
    // The bug this exists for: a Black line the book only recognises at 1.d4
    // came back as "Queen's Pawn Opening" \u2014 true, and the name of what White
    // did. "Your Black prep" says more.
    expect(deepestNameForColor(index, ['d4', 'Nf6'], 'b')?.name).toBe("Queen's Pawn Opening");
    expect(specificNameForColor(index, ['d4', 'Nf6'], 'b')).toBeNull();
    expect(specificNameForColor(index, ['d4', 'Nf6', 'Bf4'], 'w')).toBeNull();
  });

  it('keeps a Black reply at move one, which does name a choice', () => {
    expect(specificNameForColor(index, ['e4', 'c5'], 'b')?.name).toBe('Sicilian Defence');
  });

  it('keeps a name earned on the other side\u2019s move', () => {
    // The book attaches "King's Indian Defence" at White's seventh ply, and it
    // is still the name of Black's opening \u2014 so whose move earned it cannot be
    // what decides this.
    const line = 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6'.split(' ');
    const found = specificNameForColor(index, line, 'b');
    expect(found?.name).toContain("King's Indian");
    expect(found!.ply % 2).toBe(1);
  });

  it('takes the cutoff as an argument, for callers that want more', () => {
    const line = 'e4 c5'.split(' ');
    expect(specificNameForColor(index, line, 'b', START_FEN, 3)).toBeNull();
  });

  it('stops at an illegal move rather than throwing', () => {
    expect(() => specificNameForColor(index, ['e4', 'e4', 'e4'], 'w')).not.toThrow();
  });
});

describe('opening families', () => {
  const index = referenceIndex();

  it('folds an abbreviation the catalogue never spells out', () => {
    expect(familyName(index, 'KID: Sämisch Variation')).toBe("King's Indian Defence");
    expect(familyName(index, 'KID: Bf4 System')).toBe("King's Indian Defence");
  });

  it('resolves a prefix the catalogue does name on its own', () => {
    expect(familyName(index, 'French: Winawer')).toBe('French Defence');
    expect(familyName(index, 'Caro-Kann: Advance')).toBe('Caro-Kann Defence');
    expect(familyName(index, 'Dutch: Leningrad')).toBe('Dutch Defence');
  });

  it('folds a variation named after a person rather than its parent', () => {
    // Nothing in "Dragon: Yugoslav Attack" says Sicilian, and no position on
    // the way to it carries the Sicilian's name either.
    expect(familyName(index, 'Dragon: Yugoslav Attack')).toBe('Sicilian Defence');
    expect(familyName(index, 'Najdorf: English Attack')).toBe('Sicilian Defence');
  });

  it('leaves an opening that is already a family alone', () => {
    expect(familyName(index, 'Sicilian Defence')).toBe('Sicilian Defence');
    expect(familyName(index, "King's Pawn Opening")).toBe("King's Pawn Opening");
  });

  it('hands back a name it has never heard of unchanged', () => {
    // Only names the book actually carries are folded. Splitting an unknown one
    // on its colon would invent a family out of a string nobody authored.
    expect(familyName(index, 'Grace Attack')).toBe('Grace Attack');
    expect(familyName(index, 'Nonsense: Variation')).toBe('Nonsense: Variation');
  });

  it('never folds a family into something that is itself a variation', () => {
    for (const named of new Set([...index.names.values()].map((n) => n.name))) {
      expect(familyName(index, named)).not.toContain(': ');
    }
  });
});
