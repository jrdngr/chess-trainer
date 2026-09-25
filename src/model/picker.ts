import { applySan, positionKey, START_FEN, type Color } from '../chess/core';
import { playerOf } from './onboarding';
import { approachOne, bookGraph, type BookGraph, type OpeningNode, type OpeningTree } from './openingTree';
import { familyName } from './reference';
import {
  BRANCH_SIDES,
  FAMILY_GROUPS,
  FAMILY_SHARPNESS,
  SHARPNESS_OVERRIDES,
  type GroupSpec,
  type Sharpness,
} from './pickerData';

/**
 * The opening picker's catalogue: the book's names arranged the way the book
 * spells them — Family: Branch, Line, Sub-line — rather than the way their move
 * orders nest.
 *
 * The opening tree (`openingTree.ts`) stays the source of truth for what a
 * selection *means*: every entry here points at one of its nodes, and picking
 * an entry selects that node. What this adds is the shape a player browses
 * by: families first, then their branches, then the lines under each — plus
 * hand-picked groups inside the dozen families too big to list flat, and a
 * sharpness and difficulty for everything.
 */

export interface PickerEntry {
  /** The full name this entry stands for: "Sicilian Defence: Najdorf Variation, English Attack". */
  key: string;
  /** The last part of the name: "English Attack". A family's label is the family. */
  label: string;
  family: string;
  /** 0 a family, 1 a branch, 2 and up a line. */
  level: number;
  /**
   * The opening tree node behind the entry. Where the book never names the
   * entry on its own — only lines under it — this is the shallowest of those,
   * and `exact` is false: selecting it would select that one line, not the
   * whole entry.
   */
  node: OpeningNode;
  exact: boolean;
  parent: PickerEntry | null;
  children: PickerEntry[];
  /** Games through the entry: its own node's, or its lines' when it has none. */
  games: number;
  /** Whose opening it is: the side picking it sets. A line takes its branch's. */
  side: Color;
  sharpness: Sharpness;
  /** 1 to 5, from how many lines the book says you would need to know. */
  difficulty: number;
}

export interface PickerGroup {
  id: string;
  label: string;
  family: string;
  entries: PickerEntry[];
  sharpness: Sharpness;
  /** A node to select for the whole group, where one position defines it. */
  node: OpeningNode | null;
  /** Other groups an entry can be reached from, by entry key. */
  alsoVia: Map<string, string[]>;
}

export type FirstMove = 'e4' | 'd4' | 'flank';

export interface PickerFamily {
  entry: PickerEntry;
  firstMove: FirstMove;
  /** Null for a family small enough to list its branches flat. */
  groups: PickerGroup[] | null;
}

export interface PickerCatalog {
  families: PickerFamily[];
  /** Every entry by its full name. */
  byKey: Map<string, PickerEntry>;
  /** The entry each exact node stands for. */
  byNode: Map<string, PickerEntry>;
  familyByName: Map<string, PickerFamily>;
}

const cache = new WeakMap<OpeningTree, PickerCatalog>();

export function pickerCatalog(tree: OpeningTree): PickerCatalog {
  const cached = cache.get(tree);
  if (cached) return cached;
  const built = buildCatalog(tree);
  cache.set(tree, built);
  return built;
}

/**
 * A name as the keys of every level it names, shallowest first.
 * "Sicilian Defence: Najdorf Variation, English Attack" is three levels deep.
 * A name with no colon is a family on its own, commas and all.
 */
export function nameLevels(family: string, name: string): string[] {
  const at = name.indexOf(': ');
  if (at < 0) return [family === name ? name : family, ...(family === name ? [] : [name])];
  const prefix = name.slice(0, at);
  const parts = name.slice(at + 2).split(', ');
  return [family, ...parts.map((_, i) => `${prefix}: ${parts.slice(0, i + 1).join(', ')}`)];
}

