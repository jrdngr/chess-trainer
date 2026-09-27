import type { Color } from '../chess/core';

/**
 * How much a move moves the eval bar, from the side playing it.
 *
 * Growth shows the bar over the position you are answering, and each answer
 * says what it does to it: about 0.0 for the engine's own choice, less for
 * anything worse. Read from your side, so bigger is always better whichever
 * colour you have.
 */

/** A mate, as a score: far past anything a position is otherwise worth. */
const MATE = 10_000;

/** One engine score as centipawns from White's side, mates folded in; null when there is none. */
export function whiteCp(line: { cp: number | null; mate: number | null } | undefined): number | null {
  if (!line) return null;
  if (line.mate !== null) return line.mate > 0 ? MATE - line.mate : -MATE - line.mate;
  return line.cp;
}

/** The change a move makes to the position's eval, in centipawns from the mover's side. */
export function deltaFor(color: Color, position: number, afterMove: number): number {
  const change = afterMove - position;
  return color === 'w' ? change : -change;
}

/** Below this the change is noise between two searches, and reads as nothing. */
export const EVEN_CP = 10;

/** "+0.3", "−1.2", "0.0" — pawns, capped where the number stops meaning anything. */
export function formatDelta(cp: number): string {
  if (Math.abs(cp) < EVEN_CP) return '0.0';
  const pawns = Math.min(Math.abs(cp) / 100, 9.9);
  return `${cp > 0 ? '+' : '−'}${pawns.toFixed(1)}`;
}

/** How a delta is coloured: up is good, down is bad, near nothing is plain. */
export function deltaTone(cp: number): 'good' | 'bad' | 'even' {
  if (Math.abs(cp) < EVEN_CP) return 'even';
  return cp > 0 ? 'good' : 'bad';
}
