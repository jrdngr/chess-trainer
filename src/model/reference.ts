import { applySan, positionKey, START_FEN } from '../chess/core';
import type { ExplorerEntry, ExplorerMove, ReferenceGame } from './types';

/**
 * The reference database is authored as a set of weighted paths and folded into
 * a tree. Move counts are derived, so a position's numbers always add up: the
 * explorer never shows a child more popular than its parent.
 *
 * Paths look like:  "e4:40:38/33/29 c5:40 Nf3:55 d6:40"
 * where the parts are SAN : share-of-games-at-that-position : white/draw/black.
 */
export interface RefTreeNode {
  san: string;
  share: number;
  wdl: [number, number, number];
  children: Map<string, RefTreeNode>;
}

const DEFAULT_WDL: [number, number, number] = [36, 33, 31];

function parseToken(token: string): { san: string; share: number; wdl?: [number, number, number] } {
  const [san, shareRaw, wdlRaw] = token.split(':');
  const share = Number(shareRaw ?? 10);
  let wdl: [number, number, number] | undefined;
  if (wdlRaw) {
    const parts = wdlRaw.split('/').map(Number);
    if (parts.length === 3 && parts.every((n) => Number.isFinite(n))) {
      wdl = [parts[0], parts[1], parts[2]];
    }
  }
  return { san, share: Number.isFinite(share) ? share : 10, wdl };
}

export function buildRefTree(paths: string[]): Map<string, RefTreeNode> {
  const roots = new Map<string, RefTreeNode>();
  for (const path of paths) {
    let level = roots;
    let parentWdl = DEFAULT_WDL;
    for (const token of path.trim().split(/\s+/)) {
      if (!token) continue;
      const { san, share, wdl } = parseToken(token);
      let node = level.get(san);
      if (!node) {
        node = { san, share, wdl: wdl ?? parentWdl, children: new Map() };
        level.set(san, node);
      } else if (wdl) {
        node.wdl = wdl;
      }
      parentWdl = node.wdl;
      level = node.children;
    }
  }
  return roots;
}

export interface OpeningName {
  eco: string;
  name: string;
}

/** One named opening: where it sits, and how often it is played. */
export interface CatalogueEntry extends OpeningName {
  /** The defining move order, space-joined — also the opening's id. */
  id: string;
  sans: string[];
  /** Games in the sample that reached the position. */
  games: number;
}

export interface ReferenceIndex {
  /** positionKey -> explorer entry */
  entries: Map<string, ExplorerEntry>;
  /** positionKey -> opening name */
  names: Map<string, OpeningName>;
  /** Every named opening, most played first. */
  catalogue: CatalogueEntry[];
  totalGames: number;
  gameCount: number;
}

export interface BuildIndexOptions {
  paths: string[];
  /** "e4 c5 Nf3 d6" -> { eco, name } */
  openingNames: Record<string, OpeningName>;
  games: ReferenceGame[];
  totalGames: number;
  startFen?: string;
}

