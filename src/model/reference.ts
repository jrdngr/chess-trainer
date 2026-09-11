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

export interface ReferenceIndex {
  /** positionKey -> explorer entry */
  entries: Map<string, ExplorerEntry>;
  /** positionKey -> opening name */
  names: Map<string, OpeningName>;
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

  return { entries, names, totalGames: opts.totalGames, gameCount: opts.games.length };
}

/** Deepest opening name on the path to a position — "Sicilian Defence: Najdorf". */
export function openingNameForPath(
  index: ReferenceIndex,
  sans: string[],
  startFen = START_FEN,
): OpeningName | null {
  let fen = startFen;
  let best: OpeningName | null = index.names.get(positionKey(fen)) ?? null;
  for (const san of sans) {
    const move = applySan(fen, san);
    if (!move) break;
    fen = move.after;
    const named = index.names.get(positionKey(fen));
    if (named) best = named;
  }
  return best;
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
