import type { Color } from '../chess/core';
import type { ColorChoice } from './openingRun';
import { DEFAULT_LEVEL } from './play';
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
  /** Restrict to positions you answer as this colour. */
  side: Color | 'both';
  /** How many unseen positions a session is willing to introduce. */
  newPerSession: number;
  /** Keep going after a correct move instead of stopping at one answer. */
  followLine: boolean;
  /** Ask the weakest positions first rather than the most overdue. */
  weakFirst: boolean;
  /** Offer "Why is it wrong?" after a miss. */
  explain: boolean;
}

export const DEFAULT_DRILL: DrillPrefs = {
  draw: 'due',
  side: 'both',
  newPerSession: 8,
  followLine: true,
  weakFirst: false,
  explain: true,
};

export const DRAW_LABELS: Record<DrillDraw, string> = {
  due: 'Scheduled',
  new: 'New only',
  cram: 'Everything',
};

export function drawDescription(draw: DrillDraw): string {
  switch (draw) {
    case 'new':
      return 'Only positions you have never been asked. Good for learning a line you just added.';
    case 'cram':
      return 'Every position in scope, shallow first, ignoring the schedule. Answers still count.';
    default:
      return 'What the schedule says is due, with a few new positions woven in. The normal way to practise.';
  }
}

/* ── Repair ─────────────────────────────────────────────────────────────── */

/** How many of your games must have reached a position before it counts. */
export const GAME_THRESHOLDS = [1, 2, 3] as const;

export interface RepairPrefs {
  /** '' — every repertoire. */
  repertoireId: string;
  kinds: 'both' | RepairKind;
  minGames: number;
  /** Only positions from games you went on to lose. */
  lossesOnly: boolean;
  sort: RepairSort;
}

export const DEFAULT_REPAIR: RepairPrefs = {
  repertoireId: '',
  kinds: 'both',
  minGames: 2,
  lossesOnly: false,
  sort: 'common',
};

export function kindLabel(kind: RepairKind): string {
  return kind === 'offprep' ? 'Off prep' : 'Unprepared';
}

export function kindDescription(kinds: RepairPrefs['kinds']): string {
  switch (kinds) {
    case 'offprep':
      return 'Positions where you had a move prepared and played something else. These have a right answer.';
    case 'unprepared':
      return 'Positions you keep reaching with nothing prepared. These need a decision, not an answer.';
    default:
      return 'Both: the moves you forgot, and the positions you never prepared for.';
  }
}

export function gamesLabel(n: number): string {
  return n === 1 ? 'Any game' : `${n}+ games`;
}

/* ── Play ───────────────────────────────────────────────────────────────── */

export interface PlayPrefs {
  color: ColorChoice;
  /** One of LEVELS. */
  level: string;
  /** Write the opening into a repertoire when the game ends. */
  save: boolean;
  /** '' — whichever repertoire fits the colour played. */
  repertoireId: string;
  /** Say so the moment you leave your own prep. */
  warnOffBook: boolean;
  showEval: boolean;
  takeBacks: boolean;
}

export const DEFAULT_PLAY: PlayPrefs = {
  color: 'w',
  level: DEFAULT_LEVEL,
  save: true,
  repertoireId: '',
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
}

export const DEFAULT_GROWTH: GrowthPrefs = { minShare: 1, maxPly: 18 };

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