function labelOf(key: string, level: number): string {
  if (level === 0) return key;
  const at = key.indexOf(': ');
  const rest = at < 0 ? key : key.slice(at + 2);
  const parts = rest.split(', ');
  return parts[parts.length - 1];
}

function firstMoveOf(node: OpeningNode): FirstMove {
  const first = node.sans[0];
  return first === 'e4' ? 'e4' : first === 'd4' ? 'd4' : 'flank';
}

function buildCatalog(tree: OpeningTree): PickerCatalog {
  const index = tree.index;
  const byKey = new Map<string, PickerEntry>();

  // The node for each name: the shallowest, where the book reuses a name.
  const nodeByName = new Map<string, OpeningNode>();
  for (const node of tree.byId.values()) {
    if (node.depth === 0) continue;
    const seen = nodeByName.get(node.name);
    if (!seen || node.sans.length < seen.sans.length || (node.sans.length === seen.sans.length && node.games > seen.games)) {
      nodeByName.set(node.name, node);
    }
  }

  const ensure = (key: string, level: number, family: string, parent: PickerEntry | null): PickerEntry => {
    let entry = byKey.get(key);
    if (!entry) {
      const node = nodeByName.get(key);
      entry = {
        key,
        label: labelOf(key, level),
        family,
        level,
        node: node ?? tree.root,
        exact: Boolean(node),
        parent,
        children: [],
        games: node?.games ?? 0,
        side: 'w',
        sharpness: 3,
        difficulty: 3,
      };
      byKey.set(key, entry);
      parent?.children.push(entry);
    }
    return entry;
  };

  for (const name of nodeByName.keys()) {
    const family = familyName(index, name);
    const levels = nameLevels(family, name);
    let parent: PickerEntry | null = null;
    levels.forEach((key, level) => {
      parent = ensure(key, level, family, parent);
    });
  }

  // Entries the book only names through their lines borrow the shallowest line.
  const settle = (entry: PickerEntry) => {
    for (const child of entry.children) settle(child);
    if (!entry.exact) {
      const lines = entry.children.map((c) => c.node).filter((n) => n.depth > 0);
      const shallowest = lines.sort((a, b) => a.sans.length - b.sans.length || b.games - a.games)[0];
      if (shallowest) entry.node = shallowest;
      entry.games = entry.children.reduce((sum, child) => sum + child.games, 0);
    }
    entry.side = entry.node.depth > 0 ? playerOf(entry.node.sans) : 'w';
  };
  // A line is played from its branch's side. The English Attack is White's
  // move, but it is a Najdorf line, and whoever opens the Najdorf to pick it
  // is preparing to meet it with Black — flipping sides a level down would
  // undo the choice the branch just made. The Alapin, a branch, stays White's.
  const inherit = (entry: PickerEntry) => {
    if (entry.key in BRANCH_SIDES) entry.side = BRANCH_SIDES[entry.key];
    if (entry.level >= 2 && entry.parent) entry.side = entry.parent.side;
    for (const child of entry.children) inherit(child);
  };
  const roots = [...byKey.values()].filter((entry) => entry.level === 0);
  for (const root of roots) settle(root);
  for (const root of roots) inherit(root);

  const byNode = new Map<string, PickerEntry>();
  for (const entry of byKey.values()) if (entry.exact) byNode.set(entry.node.id, entry);

  const families: PickerFamily[] = roots.map((entry) => ({
    entry,
    firstMove: firstMoveOf(entry.node),
    groups: null,
  }));
  const familyByName = new Map(families.map((family) => [family.entry.key, family]));

  for (const family of families) {
    const split = FAMILY_GROUPS[family.entry.key];
    if (split) family.groups = groupFamily(tree, family.entry, split.groups, split.rest, split.restSharpness);
  }

  scoreSharpness(families);
  scoreDifficulty(tree, [...byKey.values()]);

  return { families, byKey, byNode, familyByName };
}

/* ── groups ─────────────────────────────────────────────────────────────── */

