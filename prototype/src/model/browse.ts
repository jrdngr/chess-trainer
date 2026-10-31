import { applySan, positionKey, START_FEN, walkSan, type Color } from '../chess/core';
import { openingsIn, linesOf, type DerivedOpening } from './openings';
import { bookGraph, deepestNodeAlong, moveLabel, type OpeningNode, type OpeningTree } from './openingTree';
import { entryForNode, entryTrail, sideForPick, type PickerCatalog, type PickerEntry } from './picker';
import { lookup, type ReferenceIndex } from './reference';
import { childrenOf } from './repertoire';
import type { ScoreState } from './scoring';
import { structureOf } from './structures';
import type { Repertoire, RepMove } from './types';
import { env } from './env';

/**
 * What the opening picker lists below its board.
 *
 * Every list is rows that stand for a line: tapping one plays the line out on
 * the board, and a row with rows under it opens them. The picker selects what
 * is on the board, so a row is only ever a way to get the board somewhere.
 */

export type ReasonKind = 'hole' | 'like' | 'style';

export interface BrowseRow {
  /** Unique within its list. */
  key: string;
  label: string;
  sans: string[];
  side: Color;
  /** The rows under this one, built when it is opened. */
  open?: () => BrowseItem[];
  /** Why a suggestion is suggested. */
  why?: { text: string; kind: ReasonKind };
}

export type BrowseItem = BrowseRow | { head: string };

export function isHead(item: BrowseItem): item is { head: string } {
  return 'head' in item;
}

/** "Najdorf" for "Najdorf Variation": the word every opening has is noise in a list. */
export function shortName(label: string): string {
  return label.replace(/ (Defence|Variation|Opening|Game)$/, '') || label;
}

/** The name a line shows under: the book's deepest name along it, as the picker spells it. */
export function lineName(tree: OpeningTree, catalog: PickerCatalog, sans: string[]): string {
  if (!sans.length) return 'Any opening';
  const node = tree.byId.get(sans.join(' ')) ?? deepestNodeAlong(tree, sans);
  if (!node) return moveLabel(sans);
  const entry = entryForNode(catalog, node);
  if (!entry) return node.name;
  const trail = entryTrail(entry).map((e) => shortName(e.label));
  return trail.length > 1 ? `${trail[0]}: ${trail[trail.length - 1]}` : trail[0];
}

/* ── book ───────────────────────────────────────────────────────────────── */

function entryRow(catalog: PickerCatalog, entry: PickerEntry): BrowseRow {
  const family = entry.level === 0 ? catalog.familyByName.get(entry.key) : null;
  const groups = family?.groups;
  const open = groups
    ? () =>
        groups.map((group): BrowseRow => ({
          key: `group:${group.id}`,
          label: group.label,
          sans: group.node?.sans ?? entry.node.sans,
          side: entry.side,
          open: () => group.entries.map((e) => entryRow(catalog, e)),
        }))
    : entry.children.length
      ? () => entry.children.map((child) => entryRow(catalog, child))
      : undefined;
  return { key: entry.key, label: entry.label, sans: entry.node.sans, side: entry.side, open };
}

const FIRST_MOVES: { id: 'e4' | 'd4' | 'flank'; head: string }[] = [
  { id: 'e4', head: '1.e4' },
  { id: 'd4', head: '1.d4' },
  { id: 'flank', head: 'Flank openings' },
];

/** Every family, under its first move, most played first. */
export function bookItems(catalog: PickerCatalog): BrowseItem[] {
  const out: BrowseItem[] = [];
  for (const { id, head } of FIRST_MOVES) {
    out.push({ head });
    const families = catalog.families
      .filter((family) => family.firstMove === id)
      .sort((a, b) => b.entry.games - a.entry.games);
    for (const family of families) out.push(entryRow(catalog, family.entry));
  }
  return out;
}

/* ── shelves ────────────────────────────────────────────────────────────── */

export interface Shelf {
  id: string;
  label: string;
  color: string;
  /** Catalogue keys: families or branches. */
  keys: string[];
}

