import type { Color } from '../chess/core';
import { familyName, nameAt, type ReferenceIndex } from './reference';
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
  /**
   * Roots of other openings that sit inside this one's subtree and are listed
   * on their own: a King's Indian under the Indian Defence's 1...Nf6. Their
   * moves are not this opening's, so they are left out of its lines, its
   * counts, and what deleting it takes.
   */
  nested?: string[];
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
  const openings = collapse(regionsOf(rep, index));
  if (rep.color === 'b') nameForBlack(openings, index);
  return sorted(openings.map((region) => finish(rep, region)));
}

/** Every named region of a tree, nested as the book names them, before anything is dropped. */
function regionsOf(rep: Repertoire, index: ReferenceIndex): Region[] {
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
  return tops;
}

/**
 * The Playbook's rows: one per opening family, "Sicilian Defence" however
 * deep the lines under it go.
 *
 * `openingsIn` names an opening after the deepest name its lines share, so a
 * Sicilian that grew one Najdorf line was listed as the Najdorf, and renamed
 * again as soon as a second line went in. A family stays put. Each region
 * joins the row of the family it belongs to; a region of another family
 * starts its own row, even inside one — the King's Indian under the Indian
 * Defence's 1...Nf6 is its own family in the book, and its own row here. A
 * row with no lines of its own (the 1.d4 a King's Indian passes through) is
 * only a way in, and is not listed.
 */
export function familiesIn(rep: Repertoire, index: ReferenceIndex): DerivedOpening[] {
  interface Row {
    name: string;
    eco?: string;
    rootId: string;
    path: string[];
    ownLines: number;
    nested: string[];
  }
  const rows: Row[] = [];
  const visit = (region: Region, row: Row | null) => {
    const family = familyName(index, region.name);
    let here = row;
    if (!here || family !== here.name) {
      here = { name: family, rootId: region.rootId, path: region.path, ownLines: 0, nested: [] };
      row?.nested.push(region.rootId);
      rows.push(here);
    }
    // The ECO of the family's own position, where the tree passes through it.
    if (region.name === family || here.eco === undefined) here.eco = region.eco ?? here.eco;
    here.ownLines += region.ownLines;
    for (const child of region.children) visit(child, here);
  };
  for (const region of regionsOf(rep, index)) visit(region, null);

  const listed = rows.filter((row) => row.ownLines > 0);
  if (rep.color === 'b') nameForBlack(listed, index);
  return sorted(
    listed.map((row) => {
      const skip = new Set(row.nested);
      const stats = subtreeStats(rep, row.rootId, row.path.length, skip);
      return {
        id: `${rep.id}#${row.rootId}`,
        repertoireId: rep.id,
        color: rep.color,
        name: row.name,
        eco: row.eco,
        rootId: row.rootId,
        path: row.path,
        moves: stats.moves,
        removes: row.nested.length ? removedWith(rep, stats.tips) : pruneCount(rep, row.rootId),
        lines: stats.lines,
        depth: stats.depth,
        variations: [],
        ...(row.nested.length ? { nested: row.nested } : {}),
      };
    }),
  );
}

/**
 * Whether a node belongs to an opening: inside its subtree but not in one
 * nested in it, or on the move order that leads to it.
 */
export function holdsNode(rep: Repertoire, opening: DerivedOpening, nodeId: string): boolean {
  const nested = new Set(opening.nested ?? []);
  let inside = false;
  for (let id: string | null = nodeId; id; id = rep.nodes[id]?.parentId ?? null) {
    if (nested.has(id)) return false;
    if (id === opening.rootId) {
      inside = true;
      break;
    }
  }
  if (inside) return true;
  for (let id: string | null = opening.rootId; id; id = rep.nodes[id]?.parentId ?? null) if (id === nodeId) return true;
  return false;
}

/** The ends of every line an opening holds, leaving out the openings nested in it. */
export function tipsOf(rep: Repertoire, opening: DerivedOpening): string[] {
  return subtreeStats(rep, opening.rootId, opening.path.length, new Set(opening.nested ?? [])).tips;
}

/** How many moves go when these lines are deleted: every move all of whose lines are among them. */
function removedWith(rep: Repertoire, tips: string[]): number {
  const gone = new Set(tips);
  let count = 0;
  const visit = (node: RepMove): boolean => {
    const kids = childrenOf(rep, node.id);
    let all = kids.length ? true : gone.has(node.id);
    for (const kid of kids) if (!visit(kid)) all = false;
    if (all) count += 1;
    return all;
  };
  for (const root of childrenOf(rep, null)) visit(root);
  return count;
}

/**
 * The book's names for the White openings Black meets without naming a
 * defense of its own: 1.e4 e5 2.Nf3 Nc6 is "King's Knight Opening: Normal
 * Variation", which is what White did, and a Black Playbook holding 1...e5
 * listed it under that name. The `collapse` rules are right about where the
 * opening starts and only the name is wrong, so these are called after Black's
 * first move instead. Only when that is unambiguous: two of them under one
 * first move keep their book names, which at least tell them apart.
 */
