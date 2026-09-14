/**
 * Build the reference book from Lichess Elite PGN months.
 *
 * The Elite database is every Lichess game where a 2400+ player met a 2200+
 * one, about 280k games a month, published as one zip per month. It is a
 * direct download with no rate limiting, which is why the book is built from
 * games rather than crawled from the opening explorer.
 *
 * Counting is iteratively deepened: each pass over the file extends only the
 * prefixes the previous pass found popular enough to keep. That bounds memory
 * by the size of the book rather than by the number of games — a single pass
 * over 280k games to ply 20 would hold millions of dead nodes, nearly all of
 * them played once.
 *
 *   node scripts/build-book.mjs <month.pgn|month.zip>...
 */
import { createReadStream, mkdirSync, writeFileSync } from 'node:fs';
import { createInterface } from 'node:readline';
import { spawn } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Chess } from 'chess.js';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const outDir = join(root, 'src/model/book');

const SOURCES = process.argv.slice(2);
if (!SOURCES.length) {
  console.error('Usage: node scripts/build-book.mjs <month.pgn|month.zip>...');
  process.exit(1);
}

/** How deep the book goes. Past this, "opening" is not really the word. */
const MAX_PLY = 20;
/** Plies added per pass. Fewer passes, more memory held per pass. */
const STEP = 4;
/** A position needs this many games to earn a place in the book. */
const MIN_GAMES = 30;
/** A move needs this share of its position, in basis points, to be recorded. */
const MIN_MOVE_BP = 5;

const OPENINGS_TSV = 'https://raw.githubusercontent.com/lichess-org/chess-openings/master/';

/** One line of movetext into SAN tokens. Elite PGN has no comments or NAGs. */
function sansFrom(movetext) {
  const out = [];
  for (const token of movetext.split(/\s+/)) {
    if (!token) continue;
    if (token === '1-0' || token === '0-1' || token === '1/2-1/2' || token === '*') break;
    // "12." or "12..." — a move number, not a move.
    if (/^\d+\.+$/.test(token)) continue;
    // "12.e4" — some writers omit the space.
    const bare = token.replace(/^\d+\.+/, '');
    if (bare) out.push(bare);
    if (out.length >= MAX_PLY) break;
  }
  return out;
}

function openStream(source) {
  if (source.endsWith('.zip')) {
    const child = spawn('unzip', ['-p', source], { stdio: ['ignore', 'pipe', 'inherit'] });
    return child.stdout;
  }
  return createReadStream(source);
}

/**
 * Walk every game in the given months, handing each one's moves and result to
 * `onGame`. Returns the number of games seen.
 */
async function eachGame(onGame) {
  let games = 0;
  for (const source of SOURCES) {
    const rl = createInterface({ input: openStream(source), crlfDelay: Infinity });
    let result = null;
    let movetext = '';
    for await (const line of rl) {
      if (line.startsWith('[')) {
        if (movetext) {
          onGame(sansFrom(movetext), result);
          games += 1;
          movetext = '';
          result = null;
        }
        const found = /^\[Result "([^"]+)"\]/.exec(line);
        if (found) result = found[1];
        continue;
      }
      if (line.trim()) movetext += `${movetext ? ' ' : ''}${line.trim()}`;
    }
    if (movetext) {
      onGame(sansFrom(movetext), result);
      games += 1;
    }
  }
  return games;
}

// ── count, deepening one step at a time ────────────────────────────────────
/** SAN prefix -> [games, whiteWins, draws]. The root is the empty string. */
const counts = new Map([['', [0, 0, 0]]]);
/** Prefixes popular enough to extend. */
let kept = new Set(['']);
let totalGames = 0;
/** Plies whose popularity is already settled. Below this, `kept` is the truth. */
let settled = 0;

for (let limit = STEP; limit <= MAX_PLY; limit += STEP) {
  const fresh = new Map();
  const seen = await eachGame((sans, result) => {
    const white = result === '1-0' ? 1 : 0;
    const draw = result === '1/2-1/2' ? 1 : 0;
    let prefix = '';
    for (let ply = 0; ply < sans.length && ply < limit; ply += 1) {
      // Inside the settled region, extend only what the last pass kept:
      // everything below an unpopular position is unpopular, and not worth the
      // memory to find out. Past it, this pass is what decides, so descend.
      if (ply < settled && !kept.has(prefix)) break;
      prefix = prefix ? `${prefix} ${sans[ply]}` : sans[ply];
      if (counts.has(prefix)) continue;
      const row = fresh.get(prefix);
      if (row) {
        row[0] += 1;
        row[1] += white;
        row[2] += draw;
      } else {
        fresh.set(prefix, [1, white, draw]);
      }
    }
  });
  totalGames = seen;

  let added = 0;
  for (const [prefix, row] of fresh) {
    // Every move of a kept position is recorded, but only the popular ones are
    // extended — the rest are leaves the explorer can still show.
    counts.set(prefix, row);
    if (row[0] >= MIN_GAMES) {
      kept.add(prefix);
      added += 1;
    }
  }
  counts.set('', [seen, 0, 0]);
  settled = limit;
  console.error(`ply ${limit}: ${seen} games · ${added} positions kept · ${counts.size} nodes held`);
  if (!added) break;
}

