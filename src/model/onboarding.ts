import type { Color } from '../chess/core';
import type { OpeningTree } from './openingTree';
import { DEFAULT_SELECTION, type Selection } from './selection';

/**
 * Onboarding: the openings a new player says they already play.
 *
 * A fresh install has no repertoires, and every mode needs one — Drill asks
 * about what is in it, Repair compares games against it, Run replays it. The
 * first screen therefore asks the only question the app cannot work out for
 * itself: which openings are yours? Anything picked is starred, and its own
 * move order goes into the tree for the side that plays it.
 *
 * What goes in is the picked opening's defining move order and nothing else.
 * Filling the rest out with the book's most-played continuations would be
 * seeding by another name — lines nobody chose, which is precisely what the
 * empty first install exists to avoid. Growth extends them, a few moves at a
 * time, with the player choosing every one.
 */

export interface OpeningPick {
  /** The opening tree node, identified by the move order that defines it. */
  id: string;
  name: string;
  /** Whose opening it is — see `playerOf`. */
  color: Color;
  /** Exactly what goes into the repertoire: the moves the name attaches to. */
  sans: string[];
}

/**
 * Whose opening a line is: whoever played its last move.
 *
 * An opening is named for what one side did — "Sicilian Defence" is Black's
 * 1...c5, "Ruy Lopez" is White's 3.Bb5 — and the book attaches the name at the
 * ply of the move that earned it. So the last ply of a node's move order names
 * the side whose repertoire it belongs in. White opens, so odd plies are White's.
 */
export function playerOf(sans: string[]): Color {
  return sans.length % 2 === 1 ? 'w' : 'b';
}

/**
 * The picks behind a set of starred node ids, in the order given.
 *
 * Ids the tree does not know are dropped rather than guessed at, and so is the
 * root: "any opening" is not an opening anyone plays.
 */
export function picksFrom(tree: OpeningTree, ids: Iterable<string>): OpeningPick[] {
  const out: OpeningPick[] = [];
  const seen = new Set<string>();
  for (const id of ids) {
    if (seen.has(id)) continue;
    seen.add(id);
    const node = tree.byId.get(id);
    if (!node || node.sans.length === 0) continue;
    out.push({ id: node.id, name: node.name, color: playerOf(node.sans), sans: node.sans });
  }
  return out;
}

/**
 * The global selection the picks imply.
 *
 * Picking only Black openings is a statement about which side you play, and
 * Home is read through the selection, so carrying it over is the difference
 * between landing on a screen that is ready and one that is generic. One
 * opening names itself; several stay under "any", where the starred rows float
 * to the top of the picker anyway. Picking nothing says nothing.
 */
export function selectionFor(picks: OpeningPick[]): Selection {
  if (picks.length === 0) return { ...DEFAULT_SELECTION };
  const colors = new Set(picks.map((pick) => pick.color));
  const [only] = colors;
  return {
    color: colors.size === 1 ? only : 'random',
    opening: picks.length === 1 ? picks[0].id : '',
  };
}