export const SHELVES: Shelf[] = [
  {
    id: 'gambits',
    label: 'Gambits',
    color: '#f97316',
    keys: [
      "King's Gambit",
      'Danish Gambit',
      'Italian Game: Evans Gambit',
      'Italian Game: Scotch Gambit',
      'Sicilian Defence: Smith-Morra Gambit',
      'Sicilian Defence: Wing Gambit',
      'Blackmar-Diemer Gambit',
      'Benko Gambit',
      'Indian Defence: Budapest Gambit',
      "Queen's Gambit Declined: Albin Countergambit",
      'Ruy Lopez: Marshall Attack',
      'Elephant Gambit',
      'Latvian Gambit',
      'Englund Gambit',
      "Petrov's Defence: Stafford Gambit",
    ],
  },
  {
    id: 'systems',
    label: 'Systems',
    color: '#3b82f6',
    keys: [
      'London System',
      "Queen's Pawn Game: Colle System",
      "King's Indian Attack",
      'Torre Attack',
      'Trompowsky Attack',
      'Rapport-Jobava System',
      'Yusupov-Rubinstein System',
      'Catalan Opening',
      'Hippopotamus Defence',
      'Modern Defence',
      'Pirc Defence',
    ],
  },
  {
    id: 'solid',
    label: 'Solid',
    color: '#2dd4bf',
    keys: [
      'Caro-Kann Defence',
      'Slav Defence',
      "Queen's Gambit Declined",
      "Petrov's Defence",
      'Ruy Lopez: Berlin Defence',
      "Queen's Indian Defence",
      'Philidor Defence',
      'Italian Game: Giuoco Pianissimo',
      'Bogo-Indian Defence',
      'London System',
    ],
  },
  {
    id: 'sharp',
    label: 'Sharp',
    color: '#ef4444',
    keys: [
      'Sicilian Defence: Najdorf Variation',
      'Sicilian Defence: Dragon Variation',
      'Sicilian Defence: Lasker-Pelikan Variation',
      'Sicilian Defence: Sozin Attack',
      "King's Indian Defence",
      'Grünfeld Defence',
      'Benoni Defence: Modern Variation',
      'Semi-Slav Defence',
      'French Defence: Winawer Variation',
      'Dutch Defence',
      'Ruy Lopez: Schliemann Defence',
      "King's Gambit",
    ],
  },
  {
    id: 'classical',
    label: 'Classical',
    color: '#facc15',
    keys: [
      'Ruy Lopez',
      'Italian Game: Giuoco Piano',
      "Queen's Gambit",
      "Queen's Gambit Declined",
      'Four Knights Game',
      'Scotch Game',
      'Vienna Game',
      'Nimzo-Indian Defence: Classical Variation',
      'French Defence: Classical Variation',
      'Caro-Kann Defence: Classical Variation',
      'Pirc Defence: Classical Variation',
    ],
  },
  {
    id: 'hypermodern',
    label: 'Hypermodern',
    color: '#a855f7',
    keys: [
      'Réti Opening',
      'English Opening',
      "King's Indian Defence",
      'Grünfeld Defence',
      'Nimzo-Indian Defence',
      "Queen's Indian Defence",
      'Bogo-Indian Defence',
      'Alekhine Defence',
      'Pirc Defence',
      'Modern Defence',
      'Catalan Opening',
      'Nimzo-Larsen Attack',
    ],
  },
  {
    id: 'offbeat',
    label: 'Offbeat',
    color: '#4ade80',
    keys: [
      'Bird Opening',
      'Polish Opening',
      'Grob Opening',
      'Hungarian Opening',
      'Van Geet Opening',
      'Nimzowitsch Defence',
      'Owen Defence',
      'St. George Defence',
      'English Defence',
      'Scandinavian Defence',
      'Center Game',
      'Ponziani Opening',
      "Bishop's Opening",
      'Richter-Veresov Attack',
    ],
  },
  {
    id: 'trappy',
    label: 'Trappy',
    color: '#ec4899',
    keys: [
      "Petrov's Defence: Stafford Gambit",
      'Englund Gambit',
      'Elephant Gambit',
      'Latvian Gambit',
      'Italian Game: Two Knights Defence',
      'Indian Defence: Budapest Gambit',
      "Queen's Gambit Declined: Albin Countergambit",
      'Blackmar-Diemer Gambit',
      'Danish Gambit',
      'Center Game',
      'Vienna Game',
      'Sicilian Defence: Smith-Morra Gambit',
      'Italian Game: Evans Gambit',
      'Ruy Lopez: Schliemann Defence',
    ],
  },
];