function keyAfter(sans: string): string | null {
  let fen = START_FEN;
  for (const san of sans.split(' ')) {
    const move = applySan(fen, san);
    if (!move) return null;
    fen = move.after;
  }
  return positionKey(fen);
}

function gamesAt(tree: OpeningTree, key: string): number {
  const entry = tree.index.entries.get(key);
  return entry ? entry.moves.reduce((sum, move) => sum + move.games, 0) : 0;
}

interface ResolvedGroup {
  spec: GroupSpec;
  keys: string[];
  games: number;
}

/**
 * Split a family's branches into its groups.
 *
 * By position, not move order: a branch goes to the group whose position it
 * passes through, the deepest if it passes through several (the Najdorf passes
 * 2.Nf3 on the way to the Open Sicilian, and is an Open Sicilian). A branch
 * whose own move order passes none goes to a group it can transpose from, the
 * most played if several. Any other group it can be reached from is noted as
 * "also via", so a transposition is shown rather than hidden.
 */
export function groupFamily(
  tree: OpeningTree,
  family: PickerEntry,
  specs: GroupSpec[],
  rest: string,
  restSharpness?: Sharpness,
): PickerGroup[] {
  const resolved: ResolvedGroup[] = specs.map((spec) => {
    const keys = spec.from.map(keyAfter).filter((key): key is string => key !== null);
    return { spec, keys, games: keys.reduce((sum, key) => sum + gamesAt(tree, key), 0) };
  });

  const members = new Map<ResolvedGroup | null, PickerEntry[]>();
  const reachable = new Map<PickerEntry, ResolvedGroup[]>();
  const homes = new Map<PickerEntry, ResolvedGroup | null>();
  for (const branch of family.children) {
    const path = branch.node.pathKeys;
    let home: ResolvedGroup | null = null;
    let deepest = -1;
    for (const group of resolved) {
      for (const key of group.keys) {
        const at = path.indexOf(key);
        if (at > deepest) {
          deepest = at;
          home = group;
        }
      }
    }
    const approach = approachOne(tree, branch.node);
    const via = resolved.filter(
      (group) => group.keys.some((key) => approach.has(key)) && !group.keys.some((key) => path.includes(key)),
    );
    if (!home) home = [...via].sort((a, b) => b.games - a.games)[0] ?? null;
    reachable.set(branch, via.filter((group) => group !== home));
    homes.set(branch, home);
    const list = members.get(home) ?? [];
    list.push(branch);
    members.set(home, list);
  }

  // A group of one is only a heading over its own branch: fold it into the rest.
  for (const group of resolved) {
    const list = members.get(group) ?? [];
    if (list.length === 1) {
      members.set(null, [...(members.get(null) ?? []), ...list]);
      members.delete(group);
    }
  }
  const kept = new Set(resolved.filter((group) => (members.get(group)?.length ?? 0) > 1));

  const out: PickerGroup[] = [];
  const familySharp = FAMILY_SHARPNESS[family.key] ?? 3;
  for (const group of [...resolved, null]) {
    if (group && !kept.has(group)) continue;
    const entries = members.get(group) ?? [];
    if (!entries.length) continue;
    const alsoVia = new Map<string, string[]>();
    for (const entry of entries) {
      const labels = (reachable.get(entry) ?? [])
        // A group that leads into this one's own position reaches every
        // branch in it, which says nothing about this branch in particular.
        .filter((other) => kept.has(other) && other !== group && !leadsInto(tree, other, homes.get(entry) ?? null))
        .sort((a, b) => b.games - a.games)
        .slice(0, 2)
        .map((other) => other.spec.label);
      if (labels.length) alsoVia.set(entry.key, labels);
    }
    const single = group && group.keys.length === 1 ? tree.byKey.get(group.keys[0]) : undefined;
    out.push({
      id: `${family.key}#${group ? group.spec.label : rest}`,
      label: group ? group.spec.label : rest,
      family: family.key,
      entries,
      sharpness: group ? group.spec.sharpness : (restSharpness ?? (familySharp as Sharpness)),
      node: single && familyName(tree.index, single.name) === family.key ? single : null,
      alsoVia,
    });
  }
  return out;
}

