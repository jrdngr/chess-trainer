import type { Color } from '../chess/core';
import { markSeen } from './freshness';
import {
  ancestorsOf,
  deepestNodeAlong,
  insideRegion,
  type OpeningTree,
} from './openingTree';

/**
 * The rating: how well you know one opening.
 *
 * There is no global score any more, and no points. Every opening you have
 * starred carries a rating of its own, and nothing else is rated: a star is
 * the player saying "this one is mine", and the rating answers how well they
 * have it. Only the modes that *test* you move it — Run, and Autopilot, which
 * is Run with the engine choosing. Drill, Growth, Repair and Play still record
 * what they did, because rounds, accuracy and streaks are activity rather than
 * assessment, but none of them changes a rating.
 *
 * A rating moves like a chess rating. Each prepared position you answer is one
 * result against that opening: right pushes it up, a miss pulls it down, and
 * the size of the move is split by how well the rating already expects you to
 * do. Low down a correct move is worth a lot and a miss costs little; high up
 * it is the other way round. So the number settles at the accuracy you really
 * hold in that opening and cannot be inflated by volume — playing more only
 * makes it truer.
 */

/**
 * The modes whose activity is tallied. They are no longer *scoring* modes:
 * only `rated` results move a rating, and only Run produces those.
 */
export type ActivityMode = 'run' | 'drill' | 'growth' | 'repair';

export const ACTIVITY_MODES: ActivityMode[] = ['run', 'drill', 'growth', 'repair'];

/* ── the rating ─────────────────────────────────────────────────────────── */

export const RATING = {
  /** Where an opening starts the moment it is starred. */
  start: 0,
  /** It never goes below this, so a bad session cannot dig a hole. */
  floor: 0,
  /**
   * The most one result can move a rating, split between the two outcomes by
   * the accuracy the rating expects. 40 puts King within a few hundred correct
   * moves and still lets one miss sting at the top.
   */
  step: 40,
  /**
   * Ratings this far apart differ by ten to one in odds. 450 spreads the tiers
   * across the accuracies a repertoire actually passes through: 62% at Pawn,
   * 99% at King.
   */
  scale: 450,
} as const;

/** The share of answers a rating expects to be right. */
export function expectedAccuracy(rating: number): number {
  return 1 / (1 + 10 ** (-rating / RATING.scale));
}

/** The rating a result leaves behind. Kept to two decimals, shown rounded. */
export function ratingAfter(rating: number, correct: boolean): number {
  const moved = rating + RATING.step * ((correct ? 1 : 0) - expectedAccuracy(rating));
  return Math.round(Math.max(RATING.floor, moved) * 100) / 100;
}

/** What one result would move a rating by, right and wrong. */
export function ratingSwing(rating: number): { up: number; down: number } {
  return {
    up: ratingAfter(rating, true) - rating,
    down: ratingAfter(rating, false) - rating,
  };
}

/* ── tiers ──────────────────────────────────────────────────────────────── */

export interface Tier {
  name: string;
  color: string;
  /** The rating that reaches it. */
  at: number;
}

/**
 * The ladder, in pieces. Each rung is a real step in accuracy rather than a
 * round number, so a promotion is rare enough to mean something: Pawn is
 * roughly 62% of your prepared moves found, Knight 78%, Bishop 88%, Rook 94%,
 * Queen 97%, King 99%.
 */
export const TIERS: Tier[] = [
  { name: 'Pawn', color: '#94a3b8', at: 100 },
  { name: 'Knight', color: '#4ade80', at: 250 },
  { name: 'Bishop', color: '#2dd4bf', at: 400 },
  { name: 'Rook', color: '#3b82f6', at: 550 },
  { name: 'Queen', color: '#a855f7', at: 700 },
  { name: 'King', color: '#facc15', at: 850 },
];

/** What an opening below the first rung shows. */
export const UNRATED: Tier = { name: 'Unrated', color: '#4b4b55', at: 0 };

export interface Rank {
  rating: number;
  /** Tiers reached; 0 is unrated. */
  reached: number;
  /** The tier held, or null below Pawn. */
  held: Tier | null;
  /** The tier being worked toward, or null at the top of the ladder. */
  next: Tier | null;
  heldLabel: string;
  nextLabel: string | null;
  floor: number;
  ceiling: number;
  /** 0..1 of the way from the tier held to the next. */
  progress: number;
}

/** Where a rating stands on the ladder. */
export function rankOf(rating: number): Rank {
  let reached = 0;
  while (reached < TIERS.length && rating >= TIERS[reached].at) reached += 1;
  const held = reached === 0 ? null : TIERS[reached - 1];
  const next = reached < TIERS.length ? TIERS[reached] : null;
  const floor = held?.at ?? 0;
  const ceiling = next?.at ?? held?.at ?? TIERS[0].at;
  return {
    rating,
    reached,
    held,
    next,
    heldLabel: held?.name ?? UNRATED.name,
    nextLabel: next?.name ?? null,
    floor,
    ceiling,
    progress: next ? Math.max(0, Math.min(1, (rating - floor) / (ceiling - floor))) : 1,
  };
}

