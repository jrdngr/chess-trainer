import type { Color } from '../chess/core';
import { markSeen } from './freshness';
import { ancestorsOf, deepestNodeAlong, type OpeningTree } from './openingTree';

/**
 * Score: what a game pays, where the points go, and what they add up to.
 *
 * Points are reward, never assessment — the schedule already grades mistakes,
 * so nothing here is ever subtracted. Every number a game can earn lives in
 * `POINTS`, so balancing the modes against each other is an edit here and
 * nowhere else. Run and Drill are on a clock, and most of their maximum is
 * the speed bonus: a fast answer is the only way to a full score in a timed
 * mode. Growth and Repair have no clock, so their base is higher.
 */
export type ScoreMode = 'run' | 'drill' | 'growth' | 'repair';

export const SCORE_MODES: ScoreMode[] = ['run', 'drill', 'growth', 'repair'];

export const POINTS = {
  run: { move: 1, finish: 5, green: 3 },
  drill: { answer: 1, lapsed: 1 },
  growth: { added: 5 },
  repair: { relearned: 4, added: 2 },
  /** Per timed move: the first half of the clock, the second half, then nothing. */
  speed: { fast: 2, quick: 1 },
  /** Consecutive correct moves in one game, from this many onward, pay this much extra each. */
  combo: { from: 3, per: 1 },
} as const;

/**
 * The bonus for answering within a budget, decided by how much of it was
 * used: full for the first half, half for the second, nothing once the clock
 * has run out. Reading the tiers off the budget rather than fixed seconds is
 * what makes the bonus and the clock hit zero together.
 */
export function speedBonus(elapsedSeconds: number, budgetSeconds: number | null): number {
  if (budgetSeconds === null || budgetSeconds <= 0) return 0;
  if (elapsedSeconds < budgetSeconds / 2) return POINTS.speed.fast;
  if (elapsedSeconds < budgetSeconds) return POINTS.speed.quick;
  return 0;
}

/** The extra a correct move earns for being the `streak`th in a row. */
export function comboBonus(streak: number): number {
  return streak >= POINTS.combo.from ? POINTS.combo.per : 0;
}

/* ── milestones ─────────────────────────────────────────────────────────── */

export interface MilestoneTier {
  name: string;
  color: string;
}

/** Infrared through ultraviolet, in order. */
export const MILESTONES: MilestoneTier[] = [
  { name: 'Infrared', color: '#7f1d1d' },
  { name: 'Red', color: '#ef4444' },
  { name: 'Orange', color: '#f97316' },
  { name: 'Yellow', color: '#facc15' },
  { name: 'Green', color: '#4ade80' },
  { name: 'Blue', color: '#3b82f6' },
  { name: 'Indigo', color: '#6366f1' },
  { name: 'Violet', color: '#a855f7' },
  { name: 'Ultraviolet', color: '#e879f9' },
];

/** Points to the first milestone on a variation's ladder. */
export const FIRST_MILESTONE = 1000;
/** Each milestone asks this much more than the last. */
export const MILESTONE_RATIO = 1.6;

/**
 * How much steeper a ladder is for a wider region.
 *
 * A first move collects everything under it, so its ladder is four times a
 * variation's and a family's twice; the global ladder stands on its own.
 */
export function ladderMultiplier(depth: number): number {
  if (depth <= 0) return 1;
  if (depth === 1) return 4;
  if (depth === 2) return 2;
  return 1;
}

/** Points needed to reach milestone `level` (0 is infrared) on a ladder. */
export function milestoneThreshold(level: number, multiplier = 1): number {
  return Math.round(FIRST_MILESTONE * multiplier * MILESTONE_RATIO ** level);
}

export interface Milestone {
  /** Milestones reached so far; 0 is none. */
  reached: number;
  /** The colour currently held, or null below infrared. */
  held: MilestoneTier | null;
  /** The colour being worked toward. Past ultraviolet the colour stays. */
  next: MilestoneTier;
  /** "Ultraviolet II" and on, once the ladder has been climbed. */
  nextLabel: string;
  heldLabel: string | null;
  floor: number;
  ceiling: number;
  /** 0..1 of the way from the last milestone to the next. */
  progress: number;
}

function tierLabel(level: number): string {
  const tier = MILESTONES[Math.min(level, MILESTONES.length - 1)];
  const cycle = level - (MILESTONES.length - 1);
  return cycle > 0 ? `${tier.name} ${roman(cycle + 1)}` : tier.name;
}

function tierOf(level: number): MilestoneTier {
  return MILESTONES[Math.min(level, MILESTONES.length - 1)];
}

function roman(n: number): string {
  const numerals: [number, string][] = [[10, 'X'], [9, 'IX'], [5, 'V'], [4, 'IV'], [1, 'I']];
  let out = '';
  let left = n;
  for (const [value, glyph] of numerals) {
    while (left >= value) {
      out += glyph;
      left -= value;
    }
  }
  return out;
}

