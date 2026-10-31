import type { Color } from '../chess/core';
import { nodeById, type OpeningNode, type OpeningTree } from './openingTree';
import { pickerCatalog, sideForPick } from './picker';
import { colorsOf, type Selection } from './selection';

/**
 * "Any favorite": a selection that is one of your favorites per round rather
 * than one opening for good.
 *
 * It is stored as a sentinel opening id, which every reader that does not know
 * it takes for the whole tree (`nodeById` falls back to the root). The side
 * toggle filters: White is your White favorites, Black your Black ones, and
 * Random flips the side each round first and then picks one of that side's.
 * Each round lands on the favorite played longest ago, with a little chance,
 * and never the one just picked while there is another.
 */
export const ANY_FAVORITE = '*favorites';

export function isAnyFavorite(selection: Pick<Selection, 'opening'>): boolean {
  return selection.opening === ANY_FAVORITE;
}

export interface Favorite {
  node: OpeningNode;
  side: Color;
}

/** Your favorites with the side each one is played from, in the selection's sides. */
export function favoritesIn(tree: OpeningTree, ids: string[], color: Selection['color']): Favorite[] {
  const catalog = pickerCatalog(tree);
  const sides = colorsOf(color);
  return ids
    .map((id) => tree.byId.get(id))
    .filter((node): node is OpeningNode => Boolean(node) && node!.depth > 0)
    .map((node) => ({ node, side: sideForPick(catalog, node) ?? ('w' as Color) }))
    .filter((fav) => sides.includes(fav.side));
}

/** How much more the favorite played longest ago is picked than the next one. */
const ODDS = 0.5;

/**
 * The favorite a round lands on: by rank, played longest ago first, each next
 * one half as likely, skipping `last` while there is another to pick.
 */
export function pickFavorite(
  favorites: Favorite[],
  lastAt: (id: string) => number,
  last: string | null,
  rand: () => number,
): Favorite | null {
  const field = favorites.length > 1 ? favorites.filter((fav) => fav.node.id !== last) : favorites;
  if (!field.length) return null;
  const ranked = [...field].sort((a, b) => lastAt(a.node.id) - lastAt(b.node.id));
  const weights = ranked.map((_, i) => ODDS ** i);
  let roll = rand() * weights.reduce((sum, w) => sum + w, 0);
  for (let i = 0; i < ranked.length; i++) {
    roll -= weights[i];
    if (roll < 0) return ranked[i];
  }
  return ranked[ranked.length - 1];
}

/**
 * One round's concrete selection under "Any favorite": a side (Random flips
 * among the sides that have a favorite), then a favorite of that side. Any
 * other selection comes back as it is, and so does this one, as the whole
 * tree, with no favorite on the sides asked for.
 */
export function resolveFavorite(
  tree: OpeningTree,
  selection: Selection,
  ids: string[],
  lastAt: (id: string) => number,
  last: string | null,
  rand: () => number,
): Selection {
  if (!isAnyFavorite(selection)) return selection;
  const all = favoritesIn(tree, ids, selection.color);
  const sides = [...new Set(all.map((fav) => fav.side))];
  if (!sides.length) return { color: selection.color, opening: '' };
  const side = sides.length > 1 ? sides[Math.floor(rand() * sides.length)] : sides[0];
  const pick = pickFavorite(
    all.filter((fav) => fav.side === side),
    lastAt,
    last,
    rand,
  )!;
  return { color: pick.side, opening: pick.node.id };
}

/** One side and the region it covers: what an overview counts or lists within. */
export interface SideRegion {
  side: Color;
  node: OpeningNode;
}

/**
 * The regions a selection covers, per side: the one opening on each of its
 * sides, or under "Any favorite" each favorite on its own side — the whole
 * tree when there is none, the way a round resolves.
 */
export function regionsBySide(tree: OpeningTree, selection: Selection, ids: string[]): SideRegion[] {
  if (!isAnyFavorite(selection)) {
    const node = nodeById(tree, selection.opening);
    return colorsOf(selection.color).map((side) => ({ side, node }));
  }
  const favorites = favoritesIn(tree, ids, selection.color);
  if (!favorites.length) return colorsOf(selection.color).map((side) => ({ side, node: tree.root }));
  return favorites.map(({ node, side }) => ({ side, node }));
}

/**
 * Each region a selection covers, paired with that side's repertoire, and the
 * results merged without repeats: what one region's call gives, for all of them.
 */
export function acrossRegions<R extends { color: Color }, T>(
  regions: SideRegion[],
  reps: R[],
  each: (rep: R, node: OpeningNode) => T[],
  key: (item: T) => string,
): T[] {
  const seen = new Set<string>();
  const out: T[] = [];
  for (const { side, node } of regions) {
    for (const rep of reps) {
      if (rep.color !== side) continue;
      for (const item of each(rep, node)) {
        const id = key(item);
        if (seen.has(id)) continue;
        seen.add(id);
        out.push(item);
      }
    }
  }
  return out;
}
