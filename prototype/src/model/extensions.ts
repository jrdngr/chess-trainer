import { fenTurn, positionKey, walkSan, START_FEN, type Color } from '../chess/core';
import { BLUNDER_LIMIT } from './openingRun';
import { lookup, totalGamesAt, type ReferenceIndex } from './reference';
import { BOOK_SHARE } from './survival';
import { childrenOf } from './repertoire';
import type { RepMove, Repertoire } from './types';

/**
 * Extensions: the moves in your Playbook that are not book moves.
 *
 * A book move is the book phase's: at least `BOOK_SHARE` of strong players'
 * games play it there, and the engine does not call it a mistake. Everything
 * else is an extension, your moves and the opponent's alike, of one of three
 * kinds:
 *
 * - **Rare**: sound, but under `BOOK_SHARE` or not in the book at a position
 *   the book has.
 * - **Mistake**: the engine judge gives away more than `BLUNDER_LIMIT`, the
 *   line Survival ends a run at.
 * - **Past the book**: the book has no games at the position at all.
 *
 * Only your own moves are ever extensions. The opponent's moves are theirs
 * to choose, however rare: a reply to 2.c3 is prep for 2.c3, not you going
 * off on your own. Once one of your moves leaves the book, your moves under it
 * are extensions too: a handful of games after a rare move are not the book's
 * word on what to play.
 *
 * Nothing here is stored. The kind is worked out from whichever book is
 * loaded, so a book update reclassifies a move by itself. The one thing kept
 * on a move is what the engine said when it came in (`RepMove.lost`), since
 * that is what tells a mistake from a rare move and is slow to work out again.
 */

export type MoveKind = 'book' | 'rare' | 'mistake' | 'past';

/** What a move is, at its own position, with what the engine said when it has said it. */
export function moveKind(index: ReferenceIndex, fenBefore: string, san: string, lost?: number): MoveKind {
  if (lost !== undefined && lost > BLUNDER_LIMIT) return 'mistake';
  const entry = lookup(index, fenBefore);
  const total = totalGamesAt(entry);
  if (!entry || total <= 0) return 'past';
  const move = entry.moves.find((m) => m.san === san);
  return move && move.games / total >= BOOK_SHARE ? 'book' : 'rare';
}

/**
 * A move's kind where the line it is on stands: under an extension a move
 * the book would play is still an extension, and is read as a rare one.
 */
function underExtension(kind: MoveKind): MoveKind {
  return kind === 'book' ? 'rare' : kind;
}

/**
 * Each move of a line from the start position, by kind, for the player of
 * `color`. `lost[i]` is what the engine said of move i. The opponent's moves
 * always read as book.
 */
export function lineKinds(
  index: ReferenceIndex,
  sans: string[],
  color: Color,
  lost: (number | undefined)[] = [],
): MoveKind[] {
  const { fens } = walkSan(sans, START_FEN);
  const out: MoveKind[] = [];
  let off = false;
  for (let i = 0; i < sans.length && i < fens.length - 1; i++) {
    if (!movedBy(i, color)) {
      out.push('book');
      continue;
    }
    const kind = moveKind(index, fens[i], sans[i], lost[i]);
    out.push(off ? underExtension(kind) : kind);
    off ||= kind !== 'book';
  }
  return out;
}

/** How many moves at the start of a line are book moves: where it becomes an extension. */
export function bookLength(kinds: MoveKind[]): number {
  const at = kinds.findIndex((kind) => kind !== 'book');
  return at < 0 ? kinds.length : at;
}

/** Every move of a tree by kind, keyed by node id. The opponent's moves always read as book. */
export function treeKinds(rep: Repertoire, index: ReferenceIndex): Map<string, MoveKind> {
  const out = new Map<string, MoveKind>();
  const visit = (node: RepMove, off: boolean) => {
    const own = fenTurn(node.fenBefore) === rep.color ? moveKind(index, node.fenBefore, node.san, node.lost) : 'book';
    out.set(node.id, off ? underExtension(own) : own);
    for (const kid of childrenOf(rep, node.id)) visit(kid, off || own !== 'book');
  };
  for (const root of childrenOf(rep, null)) visit(root, false);
  return out;
}

/** Whether the side that plays move `ply` (0 is White's first) is `color`. */
export function movedBy(ply: number, color: Color): boolean {
  return (ply % 2 === 0) === (color === 'w');
}

/**
 * What the engine said of each move in your trees, by position and move: the
 * one stored thing a played line needs to be classified, since the line a run
 * plays is matched to your prep by position rather than by node.
 */
export function lossesIn(reps: Repertoire[]): Map<string, number> {
  const out = new Map<string, number>();
  for (const rep of reps) {
    for (const node of Object.values(rep.nodes)) {
      if (node.lost !== undefined) out.set(`${positionKey(node.fenBefore)} ${node.san}`, node.lost);
    }
  }
  return out;
}

/** A played line by kind for the player of `color`, with your trees' stored losses for its moves. */
export function playedKinds(
  index: ReferenceIndex,
  sans: string[],
  color: Color,
  losses: Map<string, number>,
): MoveKind[] {
  const { fens } = walkSan(sans, START_FEN);
  const lost = sans.map((san, i) => (fens[i] ? losses.get(`${positionKey(fens[i])} ${san}`) : undefined));
  return lineKinds(index, sans, color, lost);
}
