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
 * The openings the book names a move late, and whose they really are.
 *
 * Both are named at a position one ply past the move that earned the name, so
 * reading the last ply files them under the wrong player: the King's Indian is
 * Black's ...g6 answered by 3.Nc3, and the Scotch is White's 3.d4 answered by
 * 3...exd4. Two of the book's hundred-odd families do this, and nothing about
 * their move orders sets them apart from the ones that do not — the Grünfeld
 * branches off the same 1.d4 Nf6 2.c4 g6 3.Nc3 and is named on Black's move,
 * as it should be. So they are written down rather than derived.
 */
const NAMED_LATE: Record<string, Color> = {
  // King's Indian Defence.
  'd4 Nf6 c4 g6 Nc3': 'b',
  // Scotch Game.
  'e4 e5 Nf3 Nc6 d4 exd4': 'w',
};

/** The ids of the openings above, for a test to check the book still has them. */
export const NAMED_LATE_IDS = Object.keys(NAMED_LATE);

/**
 * Whose opening a line is: whoever played its last move.
 *
 * An opening is named for what one side did — "Sicilian Defence" is Black's
 * 1...c5, "Ruy Lopez" is White's 3.Bb5 — and the book attaches the name at the
 * ply of the move that earned it. So the last ply of a node's move order names
 * the side whose repertoire it belongs in. White opens, so odd plies are White's.
 *
 * Except where the book names the opening a move late — see `NAMED_LATE`.
 */
export function playerOf(sans: string[]): Color {
  return NAMED_LATE[sans.join(' ')] ?? (sans.length % 2 === 1 ? 'w' : 'b');
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
