import { applySan, positionKey, START_FEN, type Color } from '../chess/core';
import type { ExplorerEntry, ExplorerMove } from './types';

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

/**
 * The reference database: every position the book knows, keyed by
 * `positionKey`, plus the names attached to them.
 *
 * Built by `model/book.ts` from a crawl of the lichess opening explorer. The
 * crawl resolves transpositions itself — a position two move orders reach is
 * one record — so nothing here has to merge routes back together.
 */
export interface ReferenceIndex {
  /** positionKey -> explorer entry */
  entries: Map<string, ExplorerEntry>;
  /** positionKey -> opening name */
  names: Map<string, OpeningName>;
  /** Every named opening, most played first. */
  catalogue: CatalogueEntry[];
  totalGames: number;
  gameCount: number;
  /** Every book move knows where it leads (`ExplorerMove.next`), so the book is a graph as loaded. */
  linked?: boolean;
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

/**
 * The deepest name on this line that describes the given side's opening.
 *
 * Openings are named from one side or the other: "Sicilian Defence" names what
 * Black did, "Queen's Pawn Opening" what White did. A name attaches at the ply
 * of the move that earned it, so preferring names landing just after this
 * colour moved is what keeps a Black repertoire from being called after White's
 * first move. Where the line has no such name, the deepest one of either side
 * is still better than nothing.
 */
export function deepestNameForColor(
  index: ReferenceIndex,
  sans: string[],
  color: Color,
  startFen = START_FEN,
): NamedLine | null {
  let fen = startFen;
  let any: NamedLine | null = null;
  let mine: NamedLine | null = null;
  const root = index.names.get(positionKey(fen));
  if (root) any = { ...root, ply: 0 };
  let ply = 0;
  for (const san of sans) {
    const move = applySan(fen, san);
    if (!move) break;
    fen = move.after;
    ply += 1;
    const named = index.names.get(positionKey(fen));
    if (!named) continue;
    any = { ...named, ply };
    // White's moves are the odd plies, Black's the even ones.
    if ((ply % 2 === 1) === (color === 'w')) mine = { ...named, ply };
  }
  return mine ?? any;
}

const familyCache = new WeakMap<ReferenceIndex, Map<string, string>>();

/**
 * The opening family a name belongs to: "Sicilian Defence: Najdorf Variation"
 * is a Sicilian Defence, and "Sicilian Defence" is its own family.
 *
 * Names rather than positions, because the book's taxonomy lives in the text.
 * Walking the move order cannot do it: the King's Indian is named at
 * 1.d4 Nf6 2.c4 g6 3.Nc3 Bg7 4.e4, so the Bf4 System and the Smyslov are its
 * siblings and not its children — no position they share carries the name.
 */
export function familyName(index: ReferenceIndex, name: string): string {
  return families(index).get(name) ?? name;
}

function families(index: ReferenceIndex): Map<string, string> {
  const cached = familyCache.get(index);
  if (cached) return cached;
  const names = [...new Set([...index.names.values()].map((named) => named.name))];
  const standalone = names.filter((named) => !named.includes(': '));
  const map = new Map<string, string>();
  for (const name of names) {
    const at = name.indexOf(': ');
    if (at < 0) {
      map.set(name, name);
      continue;
    }
    const prefix = name.slice(0, at);
    // The shortest opening the catalogue names with this prefix. Lichess spells
    // the family out in full — "Sicilian Defence: Najdorf Variation" — so the
    // prefix is usually the family exactly, and the lookup only has to confirm
    // the book names it on its own. Where it does not, as with the Torre
    // Attack, the prefix is left standing, which still reads as a family.
    const found = standalone
      .filter((named) => named === prefix || named.startsWith(`${prefix} `))
      .sort((a, b) => a.length - b.length)[0];
    map.set(name, found ?? prefix);
  }
  familyCache.set(index, map);
  return map;
}

/**
 * Every name the book attaches along a line, shallowest first.
 *
 * `deepestName` answers "what is this line called"; this answers "what is it
 * called at each stage", which is what grouping lines into families needs: the
 * Sämisch is a King's Indian is a Queen's Pawn Opening, and which of those three
 * is the useful heading depends on how specific the caller wants to be.
 */
export function namesAlong(
  index: ReferenceIndex,
  sans: string[],
  startFen = START_FEN,
): NamedLine[] {
  let fen = startFen;
  const out: NamedLine[] = [];
  let ply = 0;
  for (const san of sans) {
    const move = applySan(fen, san);
    if (!move) break;
    fen = move.after;
    ply += 1;
    const named = index.names.get(positionKey(fen));
    if (named) out.push({ ...named, ply });
  }
  return out;
}

/**
 * The same, but nothing at all when the only name restates the first move.
 *
 * For labelling a line as the player's own opening. "Queen's Pawn Opening" on a
 * Black line whose point is what happened at move four is true and says less
 * than "your Black prep" does — that is the complaint this answers, and the
 * depth is what fixes it rather than which side the name belongs to. Whose move
 * earned the name cannot decide it: the book attaches "King's Indian Defence"
 * at 1.d4 Nf6 2.c4 g6 3.Nc3 Bg7 4.e4, White's seventh ply, and it is still the
 * name of Black's opening.
 */
export function specificNameForColor(
  index: ReferenceIndex,
  sans: string[],
  color: Color,
  startFen = START_FEN,
  minPly = 2,
): NamedLine | null {
  const found = deepestNameForColor(index, sans, color, startFen);
  return found && found.ply >= minPly ? found : null;
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

/**
 * The book's name for this exact position, if it has one.
 *
 * Unlike `deepestName` this looks at one position rather than a whole line, so
 * it answers "does an opening begin here?" — which is what deriving the named
 * regions of a repertoire tree needs.
 */
export function nameAt(index: ReferenceIndex, fen: string): OpeningName | null {
  return index.names.get(positionKey(fen)) ?? null;
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
