import { DEFAULT_LEVEL } from './play';
import type { ClockMode } from './openingRun';
import type { NudgePriority } from './nudge';
import type { RepairKind, RepairSort } from './repair';
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

export interface DrillPrefs {
  draw: DrillDraw;
  /** How many unseen positions a session is willing to introduce. */
  newPerSession: number;
  /** Keep going after a correct move instead of stopping at one answer. */
  followLine: boolean;
  /** Ask the weakest positions first rather than the most overdue. */
  weakFirst: boolean;
  /** Offer "Why is it wrong?" after a miss. */
  explain: boolean;
  /** Seconds for each answer. Timing out only costs the speed bonus. */
  clock: ClockMode;
}

export const DEFAULT_DRILL: DrillPrefs = {
  draw: 'due',
  newPerSession: 8,
  followLine: true,
  weakFirst: false,
  explain: true,
  clock: 'off',
};

export const DRAW_LABELS: Record<DrillDraw, string> = {
  due: 'Scheduled',
  new: 'New only',
  cram: 'Everything',
};

/* ── Repair ─────────────────────────────────────────────────────────────── */

/** How many of your games must have reached a position before it counts. */
export const GAME_THRESHOLDS = [1, 2, 3] as const;

export interface RepairPrefs {
  kinds: 'both' | RepairKind;
  minGames: number;
  /** Only positions from games you went on to lose. */
  lossesOnly: boolean;
  sort: RepairSort;
}

export const DEFAULT_REPAIR: RepairPrefs = {
  kinds: 'both',
  minGames: 2,
  lossesOnly: false,
  sort: 'common',
};

export function kindLabel(kind: RepairKind): string {
  return kind === 'offprep' ? 'Off prep' : 'Unprepared';
}

export function gamesLabel(n: number): string {
  return n === 1 ? 'Any game' : `${n}+ games`;
}

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

/* ── Repair's running record ────────────────────────────────────────────── */

export interface RepairRecord {
  /** Off-prep positions answered correctly. */
  relearned: number;
  /** Unprepared positions given a move. */
  added: number;
  /** Items looked at, right or wrong. */
  seen: number;
}

export const EMPTY_REPAIR_RECORD: RepairRecord = { relearned: 0, added: 0, seen: 0 };

export function recordRepair(
  record: RepairRecord,
  outcome: { relearned?: boolean; added?: boolean },
): RepairRecord {
  return {
    seen: record.seen + 1,
    relearned: record.relearned + (outcome.relearned ? 1 : 0),
    added: record.added + (outcome.added ? 1 : 0),
  };
}

export function normalizeRepairRecord(record: Partial<RepairRecord> | undefined): RepairRecord {
  return { ...EMPTY_REPAIR_RECORD, ...(record ?? {}) };
}
