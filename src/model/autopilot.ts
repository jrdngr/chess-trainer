import type { Color } from '../chess/core';
import type { Steer } from './openingRun';
import type { Focus, Recommendation, Start } from './recommend';

/**
 * Autopilot: one round after another, each a Run on settings the
 * recommendation engine chose, without going back to Home in between.
 *
 * A round is one Run — your prep to its end, or to the checkpoint where you
 * leave it. The engine decides the opening, the colour and the focus; the
 * focus is nothing the player is told, only what the opponent steers toward.
 * Autopilot never adds to the repertoire: that is Growth's, and the reveal's.
 */

/** What each focus steers the opponent by. */
export const STEER_FOR: Record<Focus, Steer> = { test: 'popular', review: 'weak' };

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
  /** The Run setting the focus comes down to. */
  options: { steer: Steer };
}

export function planFor(pick: Recommendation): RoundPlan {
  return {
    color: pick.color,
    steer: pick.opening.id,
    start: pick.start,
    options: { steer: STEER_FOR[pick.focus] },
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