/** Walk the authored tree and produce a position-keyed explorer index. */
export function buildReferenceIndex(opts: BuildIndexOptions): ReferenceIndex {
  const startFen = opts.startFen ?? START_FEN;
  const tree = buildRefTree(opts.paths);
  const entries = new Map<string, ExplorerEntry>();

  const visit = (level: Map<string, RefTreeNode>, fen: string, gamesHere: number) => {
    if (!level.size) return;
    const nodes = [...level.values()];
    const shareTotal = nodes.reduce((sum, n) => sum + n.share, 0) || 1;
    const moves: ExplorerMove[] = [];
    const children: { node: RefTreeNode; fen: string; games: number }[] = [];

    for (const node of nodes) {
      const move = applySan(fen, node.san);
      if (!move) continue;
      const games = Math.max(1, Math.round((gamesHere * node.share) / shareTotal));
      const [w, d, b] = node.wdl;
      const wdlTotal = w + d + b || 1;
      moves.push({
        san: move.san,
        games,
        white: Math.round((games * w) / wdlTotal),
        draw: Math.round((games * d) / wdlTotal),
        black: Math.round((games * b) / wdlTotal),
      });
      children.push({ node, fen: move.after, games });
    }

    if (moves.length) {
      moves.sort((a, b) => b.games - a.games);
      entries.set(positionKey(fen), { key: positionKey(fen), moves });
    }
    for (const child of children) visit(child.node.children, child.fen, child.games);
  };

  visit(tree, startFen, opts.totalGames);

  // Opening names, resolved from SAN prefixes to position keys.
  const names = new Map<string, OpeningName>();
  for (const [line, name] of Object.entries(opts.openingNames)) {
    let fen = startFen;
    let ok = true;
    for (const san of line.split(/\s+/).filter(Boolean)) {
      const move = applySan(fen, san);
      if (!move) {
        ok = false;
        break;
      }
      fen = move.after;
    }
    if (ok) names.set(positionKey(fen), name);
  }

  // Attach the deepest matching opening name to each entry, and index games.
  const gamesByKey = new Map<string, ReferenceGame[]>();
  for (const game of opts.games) {
    let fen = startFen;
    const seen = new Set<string>();
    for (const san of game.moves.slice(0, 30)) {
      const key = positionKey(fen);
      if (!seen.has(key)) {
        seen.add(key);
        const list = gamesByKey.get(key) ?? [];
        if (list.length < 8) list.push(game);
        gamesByKey.set(key, list);
      }
      const move = applySan(fen, san);
      if (!move) break;
      fen = move.after;
    }
  }

  for (const [key, entry] of entries) {
    const named = names.get(key);
    if (named) {
      entry.eco = named.eco;
      entry.opening = named.name;
    }
    const games = gamesByKey.get(key);
    if (games?.length) entry.topGames = games;
  }

  // Positions that have games or a name but no authored continuations still
  // deserve an entry so the explorer can show something useful.
  for (const [key, name] of names) {
    if (!entries.has(key)) entries.set(key, { key, moves: [], eco: name.eco, opening: name.name });
  }
  for (const [key, games] of gamesByKey) {
    const existing = entries.get(key);
    if (existing) existing.topGames = existing.topGames ?? games;
    else entries.set(key, { key, moves: [], topGames: games });
  }

  // The catalogue: every named opening, with how often it is actually reached.
  //
  // Popularity is the count on the move that arrives at the position, or the
  // games continuing from it, whichever is larger. The arriving count must come
  // from the final ply and not an earlier one: a path that leaves the authored
  // tree part way down is rare, and inheriting 1.d4's count would rank the
  // Englund Gambit alongside the Queen's Pawn Opening.
  const found: CatalogueEntry[] = [];
  for (const [path, name] of Object.entries(opts.openingNames)) {
    const sans = path.split(/\s+/).filter(Boolean);
    // A one-move name is not an opening you would sit down to practise — it is
    // the whole database with a first move, which this mode already offers.
    if (sans.length < 2) continue;
    let fen = startFen;
    let arriving = 0;
    let legal = true;
    for (const san of sans) {
      const parent = entries.get(positionKey(fen));
      arriving = parent?.moves.find((m) => m.san === san)?.games ?? 0;
      const move = applySan(fen, san);
      if (!move) {
        legal = false;
        break;
      }
      fen = move.after;
    }
    if (!legal) continue;
    const here = entries.get(positionKey(fen));
    const games = Math.max(arriving, here ? here.moves.reduce((s, m) => s + m.games, 0) : 0);
    found.push({ id: path, sans, eco: name.eco, name: name.name, games });
  }

  // One row per name: the data names a few positions the same way at different
  // depths, and two identical rows in a picker are worse than one.
  const byName = new Map<string, CatalogueEntry>();
  for (const entry of found) {
    const seen = byName.get(entry.name);
    if (!seen || entry.games > seen.games || (entry.games === seen.games && entry.sans.length < seen.sans.length)) {
      byName.set(entry.name, entry);
    }
  }
  const catalogue = [...byName.values()].sort(
    (a, b) => b.games - a.games || a.name.localeCompare(b.name),
  );

  return {
    entries,
    names,
    catalogue,
    totalGames: opts.totalGames,
    gameCount: opts.games.length,
  };
}

/** Look one opening up by its id — the space-joined move order. */
export function openingById(index: ReferenceIndex, id: string): CatalogueEntry | null {
  return index.catalogue.find((entry) => entry.id === id) ?? null;
}

/** A name, plus how deep into the line it was recognised. */
export interface NamedLine extends OpeningName {
  /** Plies matched. 1 is "Queen's Pawn Opening"; 8 is a real variation. */
  ply: number;
}

/**
 * Deepest opening name on the path to a position, with the depth it matched
 * at. The depth matters: a line the database only recognises at ply 1 has been
 * named "Queen's Pawn Opening", which is true and useless.
 */
export function deepestName(
  index: ReferenceIndex,
  sans: string[],
  startFen = START_FEN,
): NamedLine | null {
  let fen = startFen;
  const root = index.names.get(positionKey(fen));
  let best: NamedLine | null = root ? { ...root, ply: 0 } : null;
  sans.forEach(() => undefined);
  let ply = 0;
  for (const san of sans) {
    const move = applySan(fen, san);
    if (!move) break;
    fen = move.after;
    ply += 1;
    const named = index.names.get(positionKey(fen));
    if (named) best = { ...named, ply };
  }
  return best;
}

/** Deepest opening name on the path to a position — "Sicilian Defence: Najdorf". */
export function openingNameForPath(
  index: ReferenceIndex,
  sans: string[],
  startFen = START_FEN,
): OpeningName | null {
  const found = deepestName(index, sans, startFen);
  return found ? { eco: found.eco, name: found.name } : null;
}

export function lookup(index: ReferenceIndex, fen: string): ExplorerEntry | null {
  return index.entries.get(positionKey(fen)) ?? null;
}

export function totalGamesAt(entry: ExplorerEntry | null): number {
  if (!entry) return 0;
  return entry.moves.reduce((sum, m) => sum + m.games, 0);
}

export function formatGameCount(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(n >= 10_000_000 ? 0 : 1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(n >= 10_000 ? 0 : 1)}k`;
  return String(n);
}

export function movePercent(move: ExplorerMove, total: number): number {
  return total ? (move.games / total) * 100 : 0;
}