/** Where a score stands on a ladder. The ladder never ends. */
export function milestoneOf(score: number, multiplier = 1): Milestone {
  let reached = 0;
  while (score >= milestoneThreshold(reached, multiplier)) reached += 1;
  const floor = reached === 0 ? 0 : milestoneThreshold(reached - 1, multiplier);
  const ceiling = milestoneThreshold(reached, multiplier);
  return {
    reached,
    held: reached === 0 ? null : tierOf(reached - 1),
    heldLabel: reached === 0 ? null : tierLabel(reached - 1),
    next: tierOf(reached),
    nextLabel: tierLabel(reached),
    floor,
    ceiling,
    progress: Math.max(0, Math.min(1, (score - floor) / (ceiling - floor))),
  };
}

/* ── the record ─────────────────────────────────────────────────────────── */

export interface ModeTally {
  rounds: number;
  score: number;
  answered: number;
  correct: number;
  lastAt: number | null;
}

export interface DayTally {
  score: number;
  answered: number;
  correct: number;
  rounds: number;
}

/** Everything one opening — or the whole game — has earned. */
export interface NodeStats {
  score: number;
  /** Scoring events credited directly to this node, for comparing siblings. */
  own: number;
  answered: number;
  correct: number;
  byMode: Record<ScoreMode, ModeTally>;
  bestRun: number;
  lastAt: number | null;
  /** 'YYYY-MM-DD' → the day's numbers. Kept for ever. */
  days: Record<string, DayTally>;
}

/**
 * One round: a Run, a Drill session, a Growth run or a Repair sitting.
 * A round rather than a game, because none of them is a game of chess.
 */
export interface RoundRecord {
  mode: ScoreMode;
  /** The opening the round was credited to. */
  openingId: string;
  color: Color;
  score: number;
  answered: number;
  correct: number;
  perfect: boolean;
  at: number;
  /**
   * The line the round was about — the one the opponent was steering toward,
   * whether or not it was reached. What the next rounds should not be.
   */
  line?: string[];
}

export interface ScoreState {
  total: number;
  global: NodeStats;
  nodes: Record<string, NodeStats>;
  rounds: RoundRecord[];
  /** Position key → the Run round that last saw it. See `freshness.ts`. */
  seen: Record<string, number>;
}

function emptyTally(): ModeTally {
  return { rounds: 0, score: 0, answered: 0, correct: 0, lastAt: null };
}

export function emptyNodeStats(): NodeStats {
  return {
    score: 0,
    own: 0,
    answered: 0,
    correct: 0,
    byMode: { run: emptyTally(), drill: emptyTally(), growth: emptyTally(), repair: emptyTally() },
    bestRun: 0,
    lastAt: null,
    days: {},
  };
}

export const EMPTY_SCORE: ScoreState = { total: 0, global: emptyNodeStats(), nodes: {}, rounds: [], seen: {} };

/** A saved tally from before rounds were called rounds. */
type Legacy<T> = Partial<T> & { games?: number };

/**
 * Read a saved score, whatever it is missing. Rounds used to be saved as
 * games, at every level, and a record kept for ever is read either way.
 */
export function normalizeScore(
  saved: (Partial<ScoreState> & { games?: RoundRecord[] }) | undefined,
): ScoreState {
  const tally = (saved: Legacy<ModeTally> | undefined): ModeTally => {
    const { games, ...rest } = saved ?? {};
    return { ...emptyTally(), ...rest, rounds: saved?.rounds ?? games ?? 0 };
  };
  const day = (saved: Legacy<DayTally>): DayTally => {
    const { games, ...rest } = saved;
    return { score: 0, answered: 0, correct: 0, ...rest, rounds: saved.rounds ?? games ?? 0 };
  };
  const fix = (stats: Partial<NodeStats> | undefined): NodeStats => {
    const empty = emptyNodeStats();
    const byMode = { ...empty.byMode };
    for (const mode of SCORE_MODES) byMode[mode] = tally(stats?.byMode?.[mode]);
    return {
      ...empty,
      ...(stats ?? {}),
      byMode,
      days: Object.fromEntries(Object.entries(stats?.days ?? {}).map(([key, d]) => [key, day(d)])),
    };
  };
  return {
    total: saved?.total ?? 0,
    global: fix(saved?.global),
    nodes: Object.fromEntries(Object.entries(saved?.nodes ?? {}).map(([id, stats]) => [id, fix(stats)])),
    rounds: saved?.rounds ?? saved?.games ?? [],
    seen: saved?.seen ?? {},
  };
}