/** The colour a rating draws in, the unrated grey included. */
export function tierColor(rating: number): string {
  return rankOf(rating).held?.color ?? UNRATED.color;
}

/* ── the record ─────────────────────────────────────────────────────────── */

export interface ModeTally {
  rounds: number;
  answered: number;
  correct: number;
  lastAt: number | null;
}

export interface DayTally {
  answered: number;
  correct: number;
  rounds: number;
  /** Where the rating stood at the end of the day, or null if it never moved. */
  rating: number | null;
}

/** Everything one opening — or the whole game — has done. */
export interface NodeStats {
  /**
   * The rating. Only openings you have starred are ever rated, and the global
   * record is never rated at all: it is activity, not assessment.
   */
  rating: number;
  /** Rated results this opening has had, right and wrong. */
  rated: number;
  answered: number;
  correct: number;
  byMode: Record<ActivityMode, ModeTally>;
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
  mode: ActivityMode;
  /** The opening the round was credited to. */
  openingId: string;
  color: Color;
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
  /** Activity for the whole game. Never rated. */
  global: NodeStats;
  nodes: Record<string, NodeStats>;
  rounds: RoundRecord[];
  /** Position key → the Run round that last saw it. See `freshness.ts`. */
  seen: Record<string, number>;
}

function emptyTally(): ModeTally {
  return { rounds: 0, answered: 0, correct: 0, lastAt: null };
}

export function emptyNodeStats(): NodeStats {
  return {
    rating: RATING.start,
    rated: 0,
    answered: 0,
    correct: 0,
    byMode: { run: emptyTally(), drill: emptyTally(), growth: emptyTally(), repair: emptyTally() },
    bestRun: 0,
    lastAt: null,
    days: {},
  };
}

export const EMPTY_SCORE: ScoreState = { global: emptyNodeStats(), nodes: {}, rounds: [], seen: {} };

/** A saved tally from before rounds were called rounds, or before ratings. */
type Legacy<T> = Partial<T> & { games?: number; score?: number };

/**
 * Read a saved record, whatever it is missing.
 *
 * Points are deliberately *not* carried over: a save from the scoring era has
 * a `score` on every tally and a `total` on the state, and none of it is read
 * here, so every opening comes back unrated and earns its tier again. What the
 * player actually did — rounds, answers, days, streaks — is kept.
 */
