import { applySan, positionKey, START_FEN } from '../chess/core';
import { familyName, lookup, nameAt, type ReferenceIndex } from './reference';

/**
 * The opening tree: every named opening the book knows, nested the way a
 * player thinks about them.
 *
 * The root is "any opening". Under it sit the first moves, ordered by how often
 * they are played; under each first move the families (Sicilian, King's
 * Indian); under each family its variations, as deep as the names go. The
 * Najdorf branch is four deep, the Dutch two, and the picker simply follows.
 *
 * Nesting is decided by moves first and names second. An opening whose move
 * order extends another's is that opening's variation, which is how "Najdorf:
 * Poisoned Pawn" lands under "Najdorf: Main Line, 6.Bg5". Where the moves say
 * nothing — the Fianchetto King's Indian never passes through the position the
 * book names "King's Indian Defence" — the family the name belongs to decides.
 *
 * A node is a *region* of theory: selecting it means "anything that goes
 * through here". That test is done on positions rather than move orders, so a
 * line that transposes into the Najdorf is inside the Najdorf. And "here" is
 * the node's position or any variation's under it: the Fianchetto King's
 * Indian never passes the position the book names "King's Indian Defence",
 * nor does 4.Nf3 O-O 5.e4 d6, and both are King's Indians — the picker says
 * so by nesting them there, and the region agrees.
 */
export interface OpeningNode {
  /** The defining move order, space-joined. The root's id is ''. */
  id: string;
  name: string;
  eco?: string;
  sans: string[];
  /** Position key at the end of `sans`. */
  key: string;
  /** Keys of every position along `sans`, the last included. */
  pathKeys: string[];
  /** Games in the sample that reached the position. */
  games: number;
  /** 0 for the root, 1 for a first move, 2 for a family, 3 and up for variations. */
  depth: number;
  parentId: string | null;
  children: OpeningNode[];
}

export interface OpeningTree {
  root: OpeningNode;
  byId: Map<string, OpeningNode>;
  /** The deepest node at each position, for naming a line by where it goes. */
  byKey: Map<string, OpeningNode>;
  /** The book the tree was built from, for asking what leads where. */
  index: ReferenceIndex;
}

export const ANY_OPENING = '';

const cache = new WeakMap<ReferenceIndex, OpeningTree>();

/** Built once per reference index. */
export function openingTree(index: ReferenceIndex): OpeningTree {
  const cached = cache.get(index);
  if (cached) return cached;
  const built = buildOpeningTree(index);
  cache.set(index, built);
  return built;
}

function walkKeys(sans: string[]): { keys: string[]; legal: boolean } {
  let fen = START_FEN;
  const keys: string[] = [];
  for (const san of sans) {
    const move = applySan(fen, san);
    if (!move) return { keys, legal: false };
    fen = move.after;
    keys.push(positionKey(fen));
  }
  return { keys, legal: true };
}

function makeNode(
  sans: string[],
  name: string,
  eco: string | undefined,
  games: number,
  parentId: string | null,
): OpeningNode | null {
  const { keys, legal } = walkKeys(sans);
  if (!legal) return null;
  return {
    id: sans.join(' '),
    name,
    eco,
    sans,
    key: keys[keys.length - 1] ?? positionKey(START_FEN),
    pathKeys: keys,
    games,
    depth: 0,
    parentId,
    children: [],
  };
}

/** "1.e4", "1...c5" — a move named after itself. */
export function moveLabel(sans: string[]): string {
  const ply = sans.length;
  return `${Math.floor((ply - 1) / 2) + 1}.${ply % 2 === 1 ? '' : '..'}${sans[ply - 1]}`;
}