/** The local calendar day a moment falls on. */
export function dayKey(at: number): string {
  const date = new Date(at);
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${date.getFullYear()}-${month}-${day}`;
}

/** One thing that earned points, or could have. */
export interface ScoreEvent {
  mode: ScoreMode;
  points: number;
  /** The line the position sits on — decides which openings are credited. */
  line: string[];
  color: Color;
  /** True when this was an answer, right or wrong; false for a bonus or an add. */
  answered: boolean;
  correct: boolean;
  at: number;
}

/**
 * Which openings an event credits: the deepest node its line goes through
 * and every ancestor of it. Ids, shallowest first; empty when the book names
 * nothing along the line, in which case only the global total moves.
 */
export function creditedNodes(tree: OpeningTree, line: string[]): string[] {
  const deepest = deepestNodeAlong(tree, line);
  return deepest ? ancestorsOf(tree, deepest.id).map((node) => node.id) : [];
}

function tallyEvent(stats: NodeStats, event: ScoreEvent, own: boolean): NodeStats {
  const mode = stats.byMode[event.mode];
  const key = dayKey(event.at);
  const day = stats.days[key] ?? { score: 0, answered: 0, correct: 0, rounds: 0 };
  const answered = event.answered ? 1 : 0;
  const correct = event.answered && event.correct ? 1 : 0;
  return {
    ...stats,
    score: stats.score + event.points,
    own: stats.own + (own ? 1 : 0),
    answered: stats.answered + answered,
    correct: stats.correct + correct,
    lastAt: event.at,
    byMode: {
      ...stats.byMode,
      [event.mode]: {
        ...mode,
        score: mode.score + event.points,
        answered: mode.answered + answered,
        correct: mode.correct + correct,
        lastAt: event.at,
      },
    },
    days: {
      ...stats.days,
      [key]: {
        ...day,
        score: day.score + event.points,
        answered: day.answered + answered,
        correct: day.correct + correct,
      },
    },
  };
}

/** Apply one event: the global total, and every opening it credits. */
export function applyEvent(state: ScoreState, tree: OpeningTree, event: ScoreEvent): ScoreState {
  const credited = creditedNodes(tree, event.line);
  const nodes = { ...state.nodes };
  credited.forEach((id, i) => {
    nodes[id] = tallyEvent(nodes[id] ?? emptyNodeStats(), event, i === credited.length - 1);
  });
  return {
    ...state,
    total: state.total + event.points,
    global: tallyEvent(state.global, event, false),
    nodes,
  };
}

function tallyRound(stats: NodeStats, round: RoundRecord): NodeStats {
  const mode = stats.byMode[round.mode];
  const key = dayKey(round.at);
  const day = stats.days[key] ?? { score: 0, answered: 0, correct: 0, rounds: 0 };
  return {
    ...stats,
    bestRun: round.mode === 'run' ? Math.max(stats.bestRun, round.correct) : stats.bestRun,
    lastAt: round.at,
    byMode: { ...stats.byMode, [round.mode]: { ...mode, rounds: mode.rounds + 1, lastAt: round.at } },
    days: { ...stats.days, [key]: { ...day, rounds: day.rounds + 1 } },
  };
}

/**
 * Log a finished round against the opening it was played in and every
 * opening above it. Points were credited move by move as they were earned;
 * this counts the round and remembers when.
 */
export function recordRound(state: ScoreState, tree: OpeningTree, round: RoundRecord): ScoreState {
  const credited = ancestorsOf(tree, round.openingId).map((node) => node.id);
  const nodes = { ...state.nodes };
  for (const id of credited) nodes[id] = tallyRound(nodes[id] ?? emptyNodeStats(), round);
  const global = tallyRound(state.global, round);
  // Only a Run is a round the next Run should not repeat; the count of them
  // is the clock freshness is read against.
  const seen =
    round.mode === 'run' && round.line ? markSeen(state.seen, round.line, global.byMode.run.rounds) : state.seen;
  return {
    ...state,
    global,
    nodes,
    rounds: [...state.rounds, round],
    seen,
  };
}

/** What the rounds so far have been about, for the draw and the scorer. */
export function seenIn(state: ScoreState): { at: Record<string, number>; round: number } {
  return { at: state.seen, round: state.global.byMode.run.rounds };
}

export function nodeStats(state: ScoreState, id: string): NodeStats {
  return id === '' ? state.global : (state.nodes[id] ?? emptyNodeStats());
}

/** Correct over answered, or null before anything has been answered. */
export function accuracy(stats: Pick<NodeStats, 'answered' | 'correct'>): number | null {
  return stats.answered ? stats.correct / stats.answered : null;
}

/* ── streaks ────────────────────────────────────────────────────────────── */

/**
 * Days in a row with at least one game, counting back from today — or from
 * yesterday, so a streak is not broken by not having played *yet* today.
 */
export function streak(stats: NodeStats, now = Date.now()): number {
  const played = new Set(Object.entries(stats.days).filter(([, day]) => day.rounds > 0).map(([key]) => key));
  const DAY = 86_400_000;
  let count = 0;
  let cursor = now;
  if (!played.has(dayKey(cursor))) cursor -= DAY;
  while (played.has(dayKey(cursor))) {
    count += 1;
    cursor -= DAY;
  }
  return count;
}
