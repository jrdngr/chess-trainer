import { applySan, fenTurn, piecesFromFen, walkSan, type Color } from '../chess/core';
import { nameAt, lookup, totalGamesAt, type ReferenceIndex } from './reference';
import { deepestNodeAlong, type OpeningTree } from './openingTree';
import { entryForNode, pickerCatalog } from './picker';
import { BOOK_SHARE } from './survival';

/**
 * Play on the board: building a Playbook by playing the moves in.
 *
 * The board offers the book's most played moves as arrows, one of them
 * highlighted, and the style you pick decides which: the most played, the
 * quietest, the sharpest, a gambit or a fianchetto. Only book moves are
 * offered, so following the arrows never leaves the book; playing something
 * else is allowed, and the Save sheet says so.
 */

export interface BookChoice {
  san: string;
  /** Share of the book's games at the position, 0 to 1. */
  share: number;
}

/** The book moves here, most played first: those at least `BOOK_SHARE` of games choose. */
export function bookChoices(index: ReferenceIndex, fen: string): BookChoice[] {
  const entry = lookup(index, fen);
  const total = totalGamesAt(entry);
  if (!entry || total <= 0) return [];
  return entry.moves
    .map((move) => ({ san: move.san, share: move.games / total }))
    .filter((choice) => choice.share >= BOOK_SHARE)
    .sort((a, b) => b.share - a.share);
}

export type Style = 'popular' | 'solid' | 'attack' | 'gambit' | 'fianchetto';

export const STYLES: { id: Style; label: string }[] = [
  { id: 'popular', label: 'Popular' },
  { id: 'solid', label: 'Solid' },
  { id: 'attack', label: 'Attack' },
  { id: 'gambit', label: 'Gambit' },
  { id: 'fianchetto', label: 'Fianchetto' },
];

/**
 * How far past a move the book is followed to see where it leads: the reply
 * and your next move. Further than that the most played line wanders into
 * whatever the book happens to name, and the style stops being about the move.
 */
const LOOKAHEAD = 2;

const FIANCHETTO = new Set(['g3', 'b3', 'g6', 'b6', 'Bg2', 'Bb2', 'Bg7', 'Bb7']);

/** Where a move leads if both sides keep to the book's most played moves. */
function leadsTo(index: ReferenceIndex, path: string[], san: string): string[] {
  const line = [...path, san];
  let fen = walkSan(line).fens.at(-1)!;
  for (let i = 0; i < LOOKAHEAD; i++) {
    const next = bookChoices(index, fen)[0];
    const move = next && applySan(fen, next.san);
    if (!move) break;
    line.push(move.san);
    fen = move.after;
  }
  return line;
}

/** The names a line reaches past `from` plies, in order. */
function namesPast(index: ReferenceIndex, line: string[], from: number): string[] {
  const { fens } = walkSan(line);
  return fens
    .slice(from + 1)
    .map((fen) => nameAt(index, fen)?.name)
    .filter((name): name is string => !!name);
}

function isGambit(name: string): boolean {
  return /Gambit/.test(name) && !/^Queen's Gambit/.test(name) && !/Declined/.test(name);
}

/**
 * The move a style highlights among the book moves here, or null when the
 * style finds nothing that fits. Most played breaks every tie.
 */
export function stylePick(
  index: ReferenceIndex,
  tree: OpeningTree,
  path: string[],
  choices: BookChoice[],
  style: Style,
): string | null {
  if (!choices.length) return null;
  if (style === 'popular') return choices[0].san;
  const ply = path.length;
  const scored = choices.map((choice) => {
    const line = leadsTo(index, path, choice.san);
    const names = namesPast(index, line, ply);
    let score: number | null = null;
    if (style === 'solid' || style === 'attack') {
      const node = deepestNodeAlong(tree, line);
      const sharpness = node ? entryForNode(pickerCatalog(tree), node)?.sharpness : undefined;
      if (sharpness !== undefined) score = style === 'solid' ? -sharpness : sharpness;
    } else if (style === 'gambit') {
      score = names.some(isGambit) ? 1 : null;
    } else {
      score = FIANCHETTO.has(choice.san) || names.some((name) => /Fianchetto/.test(name)) ? 1 : null;
    }
    return { san: choice.san, share: choice.share, score };
  });
  const fitting = scored.filter((s) => s.score !== null);
  if (!fitting.length) return null;
  fitting.sort((a, b) => b.score! - a.score! || b.share - a.share);
  return fitting[0].san;
}