/** Can one group's position lead into another's? */
function leadsInto(tree: OpeningTree, from: ResolvedGroup, to: ResolvedGroup | null): boolean {
  if (!to) return false;
  const parents = bookGraph(tree.index).parents;
  const targets = new Set(from.keys);
  return to.keys.some((key) => {
    const seen = new Set<string>([key]);
    const queue = [key];
    while (queue.length) {
      const at = queue.pop()!;
      if (targets.has(at)) return true;
      for (const parent of parents.get(at) ?? []) {
        if (seen.has(parent)) continue;
        seen.add(parent);
        queue.push(parent);
      }
    }
    return false;
  });
}

/** The group a branch sits in, if its family is grouped. */
export function groupOf(family: PickerFamily, entry: PickerEntry): PickerGroup | null {
  if (!family.groups) return null;
  let branch: PickerEntry | null = entry;
  while (branch && branch.level > 1) branch = branch.parent;
  return family.groups.find((group) => branch && group.entries.includes(branch)) ?? null;
}

/* ── sharpness ──────────────────────────────────────────────────────────── */

const GAMBIT = /Gambit|Countergambit/;

function scoreSharpness(families: PickerFamily[]) {
  const visit = (entry: PickerEntry, inherited: Sharpness) => {
    let own = SHARPNESS_OVERRIDES[entry.key] ?? inherited;
    // A gambit is sharp whatever family it is played in, unless someone said
    // otherwise about this very line.
    if (!(entry.key in SHARPNESS_OVERRIDES) && entry.level > 0 && GAMBIT.test(entry.label) && !/Declined/.test(entry.label)) {
      own = Math.max(own, 4) as Sharpness;
    }
    entry.sharpness = own;
    for (const child of entry.children) visit(child, own);
  };
  for (const family of families) {
    const base = FAMILY_SHARPNESS[family.entry.key] ?? 3;
    family.entry.sharpness = SHARPNESS_OVERRIDES[family.entry.key] ?? base;
    for (const branch of family.entry.children) {
      const group = family.groups?.find((g) => g.entries.includes(branch));
      visit(branch, group ? group.sharpness : family.entry.sharpness);
    }
  }
}

/* ── difficulty ─────────────────────────────────────────────────────────── */

/** A reply needs an answer once it is played this often. */
const REPLY_SHARE = 0.1;
/** How far past the entry's own position the count looks, at most and at least. */
const MAX_PLIES = 14;
const MIN_PLIES = 4;

type ChildMap = BookGraph['children'];

/**
 * How many lines you would have to know to play an entry: one move of yours
 * at each of your turns (the most played), every reply that is played at
 * least 10% of the time at theirs, for as deep as the book names lines under
 * the entry. The count is what memorising the opening costs.
 */
export function theoryLines(
  children: ChildMap,
  key: string,
  side: Color,
  plies: number,
  memo = new Map<string, number>(),
): number {
  if (plies <= 0) return 1;
  const id = `${key}|${plies}|${side}`;
  const known = memo.get(id);
  if (known !== undefined) return known;
  const moves = children.get(key) ?? [];
  let count = 1;
  if (moves.length) {
    const turn = key.split(' ')[1] === 'b' ? 'b' : 'w';
    const sorted = [...moves].sort((a, b) => b.games - a.games);
    if (turn === side) {
      count = theoryLines(children, sorted[0].key, side, plies - 1, memo);
    } else {
      const total = sorted.reduce((sum, move) => sum + move.games, 0);
      const replies = sorted.filter((move, i) => i === 0 || move.games / Math.max(1, total) >= REPLY_SHARE);
      count = replies.reduce((sum, move) => sum + theoryLines(children, move.key, side, plies - 1, memo), 0);
    }
  }
  memo.set(id, count);
  return count;
}

