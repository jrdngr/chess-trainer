import type { Color } from '../chess/core';
import type { Steer } from './openingRun';
import type { Focus, Recommendation, Start } from './recommend';

/**
 * Autopilot: one round after another, each a Run on settings the
 * recommendation engine chose, without going back to Home in between.
 *
 * A round is one Run — a line to its end or its first mistake. The engine
 * decides the opening, the colour and the focus; the focus is nothing the
 * player is told, only the settings the round is played on.
 */

/** What each focus steers the opponent by. */
export const STEER_FOR: Record<Focus, Steer> = { test: 'popular', review: 'weak', grow: 'gaps' };

/** What Autopilot decided a round should be. */
export interface RoundPlan {
  color: Color;
  /** The opening to steer toward: an opening tree node id inside the selection. */
  steer: string;
  /**
   * Where the round begins: from move one, following whatever is played, or
   * inside the opening with the way in already on the board.
   */
  start: Start;
  /** The Run settings the focus comes down to. */
  options: { steer: Steer; newMoves: number };
}

export function planFor(pick: Recommendation): RoundPlan {
  return {
    color: pick.color,
    steer: pick.opening.id,
    start: pick.start,
    options: { steer: STEER_FOR[pick.focus], newMoves: pick.focus === 'grow' ? pick.newMoves : 0 },
  };
}

/** What a round turned out to be, reported by the Run when it ends. */
export interface RoundSummary {
  openingId: string;
  color: Color;
  score: number;
  answered: number;
  correct: number;
  perfect: boolean;
}