// ── names, from lichess's own opening list ─────────────────────────────────
const openingByPath = new Map();
for (const file of ['a', 'b', 'c', 'd', 'e']) {
  const res = await fetch(`${OPENINGS_TSV}${file}.tsv`);
  const text = await res.text();
  for (const line of text.split('\n').slice(1)) {
    const [eco, name, pgn] = line.split('\t');
    if (!eco || !name || !pgn) continue;
    openingByPath.set(sansFrom(pgn).join(' '), [eco, name]);
  }
}
console.error(`names: ${openingByPath.size} openings from lichess/chess-openings`);

// ── resolve prefixes to positions ──────────────────────────────────────────
/** positionKey -> { total, moves: Map<san, [games, white, draw]> } */
const positions = new Map();
const names = new Map();
const keyCache = new Map([['', new Chess().fen().split(' ').slice(0, 4).join(' ')]]);

function keyOf(prefix) {
  const known = keyCache.get(prefix);
  if (known) return known;
  const chess = new Chess();
  for (const san of prefix.split(' ')) {
    try {
      chess.move(san);
    } catch {
      return null;
    }
  }
  const key = chess.fen().split(' ').slice(0, 4).join(' ');
  keyCache.set(prefix, key);
  return key;
}

// Children by parent, indexed once. Scanning every node for each kept prefix
// is the same work multiplied by the size of the book.
const childrenOf = new Map();
for (const [prefix, row] of counts) {
  if (!prefix) continue;
  const cut = prefix.lastIndexOf(' ');
  const parent = cut < 0 ? '' : prefix.slice(0, cut);
  const san = cut < 0 ? prefix : prefix.slice(cut + 1);
  const list = childrenOf.get(parent);
  if (list) list.push([san, row]);
  else childrenOf.set(parent, [[san, row]]);
}

for (const prefix of kept) {
  const key = keyOf(prefix);
  if (!key) continue;
  const here = counts.get(prefix);
  if (!here) continue;
  // Transpositions land on one record: two move orders reaching a position are
  // the same position, and their moves and games belong together.
  const position = positions.get(key) ?? { total: 0, moves: new Map() };
  position.total += here[0];
  for (const [san, row] of childrenOf.get(prefix) ?? []) {
    const seen = position.moves.get(san);
    if (seen) {
      seen[0] += row[0];
      seen[1] += row[1];
      seen[2] += row[2];
    } else {
      position.moves.set(san, [...row]);
    }
  }
  positions.set(key, position);
}

for (const [path, [eco, name]] of openingByPath) {
  const key = keyOf(path);
  if (key && !names.has(key)) names.set(key, [path, eco, name]);
}

// ── emit ───────────────────────────────────────────────────────────────────
mkdirSync(outDir, { recursive: true });
const emitted = [];
for (const [key, position] of positions) {
  const moves = [];
  for (const [san, [games, white, draw]] of position.moves) {
    const bp = Math.round((games / position.total) * 10_000);
    if (bp < MIN_MOVE_BP) continue;
    moves.push([san, bp, Math.round((white / games) * 100), Math.round((draw / games) * 100)]);
  }
  if (!moves.length) continue;
  moves.sort((a, b) => b[1] - a[1]);
  emitted.push([key, position.total, moves]);
}
emitted.sort((a, b) => b[1] - a[1]);

const months = SOURCES.map((s) => /(\d{4}-\d{2})/.exec(s)?.[1]).filter(Boolean);
const book = {
  version: 1,
  source: `Lichess Elite${months.length ? ` ${months.join(', ')}` : ''}`,
  builtAt: new Date().toISOString().slice(0, 10),
  totalGames,
  positions: emitted,
  names: [...names]
    .filter(([key]) => positions.has(key))
    .map(([key, [path, eco, name]]) => [key, path, eco, name]),
};
const json = `${JSON.stringify(book)}\n`;
writeFileSync(join(outDir, 'book.json'), json);

const mb = (n) => `${(n / 1_048_576).toFixed(2)} MB`;
console.error(
  `\nwrote src/model/book/book.json` +
    `\n  ${book.positions.length} positions from ${totalGames} games` +
    `\n  ${book.names.length} named, ${mb(json.length)}` +
    `\n  ${Math.round(book.positions.reduce((s, p) => s + p[2].length, 0) / book.positions.length * 10) / 10} moves per position`,
);
