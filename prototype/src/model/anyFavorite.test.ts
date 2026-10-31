import { describe, expect, it } from 'vitest';
import { buildBookIndex } from './book';
import { openingTree } from './openingTree';
import { pickerCatalog } from './picker';
import { ANY_FAVORITE, favoritesIn, pickFavorite, regionsBySide, resolveFavorite } from './anyFavorite';

const tree = openingTree(buildBookIndex());
const catalog = pickerCatalog(tree);
const id = (key: string) => catalog.byKey.get(key)!.node.id;
const NAJDORF = id('Sicilian Defence: Najdorf Variation');
const RUY = id('Ruy Lopez');
const CARO = id('Caro-Kann Defence');
const favorites = [NAJDORF, RUY, CARO];
const never = () => 0;

describe('favoritesIn', () => {
  it('filters favorites by the side they are played from', () => {
    expect(favoritesIn(tree, favorites, 'w').map((f) => f.node.id)).toEqual([RUY]);
    expect(favoritesIn(tree, favorites, 'b').map((f) => f.node.id)).toEqual([NAJDORF, CARO]);
    expect(favoritesIn(tree, favorites, 'random')).toHaveLength(3);
  });
});

describe('pickFavorite', () => {
  const black = favoritesIn(tree, favorites, 'b');

  it('leans to the favorite played longest ago', () => {
    const lastAt = (fav: string) => (fav === NAJDORF ? 100 : 50);
    expect(pickFavorite(black, lastAt, null, () => 0)!.node.id).toBe(CARO);
    expect(pickFavorite(black, lastAt, null, () => 0.99)!.node.id).toBe(NAJDORF);
  });

  it('never repeats the last pick while there is another', () => {
    for (const roll of [0, 0.5, 0.99]) expect(pickFavorite(black, never, CARO, () => roll)!.node.id).toBe(NAJDORF);
  });

  it('repeats a lone favorite', () => {
    const white = favoritesIn(tree, favorites, 'w');
    expect(pickFavorite(white, never, RUY, () => 0)!.node.id).toBe(RUY);
  });
});

describe('resolveFavorite', () => {
  it('leaves any other selection alone', () => {
    const selection = { color: 'b' as const, opening: NAJDORF };
    expect(resolveFavorite(tree, selection, favorites, never, null, Math.random)).toBe(selection);
  });

  it('sets the side from the favorite it lands on', () => {
    expect(resolveFavorite(tree, { color: 'w', opening: ANY_FAVORITE }, favorites, never, null, () => 0.3)).toEqual({
      color: 'w',
      opening: RUY,
    });
  });

  it('flips the side first on random', () => {
    const white = resolveFavorite(tree, { color: 'random', opening: ANY_FAVORITE }, favorites, never, null, () => 0.1);
    const black = resolveFavorite(tree, { color: 'random', opening: ANY_FAVORITE }, favorites, never, null, () => 0.9);
    expect([white.color, black.color].sort()).toEqual(['b', 'w']);
  });

  it('falls back to the whole tree with no favorite on the side', () => {
    expect(resolveFavorite(tree, { color: 'w', opening: ANY_FAVORITE }, [NAJDORF], never, null, () => 0)).toEqual({
      color: 'w',
      opening: '',
    });
  });
});

describe('regionsBySide', () => {
  it('covers each favorite on its own side', () => {
    const regions = regionsBySide(tree, { color: 'random', opening: ANY_FAVORITE }, favorites);
    expect(regions.map((r) => [r.side, r.node.id])).toEqual([
      ['b', NAJDORF],
      ['w', RUY],
      ['b', CARO],
    ]);
  });

  it('is the one opening otherwise', () => {
    expect(regionsBySide(tree, { color: 'random', opening: RUY }, favorites).map((r) => r.side)).toEqual(['w', 'b']);
  });
});
