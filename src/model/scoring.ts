import type { Color } from '../chess/core';
import { markSeen } from './freshness';
import {
  ancestorsOf,
  deepestNodeAlong,
  type OpeningTree,
} from './openingTree';

/**
 * The rating: how well you know one opening.
 *
 * There is no global score any more, and no points. Every opening you have
 * starred carries a rating of its own, and nothing else is rated: a star is
 * the player saying "this one is mine", and the rating answers how well they
 * have it. Only Survival moves it: it is where your prep is tested in a real
 * game, with nothing telling you what the line is. Drill, Growth and Play
 * still record what they did, because rounds, accuracy and streaks are
 * activity rather than assessment, but none of them changes a rating.
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
 * The modes whose activity is tallied. Only `rated` results move a rating,
 * and only Survival produces those. `run` is the old Autopilot round's, and
 * `repair` the old Repair mode's: both are kept for history and no longer
 * played.
 */
export type ActivityMode = 'run' | 'survival' | 'drill' | 'growth' | 'repair';

export const ACTIVITY_MODES: ActivityMode[] = ['run', 'survival', 'drill', 'growth', 'repair'];

/* ── the rating ─────────────────────────────────────────────────────────── */

export const RATING = {
  /** Where an opening starts the moment it is starred. */
  start: 0,
  /** It never goes below this, so a bad session cannot dig a hole. */
  floor: 0,
  /**
   * The most one result can move a rating, split between the two outcomes by
   * the accuracy the rating expects. 20 puts Mastered near eight hundred correct
   * answers, so a piece is earned over many runs rather than one good
   * sitting, and a miss at the top costs less than it once did.
   */
  step: 20,
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
 * The ladder, named for how well you know the opening. Each rung is a real
 * step in accuracy rather than a round number, so a promotion is rare enough
 * to mean something: Learning is roughly 62% of your prepared moves found,
 * Familiar 78%, Solid 88%, Strong 94%, Fluent 97%, Mastered 99%.
 */
export const TIERS: Tier[] = [
  { name: 'Learning', color: '#94a3b8', at: 100 },
  { name: 'Familiar', color: '#4ade80', at: 250 },
  { name: 'Solid', color: '#2dd4bf', at: 400 },
  { name: 'Strong', color: '#3b82f6', at: 550 },
  { name: 'Fluent', color: '#a855f7', at: 700 },
  { name: 'Mastered', color: '#facc15', at: 850 },
];

/**
 * Below the first rung. It reads New until Survival has rated the opening at
 * all, and Shaky once it has: one says go and start it, the other go and fix
 * it.
 */
export const UNRATED: Tier = { name: 'Shaky', color: '#4b4b55', at: 0 };
export const NEW_LABEL = 'New';

export interface Rank {
  rating: number;
  /** Tiers reached; 0 is unrated. */
  reached: number;
  /** The tier held, or null below the first rung. */
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

/**
 * Where a rating stands on the ladder. `rated` is how many results have moved
 * it; it only decides whether an opening below the first rung reads New or
 * Shaky, and is left out where a rating has just moved.
 */
export function rankOf(rating: number, rated = 1): Rank {
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
    heldLabel: held?.name ?? (rated > 0 ? UNRATED.name : NEW_LABEL),
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
   * The rating. Any opening Survival has reached can be rated, favorite or
   * not; the global record is never rated at all: it is activity, not
   * assessment.
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
 * One round: a Survival run, a Drill session or line, or a Growth run.
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
   * A Survival run's prepared positions: how many it asked and how many you
   * found. What the round mix reads as your prep accuracy.
   */
  prep?: { asked: number; found: number };
  /**
   * The line the round was about — the one the opponent was steering toward,
   * whether or not it was reached, or the line finished when `perfect`. What
   * the next rounds should not be. Only rounds that play a line carry one.
   */
  line?: string[];
}

export interface ScoreState {
  /** Activity for the whole game. Never rated. */
  global: NodeStats;
  nodes: Record<string, NodeStats>;
  rounds: RoundRecord[];
  /** Position key → the line round that last saw it. See `freshness.ts`. */
  seen: Record<string, number>;
  /**
   * How many rounds have played a line: Survival runs, line drills, and the
   * old Autopilot rounds. The clock freshness is read against.
   */
  lineRounds: number;
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
    byMode: { run: emptyTally(), survival: emptyTally(), drill: emptyTally(), growth: emptyTally(), repair: emptyTally() },
    bestRun: 0,
    lastAt: null,
    days: {},
  };
}

export const EMPTY_SCORE: ScoreState = { global: emptyNodeStats(), nodes: {}, rounds: [], seen: {}, lineRounds: 0 };

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
  const global = fix(saved?.global);
  return {
    global,
    nodes: Object.fromEntries(Object.entries(saved?.nodes ?? {}).map(([id, stats]) => [id, fix(stats)])),
    rounds,
    seen: saved?.seen ?? {},
    // Saves from before Survival counted here marked `seen` by Autopilot's
    // round count, so the clock carries on from there.
    lineRounds: saved?.lineRounds ?? global.byMode.run.rounds,
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
   * Whether this moves ratings. Only a prepared position answered in
   * Survival does; everything else is recorded and nothing more.
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
 * Which openings a rated answer counts for: every one its line has actually
 * reached, favorite or not — the same openings it counts as activity for.
 * Matched on positions, so a transposition still counts. An opening the line
 * could still head into does not: 1.e4 rates the Najdorf only in a run that
 * gets there, and then through `applyResult`'s catch-up.
 */
export function ratedNodes(tree: OpeningTree, line: string[]): string[] {
  return creditedNodes(tree, line);
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
 * Rate one run's answers into the openings `line` has reached. An opening
 * reached for the first time this run first takes every earlier answer of the
 * run, in order, so the lead-in to a Najdorf counts once the run becomes one;
 * then `result`, when there is one, rates every opening reached. Returns one
 * move per opening touched, from where it stood to where it ends up.
 */
function rateRun(
  nodes: Record<string, NodeStats>,
  tree: OpeningTree,
  earlier: MoveResult[],
  line: string[],
  result: MoveResult | null,
): RatingMove[] {
  const before = new Map<string, number>();
  const rate = (id: string, answer: MoveResult) => {
    const stats = nodes[id] ?? emptyNodeStats();
    if (!before.has(id)) before.set(id, stats.rating);
    nodes[id] = tallyRating(stats, answer).stats;
  };
  const reached = ratedNodes(tree, line);
  // Lines only grow within a run, so an opening an earlier answer reached
  // already has every answer before it.
  const rated = new Set(earlier.flatMap((answer) => ratedNodes(tree, answer.line)));
  for (const id of reached) if (!rated.has(id)) for (const answer of earlier) rate(id, answer);
  if (result) for (const id of reached) rate(id, result);
  return [...before].map(([id, was]) => {
    const after = nodes[id].rating;
    const climbed = rankOf(after).reached - rankOf(was).reached;
    return { id, before: was, after, promotion: climbed > 0 ? 1 : climbed < 0 ? -1 : 0 };
  });
}

/**
 * Apply one answer: activity against the openings its line names, and, when
 * it is rated, the rating of every opening its line has reached. `earlier` is
 * the run's rated answers before this one, which an opening reached for the
 * first time takes too. Returns the ratings that moved, shallowest opening
 * first, for the bar to show.
 */
export function applyResult(
  state: ScoreState,
  tree: OpeningTree,
  result: MoveResult,
  earlier: MoveResult[] = [],
): { state: ScoreState; moves: RatingMove[] } {
  const nodes = { ...state.nodes };
  for (const id of creditedNodes(tree, result.line)) {
    nodes[id] = tallyAnswer(nodes[id] ?? emptyNodeStats(), result);
  }
  const moves = result.rated ? rateRun(nodes, tree, earlier, result.line, result) : [];
  return {
    state: { ...state, global: tallyAnswer(state.global, result), nodes },
    moves,
  };
}

/**
 * A run is over and its line went further than its last answer: the openings
 * only that last stretch reached take the run's rated answers too.
 */
export function settleRun(
  state: ScoreState,
  tree: OpeningTree,
  earlier: MoveResult[],
  line: string[],
): { state: ScoreState; moves: RatingMove[] } {
  if (earlier.length === 0) return { state, moves: [] };
  const nodes = { ...state.nodes };
  const moves = rateRun(nodes, tree, earlier, line, null);
  return moves.length ? { state: { ...state, nodes }, moves } : { state, moves };
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
  // A round that played a line is one the next should not repeat; the count
  // of them is the clock freshness is read against.
  const lineRounds = state.lineRounds + (round.line ? 1 : 0);
  const seen = round.line ? markSeen(state.seen, round.line, lineRounds) : state.seen;
  return {
    ...state,
    global,
    nodes,
    rounds: [...state.rounds, round],
    seen,
    lineRounds,
  };
}

/** What the rounds so far have been about, for the draw and the scorer. */
export function seenIn(state: ScoreState): { at: Record<string, number>; round: number } {
  return { at: state.seen, round: state.lineRounds };
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

/**
 * Where a rating stood at the end of a day: the last day at or before it that
 * moved the rating, or the start if none had.
 */
export function ratingOn(stats: NodeStats, key: string): number {
  let at: string | null = null;
  let rating: number = RATING.start;
  for (const [day, tally] of Object.entries(stats.days)) {
    if (tally.rating === null || day > key || (at !== null && day < at)) continue;
    at = day;
    rating = tally.rating;
  }
  return rating;
}

/** How far a rating has moved over the last `days` days. */
export function ratingChange(stats: NodeStats, days: number, now = Date.now()): number {
  return stats.rating - ratingOn(stats, dayKey(now - days * 86_400_000));
}
