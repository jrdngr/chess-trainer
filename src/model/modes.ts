import type { Color } from '../chess/core';
import type { SessionMode } from './session';

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
  /** '' — every repertoire. */
  repertoireId: string;
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
  repertoireId: '',
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

/* ── Punish ─────────────────────────────────────────────────────────────── */

/** How much material a trap has to win to be worth setting. */
export const GAIN_STEPS = [2, 3, 5] as const;
/** How deep into the opening traps are drawn from, in plies. */
export const PUNISH_DEPTHS = [8, 16, 24] as const;
/** Seconds on the clock when Punish is timed. */
export const PUNISH_SECONDS = 20;

export interface PunishPrefs {
  /** '' — draw across every repertoire. */
  repertoireId: string;
  minGain: number;
  maxPly: number;
  /** Name the opening in the bar. Off makes every trap arrive unannounced. */
  nameOpening: boolean;
  /** Say which move was the mistake. Off means you have to spot it yourself. */
  announce: boolean;
  /** A countdown per puzzle. Running out counts as a miss. */
  timed: boolean;
}

export const DEFAULT_PUNISH: PunishPrefs = {
  repertoireId: '',
  minGain: 2,
  maxPly: 16,
  nameOpening: true,
  announce: true,
  timed: false,
};

export function gainLabel(gain: number): string {
  if (gain >= 5) return 'A rook or more';
  if (gain >= 3) return 'A piece or more';
  return 'Any material';
}

export function depthLabel(ply: number): string {
  return `${Math.ceil(ply / 2)} moves`;
}

/* ── Gap ────────────────────────────────────────────────────────────────── */

/** How often a reply has to be played before a hole in the prep counts. */
export const SHARE_STEPS = [3, 1, 0.2] as const;
export const GAP_DEPTHS = [8, 12, 18] as const;

export type GapSort = 'shallow' | 'popular';

export interface GapPrefs {
  /** '' — every repertoire. */
  repertoireId: string;
  minShare: number;
  maxPly: number;
  sort: GapSort;
  /** Tapping a gap adds the book's most played answer instead of asking. */
  quickFix: boolean;
}

export const DEFAULT_GAP: GapPrefs = {
  repertoireId: '',
  minShare: 1,
  maxPly: 18,
  sort: 'shallow',
  quickFix: false,
};

export function shareLabel(share: number): string {
  return share >= 1 ? `${share}% and up` : 'Anything played';
}

/* ── Punish's running record ────────────────────────────────────────────── */

export interface PunishRecord {
  seen: number;
  solved: number;
  /** Longest run of traps sprung without a miss. */
  best: number;
  streak: number;
}

export const EMPTY_PUNISH_RECORD: PunishRecord = { seen: 0, solved: 0, best: 0, streak: 0 };

export function recordPunish(record: PunishRecord, solved: boolean): PunishRecord {
  const streak = solved ? record.streak + 1 : 0;
  return {
    seen: record.seen + 1,
    solved: record.solved + (solved ? 1 : 0),
    streak,
    best: Math.max(record.best, streak),
  };
}

export function normalizePunishRecord(record: Partial<PunishRecord> | undefined): PunishRecord {
  return { ...EMPTY_PUNISH_RECORD, ...(record ?? {}) };
}
