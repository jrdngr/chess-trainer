import { describe, expect, it } from 'vitest';
import { buildBookIndex } from './book';
import {
  bookItems,
  isHead,
  mixLabels,
  myLines,
  nextMoves,
  recentItems,
  repMoves,
  searchItems,
  shelfRows,
  SHELVES,
  suggestions,
  type BrowseRow,
} from './browse';
import { nodeById, openingTree } from './openingTree';
import { pickerCatalog } from './picker';
import { addLine, createRepertoire } from './repertoire';
import { EMPTY_SCORE, emptyNodeStats, type ScoreState } from './scoring';
import type { Repertoire } from './types';

const index = buildBookIndex();
const tree = openingTree(index);
const catalog = pickerCatalog(tree);

function rep(color: 'w' | 'b', lines: string[]): Repertoire {
  let r = createRepertoire(color === 'w' ? 'White' : 'Black', color, `rep-${color}`);
  for (const line of lines) r = addLine(r, line.split(' '), 'book').rep;
  return r;
}

const rows = (items: ReturnType<typeof bookItems>) => items.filter((i): i is BrowseRow => !isHead(i));

describe('shelves', () => {
  it('names only openings the book has', () => {
    for (const shelf of SHELVES) for (const key of shelf.keys) expect(catalog.byKey.has(key), key).toBe(true);
  });

  it('lists every one of them', () => {
    for (const shelf of SHELVES) expect(shelfRows(catalog, shelf)).toHaveLength(shelf.keys.length);
  });
});

describe('book', () => {
  it('lists families under their first move', () => {
    const items = bookItems(catalog);
    expect(items[0]).toEqual({ head: '1.e4' });
    expect(rows(items).some((row) => row.key === 'Sicilian Defence')).toBe(true);
  });

  it('opens a big family on its groups, and a group on its branches', () => {
    const sicilian = rows(bookItems(catalog)).find((row) => row.key === 'Sicilian Defence')!;
    const groups = sicilian.open!() as BrowseRow[];
    expect(groups.length).toBeGreaterThan(1);
    const open = groups.find((g) => g.label === 'Open Sicilian')!;
    expect((open.open!() as BrowseRow[]).some((row) => row.key === 'Sicilian Defence: Najdorf Variation')).toBe(true);
  });
});

describe('my lines', () => {
  const white = rep('w', ['d4 d5 c4 dxc4', 'd4 d5 c4 e6 Nc3 Nf6', 'd4 d5 c4 c6 Nf3 Nf6']);
  const black = rep('b', ['e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6']);

  it('heads each side and lists its openings', () => {
    const items = myLines([white, black], index, tree, []);
    expect(items[0]).toEqual({ head: 'White' });
    expect(items.some((i) => isHead(i) && i.head === 'Black')).toBe(true);
    const all = rows(items).flatMap((row) => [row, ...rows(row.open?.() ?? [])]);
    expect(all.some((row) => row.label === "Queen's Gambit Accepted")).toBe(true);
    expect(all.some((row) => row.label.includes('Najdorf'))).toBe(true);
    expect(rows(items).every((row) => row.sans.length > 0)).toBe(true);
  });

  it('puts favorites first', () => {
    const plain = rows(myLines([white], index, tree, []));
    const last = plain[plain.length - 1];
    const node = tree.byKey.get(nodeById(tree, last.sans.join(' ')).key)!;
    const starred = rows(myLines([white], index, tree, [node.id]));
    expect(starred[0].key).toBe(last.key);
  });
});

describe('next moves', () => {
  it('lists book moves from the start, most played first, and marks yours', () => {
    const moves = nextMoves(index, tree, catalog, [], repMoves([rep('w', ['d4 d5'])]));
    expect(moves.length).toBeGreaterThan(3);
    expect(moves[0].share).toBeGreaterThanOrEqual(moves[1].share);
    expect(moves.find((m) => m.san === 'd4')?.mine).toBe(true);
    expect(moves.find((m) => m.san === 'e4')?.mine).toBe(false);
    expect(moves.find((m) => m.san === 'e4')?.label).toBe('1.e4');
  });

  it('names a reply by where it goes', () => {
    const moves = nextMoves(index, tree, catalog, ['e4'], new Set());
    expect(moves.find((m) => m.san === 'c5')?.name).toContain('Sicilian');
  });
});

