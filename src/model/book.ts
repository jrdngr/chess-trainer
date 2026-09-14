import type { ExplorerEntry, ExplorerMove } from './types';
import type { CatalogueEntry, OpeningName, ReferenceIndex } from './reference';
import { REFERENCE_GAMES } from './seed/games';
import { applySan, positionKey, START_FEN } from '../chess/core';
// Imported as text rather than as a module: letting TypeScript infer the type
// of a multi-megabyte JSON literal costs more than the whole rest of the
// typecheck, and one JSON.parse at boot is cheaper than the object literal the
// bundler would otherwise emit.
import bookJson from './book/book.json?raw';

/**
 * The reference book, crawled from the lichess opening explorer.
 *
 * Unlike the authored paths this replaced, the crawl already knows every
 * position's key, so building the index is a parse and two loops rather than a
 * walk through move generation. Nothing here calls into chess.js.
 *
 * Wire format — arrays, not objects, because the field names would otherwise be
 * most of the file:
 *   positions: [positionKey, gamesAtPosition, [[san, shareBp, whitePct, drawPct], ...]]
 *   names:     [positionKey, sanPath, eco, name]
 *
 * Move popularity is stored as a share of the position in basis points. The
 * explorer only ever shows it as a proportion, and at 659M games the absolute
 * counts are nine digits each.
 */
export interface BookFile {
  version: number;
  source: string;
  builtAt: string;
  totalGames: number;
  positions: [string, number, [string, number, number, number][]][];
  names: [string, string, string, string][];
}

/**
 * Lichess spells it "Defense". The rest of the app — and the openings the user
 * already has filed — spell it "Defence", so the book is normalised on the way
 * in rather than leaving two spellings to collide in the same picker.
 */
function normaliseName(name: string): string {
  return name.replace(/\bDefense\b/g, 'Defence');
}

function buildEntries(book: BookFile): Map<string, ExplorerEntry> {
  const entries = new Map<string, ExplorerEntry>();
  for (const [key, total, moves] of book.positions) {
    const rows: ExplorerMove[] = moves.map(([san, bp, whitePct, drawPct]) => {
      const games = Math.round((total * bp) / 10_000);
      const white = Math.round((games * whitePct) / 100);
      const draw = Math.round((games * drawPct) / 100);
      return { san, games, white, draw, black: Math.max(0, games - white - draw) };
    });
    rows.sort((a, b) => b.games - a.games);
    entries.set(key, { key, moves: rows });
  }
  return entries;
}

/** Famous games, attached to every position they pass through. */
function attachGames(entries: Map<string, ExplorerEntry>): void {
  for (const game of REFERENCE_GAMES) {
    let fen = START_FEN;
    const seen = new Set<string>();
    for (const san of game.moves.slice(0, 30)) {
      const key = positionKey(fen);
      if (!seen.has(key)) {
        seen.add(key);
        const entry = entries.get(key) ?? { key, moves: [] };
        entry.topGames = entry.topGames ?? [];
        if (entry.topGames.length < 8) entry.topGames.push(game);
        entries.set(key, entry);
      }
      const move = applySan(fen, san);
      if (!move) break;
      fen = move.after;
    }
  }
}

/** Turn a book file into the index the app reads. Pure, so it can be tested on a literal. */
export function decodeBook(book: BookFile): ReferenceIndex {
  const entries = buildEntries(book);
  const names = new Map<string, OpeningName>();
  const found: CatalogueEntry[] = [];

  for (const [key, path, eco, rawName] of book.names) {
    const name = normaliseName(rawName);
    names.set(key, { eco, name });
    const entry = entries.get(key);
    if (entry) {
      entry.eco = eco;
      entry.opening = name;
    }
    const sans = path.split(' ').filter(Boolean);
    // A one-move name is not an opening you would sit down to practise — it is
    // the whole database with a first move, which this mode already offers.
    if (sans.length < 2) continue;
    found.push({ id: path, sans, eco, name, games: entry?.moves.reduce((s, m) => s + m.games, 0) ?? 0 });
  }

  attachGames(entries);

  // One row per name: the book names a few positions the same way at different
  // depths, and two identical rows in a picker are worse than one.
  const byName = new Map<string, CatalogueEntry>();
  for (const entry of found) {
    const seen = byName.get(entry.name);
    if (!seen || entry.games > seen.games || (entry.games === seen.games && entry.sans.length < seen.sans.length)) {
      byName.set(entry.name, entry);
    }
  }

  return {
    entries,
    names,
    catalogue: [...byName.values()].sort((a, b) => b.games - a.games || a.name.localeCompare(b.name)),
    totalGames: book.totalGames,
    gameCount: REFERENCE_GAMES.length,
  };
}

const parsed = JSON.parse(bookJson) as BookFile;

export const BOOK_SOURCE = `${parsed.source} \u00b7 ${parsed.totalGames.toLocaleString()} games`;

export function buildBookIndex(): ReferenceIndex {
  return decodeBook(parsed);
}