export function buildOpeningTree(index: ReferenceIndex): OpeningTree {
  const root: OpeningNode = {
    id: ANY_OPENING,
    name: 'Any opening',
    sans: [],
    key: positionKey(START_FEN),
    pathKeys: [],
    games: index.totalGames,
    depth: 0,
    parentId: null,
    children: [],
  };
  const byId = new Map<string, OpeningNode>([[root.id, root]]);

  /** A first move, created from the database root or on demand. */
  const firstMove = (san: string, games: number): OpeningNode => {
    const found = byId.get(san);
    if (found) return found;
    const after = applySan(START_FEN, san);
    const named = after ? nameAt(index, after.after) : null;
    const node = makeNode([san], named?.name ?? moveLabel([san]), named?.eco, games, root.id);
    if (!node) throw new Error(`Illegal first move ${san}`);
    byId.set(node.id, node);
    return node;
  };
  for (const move of lookup(index, START_FEN)?.moves ?? []) firstMove(move.san, move.games);

  // Every catalogue entry becomes a node before any parent is decided, so a
  // parent can be found whichever order the catalogue lists them in.
  const entries = index.catalogue
    .map((entry) => makeNode(entry.sans, entry.name, entry.eco, entry.games, null))
    .filter((node): node is OpeningNode => node !== null);
  for (const node of entries) byId.set(node.id, node);
  const byName = new Map(entries.map((node) => [node.name, node]));

  const extendsPath = (longer: string[], shorter: string[]) =>
    longer.length > shorter.length && shorter.every((san, i) => longer[i] === san);

  for (const node of entries) {
    // Moves first: the deepest opening whose move order this one extends.
    let parent: OpeningNode | null = null;
    for (const other of entries) {
      if (other === node || !extendsPath(node.sans, other.sans)) continue;
      if (!parent || other.sans.length > parent.sans.length) parent = other;
    }
    // Names second, and not only as a fallback: containment by move order is
    // not the same as belonging.
    //
    // A King's Indian Fianchetto goes 1.d4 Nf6 2.c4 g6 3.Nf3, which never
    // reaches the position the book names the King's Indian Defence by, so its
    // deepest containing move order is a West Indian Defence — another family.
    // Filing it there would put a King's Indian outside the King's Indian, and
    // a region is meant to be a family and every variation under it, by any
    // road in.
    //
    // The reverse mismatch is left alone. The Grünfeld extends the move order
    // the book names the King's Indian by and is nobody's King's Indian, but
    // nothing structural separates that from the Ruy López extending the King's
    // Knight Opening, which is filed exactly right. It is an artefact of the
    // book naming 1.d4 Nf6 2.c4 g6 3.Nc3 after a defence Black has not yet
    // committed to, and it is better lived with than guessed at.
    const family = familyName(index, node.name);
    if (family !== node.name && (!parent || familyName(index, parent.name) !== family)) {
      const named = byName.get(family);
      if (named && named !== node && !extendsPath(named.sans, node.sans)) parent = named;
    }
    node.parentId = (parent ?? firstMove(node.sans[0], 0)).id;
  }

  // A name-derived parent could in principle chain back round; cut any loop
  // at the first move rather than trusting the data never to do it.
  for (const node of entries) {
    const seen = new Set<string>([node.id]);
    let cursor = node;
    while (cursor.parentId !== null && cursor.parentId !== root.id) {
      if (seen.has(cursor.parentId)) {
        node.parentId = firstMove(node.sans[0], 0).id;
        break;
      }
      seen.add(cursor.parentId);
      cursor = byId.get(cursor.parentId)!;
    }
  }

  for (const node of byId.values()) {
    if (node === root) continue;
    byId.get(node.parentId ?? root.id)!.children.push(node);
  }

  const sortChildren = (node: OpeningNode, depth: number) => {
    node.depth = depth;
    node.children.sort((a, b) => b.games - a.games || a.name.localeCompare(b.name));
    for (const child of node.children) sortChildren(child, depth + 1);
  };
  sortChildren(root, 0);

  const byKey = new Map<string, OpeningNode>();
  for (const node of byId.values()) {
    const existing = byKey.get(node.key);
    if (!existing || node.depth > existing.depth) byKey.set(node.key, node);
  }

  return { root, byId, byKey, index };
}

/** The node with this id, or the root for '' and for an id the tree lacks. */
export function nodeById(tree: OpeningTree, id: string): OpeningNode {
  return tree.byId.get(id) ?? tree.root;
}