/**
 * The styles worth showing here: Popular always, and every other one that
 * would highlight a different move, or is the one picked.
 */
export function shownStyles(picks: Partial<Record<Style, string | null>>, picked: Style): Style[] {
  return STYLES.map((s) => s.id).filter(
    (id) => id === 'popular' || id === picked || (picks[id] && picks[id] !== picks.popular),
  );
}

/** The arrows to draw: the three most played, with the highlighted move always among them. */
export function arrowChoices(choices: BookChoice[], highlight: string | null): BookChoice[] {
  const top = choices.slice(0, 3);
  if (!highlight || top.some((c) => c.san === highlight)) return top;
  const picked = choices.find((c) => c.san === highlight);
  return picked ? [...top.slice(0, 2), picked] : top;
}

/** "47%": a share as the arrows show it. */
export function shareText(share: number): string {
  return `${Math.max(1, Math.round(share * 100))}%`;
}

/* ── goals ────────────────────────────────────────────────────────────── */

export interface Goal {
  label: string;
  value: string;
  /** The value names pieces or squares, rather than saying something in words. */
  moves: boolean;
}

const HOME: Record<Color, { square: string; piece: 'n' | 'b' }[]> = {
  w: [
    { square: 'b1', piece: 'n' },
    { square: 'c1', piece: 'b' },
    { square: 'f1', piece: 'b' },
    { square: 'g1', piece: 'n' },
  ],
  b: [
    { square: 'b8', piece: 'n' },
    { square: 'c8', piece: 'b' },
    { square: 'f8', piece: 'b' },
    { square: 'g8', piece: 'n' },
  ],
};

/**
 * Where one side stands on the opening's three jobs: the minor pieces still
 * at home, whether it has castled, and the center pawns against the other
 * side's. Read off the position alone.
 */
export function goals(fen: string, color: Color): Goal[] {
  const pieces = piecesFromFen(fen);
  const at = (square: string) => pieces.find((p) => p.square === square);

  const home = HOME[color].filter(({ square, piece }) => {
    const p = at(square);
    return p && p.color === color && p.type === piece;
  });
  const develop = home.length ? home.map(({ square, piece }) => `${piece.toUpperCase()}${square}`).join(' ') : 'done';

  const rank = color === 'w' ? '1' : '8';
  const king = pieces.find((p) => p.type === 'k' && p.color === color);
  const rights = fen.split(' ')[2] ?? '-';
  const canCastle = color === 'w' ? /[KQ]/.test(rights) : /[kq]/.test(rights);
  const castled = !!king && king.square[1] === rank && ['g', 'h', 'b', 'c'].includes(king.square[0]) && !canCastle;
  const castle = castled ? 'done' : canCastle ? 'not yet' : 'no';

  const center = (side: Color) =>
    pieces
      .filter((p) => p.type === 'p' && p.color === side && 'de'.includes(p.square[0]) && '3456'.includes(p.square[1]))
      .map((p) => p.square)
      .sort()
      .join(' ');
  const mine = center(color);
  const theirs = center(color === 'w' ? 'b' : 'w');
  const centerText = mine || theirs ? `${mine || '—'} vs ${theirs || '—'}` : '—';

  return [
    { label: 'Develop', value: develop, moves: home.length > 0 },
    { label: 'Castle', value: castle, moves: false },
    { label: 'Center', value: centerText, moves: true },
  ];
}

/** Whose move it is after a line. */
export function turnAfter(sans: string[]): Color {
  return fenTurn(walkSan(sans).fens.at(-1)!);
}