export function normalizeScore(
  saved: (Partial<ScoreState> & { games?: RoundRecord[] }) | undefined,
): ScoreState {
  const tally = (saved: Legacy<ModeTally> | undefined): ModeTally => ({
    ...emptyTally(),
    answered: saved?.answered ?? 0,
    correct: saved?.correct ?? 0,
    lastAt: saved?.lastAt ?? null,
    rounds: saved?.rounds ?? saved?.games ?? 0,
  });
  const day = (saved: Legacy<DayTally>): DayTally => ({
    answered: saved.answered ?? 0,
    correct: saved.correct ?? 0,
    rounds: saved.rounds ?? saved.games ?? 0,
    rating: saved.rating ?? null,
  });
  const fix = (stats: Partial<NodeStats> | undefined): NodeStats => {
    const empty = emptyNodeStats();
    const byMode = { ...empty.byMode };
    for (const mode of ACTIVITY_MODES) byMode[mode] = tally(stats?.byMode?.[mode]);
    return {
      ...empty,
      rating: stats?.rating ?? RATING.start,
      rated: stats?.rated ?? 0,
      answered: stats?.answered ?? 0,
      correct: stats?.correct ?? 0,
      bestRun: stats?.bestRun ?? 0,
      lastAt: stats?.lastAt ?? null,
      byMode,
      days: Object.fromEntries(Object.entries(stats?.days ?? {}).map(([key, d]) => [key, day(d)])),
    };
  };
  const rounds = (saved?.rounds ?? saved?.games ?? []).map((round) => ({ ...round }));
  return {
    global: fix(saved?.global),
    nodes: Object.fromEntries(Object.entries(saved?.nodes ?? {}).map(([id, stats]) => [id, fix(stats)])),
    rounds,
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

/* ── results ────────────────────────────────────────────────────────────── */

/** One answer given somewhere in the app. */
export interface MoveResult {
  mode: ActivityMode;
  /** The line the position sits on — decides which openings it belongs to. */
  line: string[];
  color: Color;
  correct: boolean;
  /**
   * Whether this moves ratings. Only a prepared position answered in Run or
   * Autopilot does; everything else is recorded and nothing more.
   */
  rated: boolean;
  at: number;
}

/** How one opening's rating moved. */
export interface RatingMove {
  id: string;
  before: number;
  after: number;
  /** 1 promoted a tier, -1 demoted, 0 neither. */
  promotion: 1 | -1 | 0;
}

/**
 * Which openings an answer counts as activity for: the deepest node its line
 * goes through and every ancestor of it. Ids, shallowest first; empty when the
 * book names nothing along the line.
 */
export function creditedNodes(tree: OpeningTree, line: string[]): string[] {
  const deepest = deepestNodeAlong(tree, line);
  return deepest ? ancestorsOf(tree, deepest.id).map((node) => node.id) : [];
}

/**
 * Which starred openings a result rates: every one the line is inside, so a
 * Najdorf move moves a starred Najdorf and a starred Sicilian alike, while a
 * Dragon move moves the Sicilian and leaves the Najdorf alone. Regions are
 * matched on positions, so a transposition still counts.
 */
export function ratedNodes(tree: OpeningTree, starred: Iterable<string>, line: string[]): string[] {
  const out: string[] = [];
  for (const id of starred) {
    const node = tree.byId.get(id);
    if (!node || node.depth === 0 || out.includes(id)) continue;
    if (insideRegion(tree, node, line)) out.push(id);
  }
  return out.sort((a, b) => (tree.byId.get(a)?.depth ?? 0) - (tree.byId.get(b)?.depth ?? 0));
}

function tallyAnswer(stats: NodeStats, result: MoveResult): NodeStats {
  const mode = stats.byMode[result.mode];
  const key = dayKey(result.at);
  const day = stats.days[key] ?? { answered: 0, correct: 0, rounds: 0, rating: null };
  const correct = result.correct ? 1 : 0;
  return {
    ...stats,
    answered: stats.answered + 1,
    correct: stats.correct + correct,
    lastAt: result.at,
    byMode: {
      ...stats.byMode,
      [result.mode]: {
        ...mode,
        answered: mode.answered + 1,
        correct: mode.correct + correct,
        lastAt: result.at,
      },
    },
    days: {
      ...stats.days,
      [key]: { ...day, answered: day.answered + 1, correct: day.correct + correct },
    },
  };
}

function tallyRating(stats: NodeStats, result: MoveResult): { stats: NodeStats; move: RatingMove } {
  const before = stats.rating;
  const after = ratingAfter(before, result.correct);
  const key = dayKey(result.at);
  const day = stats.days[key] ?? { answered: 0, correct: 0, rounds: 0, rating: null };
  const climbed = rankOf(after).reached - rankOf(before).reached;
  return {
    stats: {
      ...stats,
      rating: after,
      rated: stats.rated + 1,
      days: { ...stats.days, [key]: { ...day, rating: after } },
    },
    move: { id: '', before, after, promotion: climbed > 0 ? 1 : climbed < 0 ? -1 : 0 },
  };
}

/**
 * Apply one answer: activity against the openings its line names, and the
 * rating of every starred opening it was played inside. Returns the ratings
 * that moved, shallowest opening first, for the bar to show.
 */
export function applyResult(
  state: ScoreState,
  tree: OpeningTree,
  starred: Iterable<string>,
  result: MoveResult,
): { state: ScoreState; moves: RatingMove[] } {
  const nodes = { ...state.nodes };
  for (const id of creditedNodes(tree, result.line)) {
    nodes[id] = tallyAnswer(nodes[id] ?? emptyNodeStats(), result);
  }
  const moves: RatingMove[] = [];
  if (result.rated) {
    for (const id of ratedNodes(tree, starred, result.line)) {
      const { stats, move } = tallyRating(nodes[id] ?? emptyNodeStats(), result);
      nodes[id] = stats;
      moves.push({ ...move, id });
    }
  }
  return {
    state: { ...state, global: tallyAnswer(state.global, result), nodes },
    moves,
  };
}

function tallyRound(stats: NodeStats, round: RoundRecord): NodeStats {
  const mode = stats.byMode[round.mode];
  const key = dayKey(round.at);
  const day = stats.days[key] ?? { answered: 0, correct: 0, rounds: 0, rating: null };
  return {
    ...stats,
    bestRun: round.mode === 'run' ? Math.max(stats.bestRun, round.correct) : stats.bestRun,
    lastAt: round.at,
    byMode: { ...stats.byMode, [round.mode]: { ...mode, rounds: mode.rounds + 1, lastAt: round.at } },
    days: { ...stats.days, [key]: { ...day, rounds: day.rounds + 1 } },
  };
}

/**
 * Log a finished round against the opening it was played in and every opening
 * above it. Ratings moved answer by answer as they were given; this counts the
 * round and remembers when.
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
 * Days in a row with at least one round, counting back from today — or from
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