/** A shelf's openings, as rows; names the book has since lost are left out. */
export function shelfRows(catalog: PickerCatalog, shelf: Shelf): BrowseRow[] {
  return shelf.keys
    .map((key) => catalog.byKey.get(key))
    .filter((entry): entry is PickerEntry => Boolean(entry))
    .map((entry) => ({ ...entryRow(catalog, entry), label: shortEntryLabel(entry) }));
}

/** "Sicilian: Najdorf" for a branch, the family's own name for a family. */
function shortEntryLabel(entry: PickerEntry): string {
  const trail = entryTrail(entry).map((e) => shortName(e.label));
  return trail.length > 1 ? `${trail[0]}: ${trail[trail.length - 1]}` : trail[0];
}

/* ── my lines ───────────────────────────────────────────────────────────── */

/** "Exchange Variation" under "Queen's Gambit Declined", not the whole name again. */
function underName(name: string, parent: string | null): string {
  if (!parent) return name;
  for (const sep of [': ', ', ']) if (name.startsWith(parent + sep)) return name.slice(parent.length + sep.length);
  const colon = parent.indexOf(': ');
  if (colon > 0 && name.startsWith(parent.slice(0, colon + 2))) return name.slice(colon + 2);
  return name;
}

/** The tree node standing at a line's last position, for ratings and favorites. */
export function nodeAt(tree: OpeningTree, sans: string[]): OpeningNode | null {
  const exact = tree.byId.get(sans.join(' '));
  if (exact) return exact;
  const { fens } = walkSan(sans);
  if (fens.length !== sans.length + 1) return null;
  return tree.byKey.get(positionKey(fens[fens.length - 1])) ?? null;
}

/**
 * Your own repertoire as names: each side, then its openings, their
 * variations, and the lines of an opening with none. Favorites first.
 */
export function myLines(
  reps: Repertoire[],
  index: ReferenceIndex,
  tree: OpeningTree,
  favorites: Iterable<string>,
): BrowseItem[] {
  const stars = new Set(favorites);
  const starred = (sans: string[]) => {
    const node = nodeAt(tree, sans);
    return node ? stars.has(node.id) : false;
  };
  const out: BrowseItem[] = [];
  for (const color of ['w', 'b'] as Color[]) {
    const mine = reps.filter((rep) => rep.color === color);
    const rows: BrowseRow[] = [];
    for (const rep of mine) {
      const openingRow = (opening: DerivedOpening, parent: string | null): BrowseRow => {
        const lines = opening.variations.length ? [] : linesOf(rep, opening, index);
        const open = opening.variations.length
          ? () => favoritesFirst(opening.variations.map((v) => openingRow(v, opening.name)), starred)
          : lines.length > 1
            ? () =>
                lines.map((line) => ({
                  key: `${rep.id}#${line.tipId}`,
                  label: line.split ? `${line.name} · ${line.split}` : line.name,
                  sans: line.path,
                  side: color,
                }))
            : undefined;
        return { key: opening.id, label: underName(opening.name, parent), sans: opening.path, side: color, open };
      };
      rows.push(...openingsIn(rep, index).map((opening) => openingRow(opening, null)));
    }
    if (!rows.length) continue;
    out.push({ head: color === 'w' ? 'White' : 'Black' });
    out.push(...favoritesFirst(rows, starred));
  }
  return out;
}

function favoritesFirst(rows: BrowseRow[], starred: (sans: string[]) => boolean): BrowseRow[] {
  return rows
    .map((row, i) => ({ row, i, star: starred(row.sans) }))
    .sort((a, b) => Number(b.star) - Number(a.star) || a.i - b.i)
    .map(({ row }) => row);
}

/* ── recent ─────────────────────────────────────────────────────────────── */

const DAY = 24 * 60 * 60 * 1000;