describe('search', () => {
  it('finds by initials and by moves', () => {
    const byInitials = rows(searchItems('qga', [], index, tree, catalog));
    expect(byInitials.some((row) => row.label.startsWith("Queen's Gambit Accepted"))).toBe(true);
    const byMoves = rows(searchItems('1.e4 c5', [], index, tree, catalog));
    expect(byMoves.some((row) => row.label.startsWith('Sicilian'))).toBe(true);
  });

  it('lists your own lines first', () => {
    const items = searchItems('slav', [rep('w', ['d4 d5 c4 c6 Nf3 Nf6'])], index, tree, catalog);
    expect(items[0]).toEqual({ head: 'My lines' });
  });
});

describe('recent', () => {
  it('groups played openings by when', () => {
    const now = new Date(2026, 9, 20, 12).getTime();
    const node = (id: string, lastAt: number) => [id, { ...emptyNodeStats(), lastAt }] as const;
    const ids = [...tree.byId.keys()].filter((id) => tree.byId.get(id)!.depth > 2).slice(0, 3);
    const score: ScoreState = {
      ...EMPTY_SCORE,
      nodes: Object.fromEntries([node(ids[0], now - 1000), node(ids[1], now - 3 * 86400000), node(ids[2], now - 30 * 86400000)]),
    };
    const items = recentItems(tree, catalog, score, now);
    expect(items.filter(isHead).map((h) => h.head)).toEqual(['Today', 'This week', 'Earlier']);
  });
});

describe('suggestions', () => {
  it('fills the holes of an empty repertoire with answers to the first moves', () => {
    const list = suggestions([], index, tree, catalog);
    expect(list.length).toBeGreaterThan(0);
    expect(list[0].why?.kind).toBe('hole');
    expect(list.some((row) => row.why?.text === 'Nothing yet against 1.e4')).toBe(true);
    expect(list.every((row) => row.side === 'b')).toBe(true);
  });

  it('says book games, never your games', () => {
    const black = rep('b', ['e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6', 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6']);
    const list = suggestions([black], index, tree, catalog);
    const holes = list.filter((row) => row.why?.kind === 'hole' && !row.why.text.startsWith('Nothing'));
    expect(holes.length).toBeGreaterThan(0);
    for (const row of holes) expect(row.why!.text).toMatch(/ in \d+% of book games$/);
  });

  it('mixes the reasons', () => {
    const white = rep('w', ['d4 d5 c4 e6 Nc3 Nf6 Bg5 Be7 e3 O-O', 'd4 d5 c4 c6 Nf3 Nf6 Nc3 dxc4 a4 Bf5']);
    const black = rep('b', ['e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6', 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6']);
    const list = suggestions([white, black], index, tree, catalog);
    const kinds = new Set(list.map((row) => row.why?.kind));
    expect(kinds.size).toBeGreaterThan(1);
    for (const row of list) expect(row.why?.text).toBeTruthy();
    expect(list.some((row) => row.why?.text === 'Sharp like your Najdorf' || row.why?.text === "Sharp like your King's Indian")).toBe(true);
    expect(list.some((row) => row.why?.text.startsWith('Transposes into your '))).toBe(true);
  });
});

describe('mixLabels', () => {
  it('never deals three of one label in a row while another is left', () => {
    const row = (kind: 'hole' | 'like' | 'style', i: number): BrowseRow => ({
      key: `${kind}${i}`,
      label: '',
      sans: [],
      side: 'w',
      why: { kind, text: kind },
    });
    const mixed = mixLabels([row('hole', 1), row('hole', 2), row('hole', 3), row('hole', 4), row('like', 1), row('style', 1)]);
    expect(mixed.map((r) => r.key)).toEqual(['hole1', 'hole2', 'like1', 'hole3', 'hole4', 'style1']);
  });
});

describe('a line the book does not name', () => {
  it('is a node carrying the deepest name along it', () => {
    const node = nodeById(tree, 'd4 d5 c4 c6 Nf3 Nf6 Nc3 dxc4 a4 Bf5 e3 e6');
    expect(node.custom).toBe(true);
    expect(node.name).toContain('Slav');
    expect(node.sans).toHaveLength(12);
  });
});