/** The node and everything above it, the root excluded, shallowest first. */
export function ancestorsOf(tree: OpeningTree, id: string): OpeningNode[] {
  const out: OpeningNode[] = [];
  let cursor: OpeningNode | undefined = tree.byId.get(id);
  while (cursor && cursor.depth > 0) {
    out.unshift(cursor);
    cursor = cursor.parentId === null ? undefined : tree.byId.get(cursor.parentId);
  }
  return out;
}

/** Starred first, then most played — the order at every level of the picker. */
export function orderedChildren(node: OpeningNode, starred: Iterable<string>): OpeningNode[] {
  const stars = new Set(starred);
  return [...node.children].sort(
    (a, b) =>
      Number(stars.has(b.id)) - Number(stars.has(a.id)) ||
      b.games - a.games ||
      a.name.localeCompare(b.name),
  );
}

/** Every node under this one, itself excluded, in picker order. */
export function descendantsOf(node: OpeningNode): OpeningNode[] {
  const out: OpeningNode[] = [];
  const visit = (n: OpeningNode) => {
    for (const child of n.children) {
      out.push(child);
      visit(child);
    }
  };
  visit(node);
  return out;
}

/** Is this node, or any opening it sits inside, starred? */
export function starredWithin(tree: OpeningTree, id: string, starred: Iterable<string>): boolean {
  const stars = new Set(starred);
  return ancestorsOf(tree, id).some((node) => stars.has(node.id));
}

/* ── regions ────────────────────────────────────────────────────────────── */

/**
 * Where a line stands relative to a region.
 *
 * `reached`: the line passes through the node's position, so everything after
 * is inside the region. `onWay`: the book still has a route from here to that
 * position, so the line can still get there. `outside`: it cannot.
 */
export type LineStatus = 'reached' | 'onWay' | 'outside';

const approaches = new WeakMap<OpeningNode, Set<string>>();

/**
 * Every position the book can reach one node's own position from.
 *
 * Walked backwards through the reference database rather than read off the
 * node's own move order, so a transposition counts: 1.c4 Nf6 2.Nc3 g6 3.e4 is
 * on the way to the King's Indian even though the book names it from 1.d4. The
 * node's own path is included regardless, since a rarely played opening may
 * have a move order the database never authored a continuation for.
 */
function approachOne(tree: OpeningTree, node: OpeningNode): Set<string> {
  const cached = approaches.get(node);
  if (cached) return cached;
  const parents = parentMap(tree.index);
  const out = new Set<string>(node.pathKeys);
  // Every position along the path is walked back from, not only the last:
  // a line can transpose into the path partway along, and a position seeded
  // as already found would otherwise never have its own parents looked at.
  const queue = [...node.pathKeys];
  while (queue.length) {
    const key = queue.pop()!;
    for (const parent of parents.get(key) ?? []) {
      if (out.has(parent)) continue;
      out.add(parent);
      queue.push(parent);
    }
  }
  approaches.set(node, out);
  return out;
}

interface Region {
  /** The positions that are the region: the node's own, and every variation's under it. */
  inside: Set<string>;
  /** Every position the book can reach one of those from. */
  approach: Set<string>;
}

const regions = new WeakMap<OpeningNode, Region>();

/**
 * What a node is as a region: its own position and its variations' — reaching
 * any of them is reaching the opening — and everything the book can get to
 * one of them from.
 *
 * The variations matter because a family is named by one position and played
 * through many. The Fianchetto King's Indian sits under the King's Indian in
 * the picker and never passes the position the family is named by; the
 * Classical reached by 4.Nf3 O-O 5.e4 d6 skips it too. Reading the family as
 * its one position alone would have the opponent refuse those move orders
 * with the family selected, and the scorer count the lines as no one's.
 */
export function regionOf(tree: OpeningTree, node: OpeningNode): Region {
  const cached = regions.get(node);
  if (cached) return cached;
  const members = [node, ...descendantsOf(node)];
  const inside = new Set(members.map((member) => member.key));
  const approach = new Set<string>();
  for (const member of members) for (const key of approachOne(tree, member)) approach.add(key);
  const out = { inside, approach };
  regions.set(node, out);
  return out;
}

/** Every position the book can reach the region from — see `regionOf`. */
export function approachKeys(tree: OpeningTree, node: OpeningNode): Set<string> {
  return regionOf(tree, node).approach;
}