/** Openings you played lately, newest first, under Today, This week and Earlier. */
export function recentItems(
  tree: OpeningTree,
  catalog: PickerCatalog,
  score: ScoreState,
  now = env.now(),
  limit = 40,
): BrowseItem[] {
  const startOfDay = new Date(now);
  startOfDay.setHours(0, 0, 0, 0);
  const today = startOfDay.getTime();
  const played = Object.entries(score.nodes)
    .map(([id, stats]) => ({ node: tree.byId.get(id), at: stats.lastAt ?? 0 }))
    .filter((p): p is { node: OpeningNode; at: number } => Boolean(p.node) && p.node!.depth > 0 && p.at > 0)
    .sort((a, b) => b.at - a.at)
    .slice(0, limit);
  const out: BrowseItem[] = [];
  let head = '';
  for (const { node, at } of played) {
    const group = at >= today ? 'Today' : at >= today - 6 * DAY ? 'This week' : 'Earlier';
    if (group !== head) out.push({ head: (head = group) });
    out.push(nodeRow(tree, catalog, node));
  }
  return out;
}

function nodeRow(tree: OpeningTree, catalog: PickerCatalog, node: OpeningNode): BrowseRow {
  const entry = entryForNode(catalog, node);
  const row = entry && entry.node.id === node.id ? entryRow(catalog, entry) : null;
  return {
    key: node.id,
    label: lineName(tree, catalog, node.sans),
    sans: node.sans,
    side: sideForPick(catalog, node) ?? 'w',
    open: row?.open,
  };
}

/* ── search ─────────────────────────────────────────────────────────────── */

/** "qga" for "Queen's Gambit Accepted". */
function initials(name: string): string {
  return name
    .split(/[\s:,\-]+/)
    .filter(Boolean)
    .map((word) => word[0])
    .join('')
    .toLowerCase();
}

function matches(needle: string, name: string, sans: string[], eco?: string): boolean {
  const lower = name.toLowerCase();
  if (lower.includes(needle)) return true;
  if (eco && eco.toLowerCase().startsWith(needle)) return true;
  const plain = needle.replace(/\d+\.+/g, '').trim();
  if (plain && sans.join(' ').toLowerCase().startsWith(plain)) return true;
  return !needle.includes(' ') && needle.length >= 2 && initials(name).startsWith(needle);
}

/** Search by name, ECO, moves or initials: your own lines first, then the book. */
export function searchItems(
  query: string,
  reps: Repertoire[],
  index: ReferenceIndex,
  tree: OpeningTree,
  catalog: PickerCatalog,
  limit = 40,
): BrowseItem[] {
  const needle = query.trim().toLowerCase();
  if (!needle) return [];
  const out: BrowseItem[] = [];

  const mine: BrowseRow[] = [];
  const walk = (opening: DerivedOpening, color: Color) => {
    if (matches(needle, opening.name, opening.path, opening.eco))
      mine.push({ key: `mine:${opening.id}`, label: lineName(tree, catalog, opening.path), sans: opening.path, side: color });
    for (const v of opening.variations) walk(v, color);
  };
  for (const rep of reps) for (const opening of openingsIn(rep, index)) walk(opening, rep.color);
  if (mine.length) out.push({ head: 'My lines' }, ...mine.slice(0, 12));

  const book = [...catalog.byKey.values()]
    .filter((entry) => matches(needle, entry.key, entry.node.sans, entry.node.eco))
    .sort((a, b) => a.level - b.level || b.games - a.games)
    .slice(0, limit)
    .map((entry) => ({ ...entryRow(catalog, entry), label: shortEntryLabel(entry) }));
  if (book.length) out.push({ head: 'Book' }, ...book);
  return out;
}

/* ── next moves ─────────────────────────────────────────────────────────── */

export interface NextMove {
  san: string;
  /** "3.Nc3" or "3...Nf6". */
  label: string;
  /** Share of book games at this position, 0 to 100. */
  share: number;
  /** Where it goes, by name, or '' when the book names nothing near. */
  name: string;
  /** Your repertoire plays it here. */
  mine: boolean;
}

/** Every move your repertoires play, as position|san. */
export function repMoves(reps: Repertoire[]): Set<string> {
  const out = new Set<string>();
  for (const rep of reps) for (const node of Object.values(rep.nodes)) out.add(`${node.key}|${node.san}`);
  return out;
}

/**
 * The book's moves from a position, most played first, each named for where it
 * goes: its own name when the book names the position, else the names a couple
 * of plies on.
 */
