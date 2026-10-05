import type { DrillPrefs, GrowthPrefs } from './modes';
import type { SurvivalPrefs } from './survival';

/**
 * Autopilot's own options, and the values it plays every mode on.
 *
 * Autopilot is curated: it decides what each round is and how it is played,
 * so it never reads a mode's setup. Changing Survival, Drill or Growth on
 * their own screens changes those modes and nothing here. The only choices
 * left to the player are matters of taste, kept on Autopilot's own sheet.
 *
 * The fixed values are written out rather than spread from each mode's
 * defaults, so a change to a mode's defaults does not reach Autopilot either.
 */
export interface AutopilotPrefs {
  /** Survival's move-score popups. */
  moveScores: boolean;
  /** Survival's board-edge glow. */
  boardGlow: boolean;
}

export const DEFAULT_AUTOPILOT: AutopilotPrefs = { moveScores: true, boardGlow: true };

/** Drill rounds: no clock, Why? always offered. Weakest first is set per round. */
export const AUTO_DRILL: DrillPrefs = {
  form: 'positions',
  draw: 'due',
  newPerSession: 8,
  followLine: true,
  weakFirst: false,
  explain: true,
  batchSimilar: true,
  clock: 'off',
};

/** Growth rounds, and what counts as ready to grow when picking a round. */
export const AUTO_GROWTH: GrowthPrefs = {
  minShare: 1,
  maxPly: 18,
  nudgePriority: 'transposition',
  nudgePawns: false,
};

/** Survival rounds: Autopilot steers, there is no clock, the feedback is yours. */
export function autoSurvival(prefs: AutopilotPrefs): SurvivalPrefs {
  return { steer: 'lines', clock: 'off', moveScores: prefs.moveScores, boardGlow: prefs.boardGlow };
}

/** Every mode's options as an Autopilot round plays them. */
export interface ModePrefs {
  survival: SurvivalPrefs;
  drill: DrillPrefs;
  growth: GrowthPrefs;
}

export function autopilotModes(prefs: AutopilotPrefs): ModePrefs {
  return { survival: autoSurvival(prefs), drill: AUTO_DRILL, growth: AUTO_GROWTH };
}