function deepestPly(entry: PickerEntry): number {
  let deepest = entry.node.sans.length;
  for (const child of entry.children) deepest = Math.max(deepest, deepestPly(child));
  return deepest;
}

/**
 * Difficulty as a 1 to 5 bucket, ranked among entries at the same level so a
 * family is compared with families and a line with lines. Ranking rather than
 * fixed thresholds keeps all five buckets in use whatever the book holds.
 */
function scoreDifficulty(tree: OpeningTree, entries: PickerEntry[]) {
  const children = bookGraph(tree.index).children;
  const memo = new Map<string, number>();
  const raw = new Map<PickerEntry, number>();
  for (const entry of entries) {
    if (entry.node.depth === 0) continue;
    const plies = Math.max(MIN_PLIES, Math.min(MAX_PLIES, deepestPly(entry) - entry.node.sans.length));
    raw.set(entry, theoryLines(children, entry.node.key, entry.side, plies, memo));
  }
  const tiers = new Map<number, PickerEntry[]>();
  for (const entry of raw.keys()) {
    const tier = Math.min(entry.level, 2);
    tiers.set(tier, [...(tiers.get(tier) ?? []), entry]);
  }
  for (const list of tiers.values()) {
    const sorted = [...list].sort((a, b) => raw.get(a)! - raw.get(b)!);
    sorted.forEach((entry, i) => {
      // Ties share a bucket: the first of a run of equal counts decides it.
      let first = i;
      while (first > 0 && raw.get(sorted[first - 1]) === raw.get(entry)) first -= 1;
      entry.difficulty = 1 + Math.floor((first / sorted.length) * 5);
    });
  }
}

/* ── ordering ───────────────────────────────────────────────────────────── */

export type PickerSort = 'popular' | 'sharpest' | 'calmest' | 'easiest' | 'hardest';

export const PICKER_SORTS: { value: PickerSort; label: string }[] = [
  { value: 'popular', label: 'Popular' },
  { value: 'sharpest', label: 'Sharpest' },
  { value: 'calmest', label: 'Calmest' },
  { value: 'easiest', label: 'Easiest' },
  { value: 'hardest', label: 'Hardest' },
];

/** Starred first, whatever the sort; then the sort; then most played. */
export function sortEntries(entries: PickerEntry[], sort: PickerSort, starred: Iterable<string>): PickerEntry[] {
  const stars = new Set(starred);
  const metric = (entry: PickerEntry): number => {
    switch (sort) {
      case 'sharpest':
        return -entry.sharpness;
      case 'calmest':
        return entry.sharpness;
      case 'easiest':
        return entry.difficulty;
      case 'hardest':
        return -entry.difficulty;
      default:
        return 0;
    }
  };
  return [...entries].sort(
    (a, b) =>
      Number(stars.has(b.node.id) && b.exact) - Number(stars.has(a.node.id) && a.exact) ||
      metric(a) - metric(b) ||
      b.games - a.games ||
      a.label.localeCompare(b.label),
  );
}

/** The entry a tree node is shown as: its own, or the deepest named one around it. */
export function entryForNode(catalog: PickerCatalog, node: OpeningNode): PickerEntry | null {
  return catalog.byNode.get(node.id) ?? catalog.byKey.get(node.name) ?? null;
}

/** An entry and everything above it, family first. */
export function entryTrail(entry: PickerEntry): PickerEntry[] {
  const out: PickerEntry[] = [];
  let cursor: PickerEntry | null = entry;
  while (cursor) {
    out.unshift(cursor);
    cursor = cursor.parent;
  }
  return out;
}

/** The side picking a tree node sets: its entry's, or none for "any opening". */
export function sideForPick(catalog: PickerCatalog, node: OpeningNode): Color | null {
  if (node.depth === 0) return null;
  return entryForNode(catalog, node)?.side ?? playerOf(node.sans);
}