export function nextMoves(
  index: ReferenceIndex,
  tree: OpeningTree,
  catalog: PickerCatalog,
  sans: string[],
  mine: Set<string>,
): NextMove[] {
  const { fens } = walkSan(sans);
  const fen = fens[fens.length - 1] ?? START_FEN;
  const key = positionKey(fen);
  const moves = [...(lookup(index, fen)?.moves ?? [])].sort((a, b) => b.games - a.games);
  const total = moves.reduce((sum, m) => sum + m.games, 0);
  const here = deepestNodeAlong(tree, sans);
  return moves.slice(0, 14).map((move) => {
    const line = [...sans, move.san];
    return {
      san: move.san,
      label: moveLabel(line),
      share: total ? (move.games / total) * 100 : 0,
      name: whereItGoes(index, tree, catalog, line, here),
      mine: mine.has(`${key}|${move.san}`),
    };
  });
}

function whereItGoes(
  index: ReferenceIndex,
  tree: OpeningTree,
  catalog: PickerCatalog,
  line: string[],
  here: OpeningNode | null,
): string {
  const label = (node: OpeningNode) => {
    const entry = entryForNode(catalog, node);
    return shortName(entry?.label ?? node.name);
  };
  const exact = nodeAt(tree, line);
  if (exact && exact.id !== here?.id && exact.depth > (here?.depth ?? 0)) return lineName(tree, catalog, exact.sans);
  // Unnamed: look a few plies on along the book's most played moves.
  const { fens } = walkSan(line);
  let frontier = [fens[fens.length - 1]];
  const found: string[] = [];
  for (let ply = 0; ply < 4 && found.length < 2 && frontier.length; ply++) {
    const next: string[] = [];
    for (const fen of frontier) {
      const moves = [...(lookup(index, fen)?.moves ?? [])].sort((a, b) => b.games - a.games).slice(0, 3);
      for (const move of moves) {
        const after = applySan(fen, move.san)?.after;
        if (!after) continue;
        const node = tree.byKey.get(positionKey(after));
        if (node && node.id !== here?.id && node.depth > (here?.depth ?? 0)) {
          const name = label(node);
          if (!found.includes(name) && found.length < 2) found.push(name);
        } else next.push(after);
      }
    }
    frontier = next.slice(0, 9);
  }
  return found.join(' · ');
}

/* ── suggestions ────────────────────────────────────────────────────────── */

interface Candidate {
  row: BrowseRow;
  /** How often you would face it without an answer: 0 to 1. */
  need: number;
  needText?: string;
  /** Shares a structure with or transposes into something you play. */
  fit: number;
  fitText?: string;
  /** Plays like something you play a lot. */
  style: number;
  styleText?: string;
}

/** A reply under this share of book games at its position is not a hole worth filling. */
const HOLE_SHARE = 0.08;
/** Nor is one you would meet in under this share of your games. */
const HOLE_REACH = 0.02;

/** How played a node is, 0 to 1, flattened so a line deep in the tree still counts. */
function popularity(index: ReferenceIndex, node: OpeningNode): number {
  const total = index.totalGames || 1;
  return Math.min(1, Math.sqrt(node.games / total));
}

/** Follow the book's most played move until it reaches a name, a few plies at most. */
function namedAfter(index: ReferenceIndex, tree: OpeningTree, sans: string[], plies = 4): OpeningNode | null {
  let line = [...sans];
  let { fens } = walkSan(line);
  let fen = fens[fens.length - 1];
  for (let i = 0; i < plies; i++) {
    const top = [...(lookup(index, fen)?.moves ?? [])].sort((a, b) => b.games - a.games)[0];
    if (!top) break;
    const after = applySan(fen, top.san)?.after;
    if (!after) break;
    line = [...line, top.san];
    fen = after;
    const node = tree.byKey.get(positionKey(after));
    if (node) return tree.byId.get(line.join(' ')) ?? node;
  }
  return null;
}

