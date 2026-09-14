import { describe, expect, it } from 'vitest';
import { applySan, positionKey, walkSan, START_FEN } from '../chess/core';
import {
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
import { decodeBook, type BookFile } from './book';

const FIXTURE: BookFile = {
  version: 1,
  source: 'test',
  builtAt: '2026-01-01',
  totalGames: 1000,
  positions: [
    // Shares are basis points of the position's own game count.
    [positionKey(START_FEN), 1000, [['e4', 6000, 50, 10], ['d4', 4000, 50, 10]]],
    [positionKey(walkSan(['e4']).fens.at(-1)!), 600, [['c5', 5000, 40, 10], ['e5', 5000, 40, 10]]],
    [positionKey(walkSan(['e4', 'c5']).fens.at(-1)!), 300, [['Nf3', 8000, 50, 10]]],
  ],
  names: [[positionKey(walkSan(['e4', 'c5']).fens.at(-1)!), 'e4 c5', 'B20', 'Sicilian Defense']],
};

describe('the book file', () => {
  const index = decodeBook(FIXTURE);

  it('expands basis-point shares back into game counts', () => {
    const start = lookup(index, START_FEN)!;
    expect(start.moves.map((m) => m.san)).toEqual(['e4', 'd4']);
    expect(start.moves[0].games).toBe(600);
    expect(start.moves[1].games).toBe(400);
  });

  it('splits a move\u2019s games across the three results', () => {
    const [e4] = lookup(index, START_FEN)!.moves;
    expect([e4.white, e4.draw, e4.black]).toEqual([300, 60, 240]);
    expect(e4.white + e4.draw + e4.black).toBe(e4.games);
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

  it('spells the book\u2019s American names the way the rest of the app does', () => {
    expect(index.catalogue.map((entry) => entry.name)).toContain('Sicilian Defence');
    expect(index.catalogue.map((entry) => entry.name)).not.toContain('Sicilian Defense');
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
    expect(entry.opening).toBe('Sicilian Defence: Najdorf Variation');
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
  it('is one entry however many move orders reach it', () => {
    // The crawl keys positions rather than lines, so 1.d4 Nf6 2.c4 e6 3.Nf3 and
    // 1.d4 Nf6 2.Nf3 e6 3.c4 are not two records to be merged — they are the
    // same record, found once.
    const index = referenceIndex();
    const one = walkSan('d4 Nf6 c4 e6 Nf3'.split(' ')).fens.at(-1)!;
    const other = walkSan('d4 Nf6 Nf3 e6 c4'.split(' ')).fens.at(-1)!;
    expect(positionKey(one)).toBe(positionKey(other));
    expect(lookup(index, one)).toBe(lookup(index, other));
    expect(totalGamesAt(lookup(index, one))).toBeGreaterThan(0);
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
    // 1.e4 c5 has a name at both plies: "King's Pawn Game" after e4 is
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

  it('stops naming where the line leaves the book', () => {
    // The book names every first move it holds, so a line that leaves it keeps
    // the last name it earned rather than picking one up from the moves after.
    const named = deepestNameForColor(index, ['a3', 'h6', 'a4'], 'w');
    expect(named?.name).toBe("Anderssen's Opening");
    expect(named?.ply).toBe(1);
  });

  it('stops at an illegal move rather than throwing', () => {
    expect(() => deepestNameForColor(index, ['e4', 'e4', 'e4'], 'w')).not.toThrow();
  });
});

describe('naming a line as the player\u2019s own opening', () => {
  const index = referenceIndex();

  it('gives nothing when the only name restates the first move', () => {
    // The bug this exists for: a Black line the book only recognises at 1.d4
    // came back as "Queen's Pawn Game" \u2014 true, and the name of what White
    // did. "Your Black prep" says more.
    expect(deepestNameForColor(index, ['d4', 'h6'], 'b')?.name).toBe("Queen's Pawn Game");
    expect(specificNameForColor(index, ['d4', 'h6'], 'b')).toBeNull();
    expect(specificNameForColor(index, ['d4', 'h6', 'c4'], 'w')).toBeNull();
  });

  it('keeps a Black reply at move one, which does name a choice', () => {
    expect(specificNameForColor(index, ['e4', 'c5'], 'b')?.name).toBe('Sicilian Defence');
  });

  it('keeps a name earned on the other side\u2019s move', () => {
    // The book attaches "King's Indian Defence" at White's fifth ply, and it is
    // still the name of Black's opening \u2014 so whose move earned it cannot be
    // what decides this. Here the deepest name for Black lands on Black's own
    // move, and the family it belongs to did not.
    const line = 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6'.split(' ');
    const found = specificNameForColor(index, line, 'b');
    expect(found?.name).toContain("King's Indian");
    expect(familyName(index, found!.name)).toBe("King's Indian Defence");
    // The family name itself is earned by White's fifth ply, and it names what
    // Black is doing all the same.
    const family = deepestName(index, line.slice(0, 5));
    expect(family?.name).toBe("King's Indian Defence");
    expect(family!.ply % 2).toBe(1);
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

  it('resolves a prefix the catalogue names on its own', () => {
    expect(familyName(index, 'French Defence: Winawer Variation')).toBe('French Defence');
    expect(familyName(index, 'Caro-Kann Defence: Advance Variation')).toBe('Caro-Kann Defence');
    expect(familyName(index, "King's Indian Defence: Sämisch Variation")).toBe(
      "King's Indian Defence",
    );
  });

  it('leaves the prefix standing when the book never names it alone', () => {
    // The book has Torre Attack lines but no bare "Torre Attack" position, and
    // the prefix is still the right heading for them.
    expect(familyName(index, 'Torre Attack: Classical Defence')).toBe('Torre Attack');
  });

  it('folds a variation named after a person under its family', () => {
    expect(familyName(index, 'Sicilian Defence: Dragon Variation, Yugoslav Attack')).toBe(
      'Sicilian Defence',
    );
    expect(familyName(index, 'Sicilian Defence: Najdorf Variation, English Attack')).toBe(
      'Sicilian Defence',
    );
  });

  it('leaves an opening that is already a family alone', () => {
    expect(familyName(index, 'Sicilian Defence')).toBe('Sicilian Defence');
    expect(familyName(index, "King's Pawn Game")).toBe("King's Pawn Game");
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