const parentMaps = new WeakMap<ReferenceIndex, Map<string, string[]>>();

/** For every position in the book, the positions one move before it. */
function parentMap(index: ReferenceIndex): Map<string, string[]> {
  const cached = parentMaps.get(index);
  if (cached) return cached;
  const out = new Map<string, string[]>();
  const visit = (fen: string, seen: Set<string>) => {
    const key = positionKey(fen);
    if (seen.has(key)) return;
    seen.add(key);
    for (const move of lookup(index, fen)?.moves ?? []) {
      const applied = applySan(fen, move.san);
      if (!applied) continue;
      const child = positionKey(applied.after);
      const list = out.get(child) ?? [];
      if (!list.includes(key)) list.push(key);
      out.set(child, list);
      visit(applied.after, seen);
    }
  };
  visit(START_FEN, new Set());
  parentMaps.set(index, out);
  return out;
}

export function lineStatus(tree: OpeningTree, node: OpeningNode, sans: string[]): LineStatus {
  if (node.depth === 0) return 'reached';
  const { inside, approach } = regionOf(tree, node);
  let fen = START_FEN;
  for (const san of sans) {
    const move = applySan(fen, san);
    if (!move) return 'outside';
    fen = move.after;
    const key = positionKey(fen);
    if (inside.has(key)) return 'reached';
    if (!approach.has(key)) return 'outside';
  }
  return 'onWay';
}

/** Can a line still be part of this region? */
export function insideRegion(tree: OpeningTree, node: OpeningNode, sans: string[]): boolean {
  return lineStatus(tree, node, sans) !== 'outside';
}

/**
 * The deepest opening a line goes through — what it is called, and where its
 * score goes. Null when the book names nothing along it.
 */
export function deepestNodeAlong(tree: OpeningTree, sans: string[]): OpeningNode | null {
  let best: OpeningNode | null = null;
  let fen = START_FEN;
  for (const san of sans) {
    const move = applySan(fen, san);
    if (!move) break;
    fen = move.after;
    const found = tree.byKey.get(positionKey(fen));
    if (found && (!best || found.depth >= best.depth)) best = found;
  }
  return best;
}

/**
 * The deepest opening inside `within` that a line goes through, for steering a
 * game toward one variation of a wider selection. Falls back to `within`.
 */
export function deepestNodeWithin(
  tree: OpeningTree,
  within: OpeningNode,
  sans: string[],
): OpeningNode {
  const deepest = deepestNodeAlong(tree, sans);
  if (!deepest) return within;
  return ancestorsOf(tree, deepest.id).some((node) => node.id === within.id) || within.depth === 0
    ? deepest
    : within;
}

/**
 * Which of several regions a line belongs to, from one walk of the line.
 *
 * `lineStatus` answers for one node; the recommendation engine asks for every
 * node under the selection at once, for every line in the repertoire, and
 * walking the line once per node would be the slow part of the whole app.
 */
export function regionsOf(
  tree: OpeningTree,
  nodes: OpeningNode[],
  sans: string[],
): Map<string, LineStatus> {
  const out = new Map<string, LineStatus>();
  const keys: string[] = [];
  let fen = START_FEN;
  let legal = true;
  for (const san of sans) {
    const move = applySan(fen, san);
    if (!move) {
      legal = false;
      break;
    }
    fen = move.after;
    keys.push(positionKey(fen));
  }
  const last = keys[keys.length - 1] ?? positionKey(START_FEN);
  for (const node of nodes) {
    if (node.depth === 0) {
      out.set(node.id, 'reached');
      continue;
    }
    if (!legal) {
      out.set(node.id, 'outside');
      continue;
    }
    const { inside, approach } = regionOf(tree, node);
    const at = keys.findIndex((key) => inside.has(key));
    if (at >= 0) {
      // Reached, provided every position before it was on the way.
      const clean = keys.slice(0, at).every((key) => approach.has(key));
      out.set(node.id, clean ? 'reached' : 'outside');
      continue;
    }
    out.set(node.id, keys.every((key) => approach.has(key)) && (keys.length === 0 || approach.has(last)) ? 'onWay' : 'outside');
  }
  return out;
}