/** Holes: book replies your repertoire meets often and has no answer to. */
function holeCandidates(reps: Repertoire[], index: ReferenceIndex, tree: OpeningTree): Candidate[] {
  const out: Candidate[] = [];
  const sides: Repertoire[] = [...reps];
  // No Black repertoire at all still faces 1.e4: an empty one finds those holes.
  if (!reps.some((rep) => rep.color === 'b'))
    sides.push({ id: '', name: '', color: 'b', rootFen: START_FEN, rootChildren: [], nodes: {}, createdAt: 0 });

  for (const rep of sides) {
    const byKey = new Map<string, RepMove[]>();
    for (const node of Object.values(rep.nodes)) byKey.set(node.key, [...(byKey.get(node.key) ?? []), node]);
    const seen = new Set<string>();
    // Positions with the opponent to move: what they play, and where you go from there.
    const visit = (fen: string, sans: string[], reach: number) => {
      const key = positionKey(fen);
      if (seen.has(key)) return;
      seen.add(key);
      const moves = lookup(index, fen)?.moves ?? [];
      const total = moves.reduce((sum, m) => sum + m.games, 0);
      if (!total) return;
      for (const move of moves) {
        const share = move.games / total;
        const after = applySan(fen, move.san)?.after;
        if (!after) continue;
        const answers = byKey.get(positionKey(after)) ?? [];
        const line = [...sans, move.san];
        if (answers.length) {
          for (const answer of answers) visit(answer.fenAfter, [...line, answer.san], reach * share);
          continue;
        }
        if (share < HOLE_SHARE || reach * share < HOLE_REACH) continue;
        const target = namedAfter(index, tree, line);
        if (!target) continue;
        out.push({
          row: { key: target.id, label: '', sans: target.sans, side: rep.color },
          need: reach * share,
          needText: sans.length === 0 || (rep.color === 'w' && sans.length === 1)
            ? `Nothing yet against ${moveLabel(line)}`
            : `${moveLabel(line)} in ${Math.round(share * 100)}% of book games`,
          fit: 0,
          style: 0,
        });
      }
    };
    if (rep.color === 'b') visit(START_FEN, [], 1);
    else for (const root of childrenOf(rep, null)) visit(root.fenAfter, [root.san], 1);
  }
  return out;
}

/** Families named for a first move rather than for anybody's plan. */
const GENERIC_FAMILIES = new Set([
  "King's Pawn Game",
  "Queen's Pawn Game",
  'Indian Defence',
  "King's Knight Opening",
  'Zukertort Opening',
  'Horwitz Defence',
]);
/** Branch names that say where in the book a line is, not what it is. */
const GENERIC_BRANCH = /^(Normal|Main Line|Modern Line|Modern Variations?|Open|Closed|Traditional|Accepted|Declined)\b/;

function generic(entry: PickerEntry): boolean {
  return GENERIC_FAMILIES.has(entry.family) || (entry.level > 0 && GENERIC_BRANCH.test(entry.label));
}

/**
 * The opening a repertoire line is filed under, for "your Najdorf": the
 * family, or its branch where the family is too big to say much on its own.
 */
function yourName(catalog: PickerCatalog, node: OpeningNode | null): string {
  if (!node) return '';
  const entry = entryForNode(catalog, node);
  if (!entry) return shortName(node.name);
  const [family, branch] = entryTrail(entry);
  const big = Boolean(catalog.familyByName.get(family.key)?.groups);
  if (branch && (big || GENERIC_FAMILIES.has(family.key)) && !GENERIC_BRANCH.test(branch.label)) return shortName(branch.label);
  return shortName(family.label);
}

/** Lines the book reaches your positions from, that your repertoire never plays. */
function transposeCandidates(
  reps: Repertoire[],
  index: ReferenceIndex,
  tree: OpeningTree,
  catalog: PickerCatalog,
): Candidate[] {
  const graph = bookGraph(index);
  const out: Candidate[] = [];
  for (const rep of reps) {
    const mine = new Set(Object.values(rep.nodes).map((node) => positionKey(node.fenAfter)));
    const deep = Object.values(rep.nodes).filter((node) => plyOf(rep, node) >= 6);
    const found = new Set<string>();
    for (const node of deep) {
      const target = positionKey(node.fenAfter);
      let layer = [target];
      for (let up = 0; up < 4 && layer.length; up++) {
        const next: string[] = [];
        for (const key of layer)
          for (const parent of graph.parents.get(key) ?? []) {
            if (mine.has(parent)) continue;
            next.push(parent);
            const named = tree.byKey.get(parent);
            if (!named || named.depth < 3 || found.has(named.id)) continue;
            if (sideForPick(catalog, named) !== rep.color) continue;
            // Your own move order already gets there: it is no new line.
            if (named.pathKeys.every((k) => mine.has(k) || k === parent)) continue;
            found.add(named.id);
            const into = yourName(catalog, deepestNodeAlong(tree, pathOf(rep, node)));
            out.push({
              row: { key: named.id, label: '', sans: named.sans, side: rep.color },
              need: 0,
              fit: popularity(index, named),
              fitText: `Transposes into your ${into}`,
              style: 0,
            });
          }
        layer = next.slice(0, 40);
      }
    }
  }
  return out;
}

