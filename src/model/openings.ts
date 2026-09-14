import type { Color } from '../chess/core';
import { nameAt, type ReferenceIndex } from './reference';
import { childrenOf, pruneCount } from './repertoire';
import type { RepMove, Repertoire } from './types';

/**
 * Openings, derived from the tree rather than stored.
 *
 * The app keeps one tree per colour — see `repertoireName` — and an opening is a
 * named region of that tree: the subtree beginning at the move where the book
 * starts calling the position something. A variation is the same thing one level
 * further in, so the two fall out of one walk.
 *
 * Deriving beats storing here for two reasons the app depends on. Transpositions
 * land on the same node for free in one position-keyed tree, where per-opening
 * containers would duplicate them; and SRS cards are keyed
 * `repertoireId#positionKey`, so splitting the tree would give one position two
 * cards and drill it twice.
 */

export interface DerivedOpening {
  /** Stable within a repertoire: the node the region begins at. */
  id: string;
  repertoireId: string;
  color: Color;
  name: string;
  eco?: string;
  /** The node the region begins at. Deleting it deletes the opening. */
  rootId: string;
  /** Moves from the start up to and including that node's move. */
  path: string[];
  /** Nodes in the region, including those inside its variations. */
  moves: number;
  /**
   * Moves that exist only for this opening — its own, plus the move order that
   * leads to it and nothing else. What deleting it would cost, and the honest
   * measure of its size: a region named at ply 7 holds two nodes but represents
   * eight moves of work.
   */
  removes: number;
  /** Lines that end inside the region. */
  lines: number;
  /** Deepest ply the region reaches. */
  depth: number;
  /** Named regions one level further in. */
  variations: DerivedOpening[];
}

interface Region {
  name: string;
  eco?: string;
  rootId: string;
  path: string[];
  /** Ply the name attaches at. One means it only restates the first move. */
  ply: number;
  children: Region[];
  /**
   * Lines ending in this region but outside every child region. A region with
   * none of its own is only a waypoint on the way to the openings below it.
   */
  ownLines: number;
}

/** Every opening in one repertoire, the biggest first. */
export function openingsIn(rep: Repertoire, index: ReferenceIndex): DerivedOpening[] {
  const tops: Region[] = [];

  const visit = (node: RepMove, path: string[], enclosing: Region | null) => {
    const here = [...path, node.san];
    const named = nameAt(index, node.fenAfter);
    let region = enclosing;

    // A name the enclosing region already carries is the same region seen
    // deeper: the data names a few positions identically at different plies.
    if (named && named.name !== enclosing?.name) {
      region = {
        name: named.name,
        eco: named.eco,
        rootId: node.id,
        path: here,
        ply: here.length,
        children: [],
        ownLines: 0,
      };
      (enclosing?.children ?? tops).push(region);
    } else if (!region) {
      // Nothing on this path is named, so the move names itself. Without this
      // an opening the book has never heard of would simply not be listed.
      region = {
        name: moveLabel(here),
        rootId: node.id,
        path: here,
        ply: here.length,
        children: [],
        ownLines: 0,
      };
      tops.push(region);
    }

    const kids = childrenOf(rep, node.id);
    if (!kids.length) region.ownLines += 1;
    for (const kid of kids) visit(kid, here, region);
  };

  for (const root of childrenOf(rep, null)) visit(root, [], null);

  return sorted(collapse(tops).map((region) => finish(rep, region)));
}

/** Every opening across both sides, each still knowing which tree it came from. */
export function openingsAcross(reps: Repertoire[], index: ReferenceIndex): DerivedOpening[] {
  return sorted(reps.flatMap((rep) => openingsIn(rep, index)));
}

/** The opening a node sits in, if the list is already to hand. */
export function openingAt(openings: DerivedOpening[], nodeId: string): DerivedOpening | null {
  for (const opening of openings) {
    if (opening.rootId === nodeId) return opening;
    const deeper = openingAt(opening.variations, nodeId);
    if (deeper) return deeper;
  }
  return null;
}

/**
 * Drop the names that only lead somewhere.
 *
 * A Black repertoire holding one King's Indian starts at 1.d4, which the book
 * calls the Queen's Pawn Game — the name of what White did. Listing that as the
 * opening is how a King's Indian came to be filed under White's first move.
 * Since every line under it is really a King's Indian, the waypoint is dropped
 * and its child takes its place. The same rule does the right thing for White:
 * 1.e4 with prep against c5, e5 and e6 lists as three openings rather than one
 * "King's Pawn Game" with everything buried inside it.
 *
 * Deeper down a second rule applies: a region with no lines of its own and
 * exactly one region under it describes no choice anybody made, so it goes too.
 * The book names nearly every position, so one King's Indian line arrives here
 * as Indian Defence → Indian Defence: Normal Variation → Indian Defence: West
 * Indian Defence → King's Indian Defence → King's Indian Defence: Normal
 * Variation, and four of those five headings name a position the player only
 * passed through on the way to the one they meant.
 *
 * The two rules differ in what they do with branches, which is the whole point.
 * A first move is dropped however many openings sit under it — 1.e4 met by the
 * Sicilian, the French and 1...e5 is three openings, not one. A deeper name is
 * kept as soon as it has more than one region under it, because then the
 * heading is what those branches have in common.
 *
 * A region with lines of its own is never dropped, whatever its depth, or those
 * lines would be listed nowhere at all.
 */
function collapse(regions: Region[]): Region[] {
  const out: Region[] = [];
  for (const region of regions) {
    const children = collapse(region.children);
    const firstMove = region.ply <= 1 && children.length > 0;
    const waypoint = children.length === 1;
    if (region.ownLines === 0 && (firstMove || waypoint)) out.push(...children);
    else out.push({ ...region, children });
  }
  return out;
}

function finish(rep: Repertoire, region: Region): DerivedOpening {
  const stats = subtreeStats(rep, region.rootId, region.path.length);
  return {
    id: `${rep.id}#${region.rootId}`,
    repertoireId: rep.id,
    color: rep.color,
    name: region.name,
    eco: region.eco,
    rootId: region.rootId,
    path: region.path,
    moves: stats.moves,
    removes: pruneCount(rep, region.rootId),
    lines: stats.lines,
    depth: stats.depth,
    variations: sorted(region.children.map((child) => finish(rep, child))),
  };
}

/** Biggest first: where the work is, and where deleting costs the most. */
function sorted(openings: DerivedOpening[]): DerivedOpening[] {
  return openings.sort((a, b) => b.removes - a.removes || a.name.localeCompare(b.name));
}

function subtreeStats(
  rep: Repertoire,
  nodeId: string,
  ply: number,
): { moves: number; lines: number; depth: number } {
  const kids = childrenOf(rep, nodeId);
  if (!kids.length) return { moves: 1, lines: 1, depth: ply };
  let moves = 1;
  let lines = 0;
  let depth = ply;
  for (const kid of kids) {
    const below = subtreeStats(rep, kid.id, ply + 1);
    moves += below.moves;
    lines += below.lines;
    depth = Math.max(depth, below.depth);
  }
  return { moves, lines, depth };
}

/** "1.b3" — an opening the book has no name for, called after its first move. */
function moveLabel(path: string[]): string {
  const ply = path.length;
  const san = path[ply - 1];
  return `${Math.floor((ply - 1) / 2) + 1}.${ply % 2 === 1 ? '' : '..'}${san}`;
}