const WHITE_NAMES = new Set(["King's Pawn Game", "King's Knight Opening", "Queen's Pawn Game", 'Zukertort Opening']);

function nameForBlack(openings: { name: string; path: string[] }[], index: ReferenceIndex) {
  const renamed = openings
    .filter((region) => region.path.length >= 2 && WHITE_NAMES.has(familyName(index, region.name)))
    .map((region) => ({ region, label: moveLabel(region.path.slice(0, 2)) }));
  const counts = new Map<string, number>();
  for (const { label } of renamed) counts.set(label, (counts.get(label) ?? 0) + 1);
  for (const { region, label } of renamed) if (counts.get(label) === 1) region.name = label;
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
  skip: Set<string> = new Set(),
): { moves: number; lines: number; depth: number; tips: string[] } {
  const all = childrenOf(rep, nodeId);
  if (!all.length) return { moves: 1, lines: 1, depth: ply, tips: [nodeId] };
  // Only the way into an opening listed on its own: a move, but no line.
  const kids = all.filter((kid) => !skip.has(kid.id));
  if (!kids.length) return { moves: 1, lines: 0, depth: 0, tips: [] };
  let moves = 1;
  let lines = 0;
  let depth = ply;
  const tips: string[] = [];
  for (const kid of kids) {
    const below = subtreeStats(rep, kid.id, ply + 1, skip);
    moves += below.moves;
    lines += below.lines;
    depth = Math.max(depth, below.depth);
    tips.push(...below.tips);
  }
  return { moves, lines, depth, tips };
}

/** "1.b3" — an opening the book has no name for, called after its first move. */
function moveLabel(path: string[]): string {
  const ply = path.length;
  const san = path[ply - 1];
  return `${Math.floor((ply - 1) / 2) + 1}.${ply % 2 === 1 ? '' : '..'}${san}`;
}

/** One line of an opening: a path from the start to a move with nothing after it. */
export interface OpeningLine {
  /** The last move of the line. */
  tipId: string;
  path: string[];
  /** The deepest book name the line reaches, without the opening's own name in front. */
  name: string;
  /** "5.Re1": where it parts from a line with the same name, when one has it. */
  split?: string;
  /**
   * Moves only this line owns: what deleting it removes. Climbs past the
   * opening's first move when this is its only line, since then the opening
   * goes with it.
   */
  removes: number;
}

/**
 * Every line of one opening, in tree order, each named for where it goes.
 *
 * Two lines often reach the same deepest name and only part ways later; those
 * get the move they split off at, which is what tells them apart at a glance.
 */
export function linesOf(rep: Repertoire, opening: DerivedOpening, index: ReferenceIndex): OpeningLine[] {
  const root = rep.nodes[opening.rootId];
  if (!root) return [];
  const raw: { tipId: string; path: string[]; name: string; split: number }[] = [];

  const nested = new Set(opening.nested ?? []);
  const visit = (node: RepMove, path: string[], name: string) => {
    const here = [...path, node.san];
    const named = nameAt(index, node.fenAfter)?.name ?? name;
    const all = childrenOf(rep, node.id);
    const kids = all.filter((kid) => !nested.has(kid.id));
    if (!all.length) {
      raw.push({ tipId: node.id, path: here, name: named, split: splitPly(rep, node.id) });
      return;
    }
    for (const kid of kids) visit(kid, here, named);
  };
  visit(root, opening.path.slice(0, -1), opening.name);

  const counts = new Map<string, number>();
  for (const line of raw) counts.set(line.name, (counts.get(line.name) ?? 0) + 1);
  return raw.map((line) => {
    const base = shortName(line.name, opening.name);
    const clash = (counts.get(line.name) ?? 0) > 1 && line.split > 0;
    return {
      tipId: line.tipId,
      path: line.path,
      name: base,
      ...(clash ? { split: moveLabel(line.path.slice(0, line.split)) } : {}),
      removes: pruneCount(rep, line.tipId),
    };
  });
}

/** "Ruy Lopez: Berlin Defence" under the Ruy Lopez reads "Berlin Defence". */
function shortName(name: string, family: string): string {
  if (name === family) return name;
  for (const sep of [': ', ', ']) {
    if (name.startsWith(family + sep)) return name.slice(family.length + sep.length);
  }
  // A variation's own name repeats only the family, e.g. "Ruy Lopez: Closed, Delayed Exchange" under "Ruy Lopez: Closed".
  const colon = family.indexOf(': ');
  if (colon > 0 && name.startsWith(family.slice(0, colon + 2))) return name.slice(colon + 2);
  return name;
}

/** Ply of the first move only this line has: where it parts from the others. */
function splitPly(rep: Repertoire, tipId: string): number {
  let ply = 0;
  for (let id: string | null = tipId; id; id = rep.nodes[id]?.parentId ?? null) ply += 1;
  let childId = tipId;
  let parentId = rep.nodes[tipId]?.parentId ?? null;
  while (parentId) {
    const parent = rep.nodes[parentId];
    if (!parent || parent.children.some((id) => id !== childId)) break;
    ply -= 1;
    childId = parentId;
    parentId = parent.parentId;
  }
  return ply;
}