function plyOf(rep: Repertoire, node: RepMove): number {
  let ply = 0;
  for (let cursor: RepMove | undefined = node; cursor; cursor = cursor.parentId ? rep.nodes[cursor.parentId] : undefined)
    ply += 1;
  return ply;
}

function pathOf(rep: Repertoire, node: RepMove): string[] {
  const out: string[] = [];
  for (let cursor: RepMove | undefined = node; cursor; cursor = cursor.parentId ? rep.nodes[cursor.parentId] : undefined)
    out.unshift(cursor.san);
  return out;
}

const structures = new WeakMap<PickerCatalog, Map<string, string | null>>();

/** The structure an entry's main line settles into, six plies past its own position. */
function structureAfter(index: ReferenceIndex, catalog: PickerCatalog, entry: PickerEntry): string | null {
  let cache = structures.get(catalog);
  if (!cache) structures.set(catalog, (cache = new Map()));
  if (cache.has(entry.key)) return cache.get(entry.key)!;
  let { fens } = walkSan(entry.node.sans);
  let fen = fens[fens.length - 1];
  for (let i = 0; i < 6; i++) {
    const top = [...(lookup(index, fen)?.moves ?? [])].sort((a, b) => b.games - a.games)[0];
    const after = top && applySan(fen, top.san)?.after;
    if (!after) break;
    fen = after;
  }
  const id = structureOf(fen)?.template.id ?? null;
  cache.set(entry.key, id);
  return id;
}

/** Openings whose pawns settle the way your lines do. */
function structureCandidates(
  reps: Repertoire[],
  index: ReferenceIndex,
  tree: OpeningTree,
  catalog: PickerCatalog,
): Candidate[] {
  const out: Candidate[] = [];
  for (const rep of reps) {
    const yours = new Map<string, string>();
    for (const node of Object.values(rep.nodes)) {
      if (node.children.length) continue;
      const structure = structureOf(node.fenAfter);
      if (!structure || yours.has(structure.template.id)) continue;
      yours.set(structure.template.id, yourName(catalog, deepestNodeAlong(tree, pathOf(rep, node))));
    }
    if (!yours.size) continue;
    const mine = new Set(Object.values(rep.nodes).map((node) => positionKey(node.fenAfter)));
    for (const family of catalog.families) {
      for (const entry of [family.entry, ...family.entry.children]) {
        if (!entry.exact || entry.side !== rep.color || mine.has(entry.node.key) || generic(entry)) continue;
        const id = structureAfter(index, catalog, entry);
        const anchor = id ? yours.get(id) : undefined;
        if (!anchor) continue;
        out.push({
          row: { key: entry.node.id, label: '', sans: entry.node.sans, side: rep.color },
          need: 0,
          fit: popularity(index, entry.node),
          fitText: `Same structure as your ${anchor}`,
          style: 0,
        });
      }
    }
  }
  return out;
}

