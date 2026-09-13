import type { Color } from '../chess/core';
import type { ScoreMode } from './scoring';

/**
 * Autopilot: one game after another, each chosen by the recommendation
 * engine, without going back to Home in between.
 *
 * A game is one round of a mode. Run has an obvious one — a line to its end
 * or its first mistake. The others are cut to a size that plays in a minute
 * or two, so the rhythm stays short games back to back.
 */
export const GAME_SIZE = {
  /** Answers in one Drill game, each answer in a followed line counting. */
  drill: 5,
  /** Items in one Repair game. */
  repair: 5,
} as const;

/** What Autopilot decided a game should be. */
export interface GamePlan {
  color: Color;
  /** The opening to steer toward: an opening tree node id inside the selection. */
  steer: string;
}

/** What a game turned out to be, reported by the mode when it ends. */
export interface GameSummary {
  mode: ScoreMode;
  openingId: string;
  color: Color;
  score: number;
  answered: number;
  correct: number;
  perfect: boolean;
}
