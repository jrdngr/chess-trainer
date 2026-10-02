import { DEFAULT_LEVEL } from './play';
import type { ClockMode } from './openingRun';
import type { NudgePriority } from './nudge';
import type { SessionMode } from './session';

export { LEVELS, levelById, OPENING_PLIES } from './play';

/**
 * What each mode remembers between visits.
 *
 * Every mode now opens on its own setup screen, so the options that shape a
 * mode live with that mode rather than in a global settings sheet. Settings is
 * left with the things that are true of the whole app — the board, the device,
 * the account — and nothing that changes how a mode plays.
 */

/* ── Drill ──────────────────────────────────────────────────────────────── */

/** What a drill session draws from the schedule. */
export type DrillDraw = Extract<SessionMode, 'due' | 'new' | 'cram'>;

/** One position at a time, or a whole line from move one — see `lineDrill.ts`. */
export type DrillForm = 'positions' | 'lines';

export interface DrillPrefs {
  form: DrillForm;
  draw: DrillDraw;
  /** How many unseen positions a session is willing to introduce. */
  newPerSession: number;
  /** Keep going after a correct move instead of stopping at one answer. */
  followLine: boolean;
  /**
   * Ask the weakest positions first rather than the most overdue; for lines,
   * draw the weakest lines rather than the ones you would meet most.
   */
  weakFirst: boolean;
  /** Offer "Why is it wrong?" after a miss. */
  explain: boolean;
  /** Seconds for each answer. Timing out only costs the speed bonus. */
  clock: ClockMode;
}

export const DEFAULT_DRILL: DrillPrefs = {
  form: 'positions',
  draw: 'due',
  newPerSession: 8,
  followLine: true,
  weakFirst: false,
  explain: true,
  clock: 'off',
};

export const FORM_LABELS: Record<DrillForm, string> = {
  positions: 'Positions',
  lines: 'Lines',
};

export const DRAW_LABELS: Record<DrillDraw, string> = {
  due: 'Scheduled',
  new: 'New only',
  cram: 'Everything',
};

/* ── Play ───────────────────────────────────────────────────────────────── */

export interface PlayPrefs {
  /** One of LEVELS. */
  level: string;
  /** Write the opening into a repertoire when the game ends. */
  save: boolean;
  /** Say so the moment you leave your own prep. */
  warnOffBook: boolean;
  showEval: boolean;
  takeBacks: boolean;
}

export const DEFAULT_PLAY: PlayPrefs = {
  level: DEFAULT_LEVEL,
  save: true,
  warnOffBook: true,
  showEval: false,
  takeBacks: true,
};

/* ── Growth ─────────────────────────────────────────────────────────────── */

/** How often a reply has to be played before it is worth preparing for. */
export const SHARE_STEPS = [3, 1, 0.2] as const;
export const GROWTH_DEPTHS = [8, 12, 18] as const;

export interface GrowthPrefs {
  minShare: number;
  maxPly: number;
  /**
   * Which familiar move the arrows nudge toward when both kinds are on
   * offer: one that transposes into your lines, or one you play elsewhere in
   * the opening. Read by Tidy too. See `nudgeArrows`.
   */
  nudgePriority: NudgePriority;
  /** Count reaching your usual pawns as a habit. */
  nudgePawns: boolean;
}

export const DEFAULT_GROWTH: GrowthPrefs = {
  minShare: 1,
  maxPly: 18,
  nudgePriority: 'transposition',
  nudgePawns: false,
};

export function shareLabel(share: number): string {
  return share >= 1 ? `${share}% and up` : 'Anything played';
}