/** Openings as sharp or as quiet as the ones you play most. */
function styleCandidates(reps: Repertoire[], index: ReferenceIndex, tree: OpeningTree, catalog: PickerCatalog): Candidate[] {
  const out: Candidate[] = [];
  for (const rep of reps) {
    const mine = new Set(Object.values(rep.nodes).map((node) => positionKey(node.fenAfter)));
    const anchors = openingsIn(rep, index)
      .slice(0, 3)
      .map((opening) => {
        const node = nodeAt(tree, opening.path);
        const entry = node ? entryForNode(catalog, node) : null;
        return entry ? { entry, name: yourName(catalog, node) } : null;
      })
      .filter((a): a is { entry: PickerEntry; name: string } => a !== null);
    for (const anchor of anchors) {
      const sharp = anchor.entry.sharpness;
      const word = sharp >= 4 ? 'Sharp' : sharp <= 2 ? 'Quiet' : 'Balanced';
      for (const family of catalog.families) {
        if (family.entry.key === anchor.entry.family) continue;
        for (const entry of [family.entry, ...family.entry.children]) {
          if (!entry.exact || entry.side !== rep.color || mine.has(entry.node.key) || generic(entry)) continue;
          // White picks its first move: a style match that starts elsewhere is a new repertoire, not a new line.
          if (rep.color === 'w' && entry.node.sans[0] !== anchor.entry.node.sans[0]) continue;
          const diff = Math.abs(entry.sharpness - sharp);
          if (diff > 1) continue;
          out.push({
            row: { key: entry.node.id, label: '', sans: entry.node.sans, side: rep.color },
            need: 0,
            fit: 0,
            style: (diff === 0 ? 1 : 0.5) * popularity(index, entry.node),
            styleText: `${word} like your ${anchor.name}`,
          });
        }
      }
    }
  }
  return out;
}

const WEIGHTS = { need: 1, fit: 0.6, style: 0.35 };

/**
 * One list of openings worth a look, each with the reason it is there.
 *
 * Every candidate gets one blended score — how often you would face it
 * unprepared, how much it shares with what you play, how well it suits your
 * style — and is labeled by whichever part of that score is biggest. The list
 * is then dealt out so no label comes up more than twice in a row.
 */
export function suggestions(
  reps: Repertoire[],
  index: ReferenceIndex,
  tree: OpeningTree,
  catalog: PickerCatalog,
  limit = 30,
): BrowseRow[] {
  const merged = new Map<string, Candidate>();
  const all = [
    ...holeCandidates(reps, index, tree),
    ...transposeCandidates(reps, index, tree, catalog),
    ...structureCandidates(reps, index, tree, catalog),
    ...styleCandidates(reps, index, tree, catalog),
  ];
  for (const c of all) {
    const id = `${c.row.side}|${c.row.key}`;
    const had = merged.get(id);
    if (!had) {
      merged.set(id, { ...c });
      continue;
    }
    if (c.need > had.need) Object.assign(had, { need: c.need, needText: c.needText });
    if (c.fit > had.fit) Object.assign(had, { fit: c.fit, fitText: c.fitText });
    if (c.style > had.style) Object.assign(had, { style: c.style, styleText: c.styleText });
  }

  const scored = [...merged.values()].map((c) => {
    const parts: { kind: ReasonKind; value: number; text?: string }[] = [
      { kind: 'hole', value: c.need * WEIGHTS.need, text: c.needText },
      { kind: 'like', value: c.fit * WEIGHTS.fit, text: c.fitText },
      { kind: 'style', value: c.style * WEIGHTS.style, text: c.styleText },
    ];
    const top = parts.reduce((a, b) => (b.value > a.value ? b : a));
    const node = tree.byId.get(c.row.key);
    const row: BrowseRow = {
      ...c.row,
      key: `${c.row.side}:${c.row.key}`,
      label: lineName(tree, catalog, c.row.sans),
      why: { kind: top.kind, text: top.text ?? '' },
    };
    if (node) {
      const entry = catalog.byNode.get(node.id);
      if (entry) row.open = entryRow(catalog, entry).open;
    }
    return { row, score: parts.reduce((sum, p) => sum + p.value, 0) };
  });
  scored.sort((a, b) => b.score - a.score || a.row.label.localeCompare(b.row.label));
  return mixLabels(scored.map((s) => s.row)).slice(0, limit);
}

/** Deal rows out best first, but never three of the same label in a row. */
export function mixLabels(rows: BrowseRow[]): BrowseRow[] {
  const left = [...rows];
  const out: BrowseRow[] = [];
  while (left.length) {
    const [a, b] = out.slice(-2).map((row) => row.why?.kind);
    const run = a !== undefined && a === b ? a : null;
    const at = run ? left.findIndex((row) => row.why?.kind !== run) : 0;
    out.push(...left.splice(at < 0 ? 0 : at, 1));
  }
  return out;
}
