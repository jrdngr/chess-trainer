import { applySan, fenTurn, positionKey, START_FEN, walkSan, type Color } from '../chess/core';
import { prepIndex } from './openingRun';
import type { Card, Repertoire } from './types';
import { missingPrep, type Focus, type Recommendation, type Start } from './recommend';
import { weakestFirst, type TrainingItem } from './session';
import { runNeed } from './srs';

/**
 * Autopilot: one Survival run after another, without going back to Home in
 * between. See `docs/autopilot.md` for what it is for.
 *
 * Every round is a run: it plays past your prep and ends on your first
 * blunder. What makes it Autopilot is that it decides each run for you — the
 * opening, the side and what the opponent steers into come from the
 * recommendation engine (`recommend.ts`) — and where the run starts, which is
 * how the drilling gets done without leaving the game:
 *
 *   position — the moves up to the opening's own position are played for
 *              you. The default. (`start: 'inside'` in the code, with no `at`.)
 *   inside   — the moves to one position deeper inside the opening are
 *              played for you: the one that needs it most. (`at`.)
 *   cold     — nothing is played for you: the run starts from move one and
 *              the opponent steers toward the opening, so the way in is
 *              yours to play. (`start: 'first'`.)
 *
 * What a start drills decides when it comes: see `chooseStart`. Need is
 * counted in runs, not days, so the more you play the sooner a position
 * comes back, and a week away changes nothing.
 */
export type StartKind = 'position' | 'inside' | 'cold';

export { RUNS_PER_DAY, runGap, runNeed } from './srs';

/** Runs the way into an opening goes unplayed before a cold start wants it. */
export const COLD_GAP = 6;

/** A cold start every this many runs at the latest, whatever the need. */
export const COLD_EVERY = 3;

/**
 * Your positions on the way into an opening, its moves from move one up to
 * its own position, and the ones inside it, past that position. The opening's
 * own position is the position start's.
 */
export function splitItems(items: TrainingItem[], openingPlies: number): { wayIn: TrainingItem[]; inside: TrainingItem[] } {
  return {
    wayIn: items.filter((item) => item.pathSans.length < openingPlies),
    inside: items.filter((item) => item.pathSans.length > openingPlies),
  };
}

/**
 * How much the way in wants playing: the runs since you last played its
 * stalest move yourself, over `COLD_GAP`. A move of the way in no run has
 * asked you counts as never played.
 */
export function coldNeed(wayIn: TrainingItem[], cards: Record<string, Card>, round: number): number {
  if (!wayIn.length) return 0;
  const since = wayIn.map((item) => {
    const tested = cards[item.cardId]?.testedRound;
    return tested === undefined ? Infinity : round - tested;
  });
  return Math.max(...since) / COLD_GAP;
}

/**
 * The position an inside start would begin at, and how much it wants it: the
 * one most overdue, in runs. With nothing due while your prep keeps missing
 * in runs (`missingPrep`), the one you answer worst, at need 1.
 */
export function insideStart(
  inside: TrainingItem[],
  cards: Record<string, Card>,
  opts: { accuracy: number | null; round: number; now?: number },
): { item: TrainingItem; need: number } | null {
  const now = opts.now ?? Date.now();
  const due = inside
    .filter((item) => cards[item.cardId])
    .map((item) => ({ item, need: runNeed(cards[item.cardId], opts.round, now) }))
    .filter((x) => x.need >= 1)
    .sort((a, b) => b.need - a.need);
  if (due.length) return due[0];
  if (missingPrep(opts.accuracy) === 0) return null;
  const weakest = weakestFirst(inside.filter((item) => cards[item.cardId]), cards)[0];
  return weakest ? { item: weakest, need: 1 } : null;
}

/**
 * Where the next run starts. A position start unless another start has more
 * need: an inside start when a position deeper in is due, a cold start when
 * the way in has gone unplayed long enough, the greater need when both do.
 * Neither comes twice running, and a cold start comes at least every
 * `COLD_EVERY` runs, counted across sessions.
 */
export function chooseStart(opts: {
  /** Autopilot's last starts, oldest first. */
  recent: StartKind[];
  cold: number;
  inside: number | null;
}): StartKind {
  const last = opts.recent[opts.recent.length - 1];
  const tail = opts.recent.slice(-(COLD_EVERY - 1));
  if (tail.length === COLD_EVERY - 1 && !tail.includes('cold')) return 'cold';
  const cold = last !== 'cold' && opts.cold >= 1 ? opts.cold : 0;
  const inside = last !== 'inside' && opts.inside !== null && opts.inside >= 1 ? opts.inside : 0;
  if (!cold && !inside) return 'position';
  return cold >= inside ? 'cold' : 'inside';
}

/** The kind of start a round was given. */
export function startKind(round: { pick: Pick<Recommendation, 'start'>; at: string[] | null }): StartKind {
  return round.at ? 'inside' : round.pick.start === 'first' ? 'cold' : 'position';
}

/** What each recommendation focus asks of a Survival run: the lines you would meet, or your weakest. */
export const LEAN_FOR: Record<Focus, 'popular' | 'weak'> = { test: 'popular', review: 'weak' };

/** What Autopilot decided a run should be — see `SurvivalPlan`. */
export function survivalPlanFor(
  pick: Recommendation,
  at: string[] | null = null,
): { color: Color; toward: string; enter: boolean; lean: 'popular' | 'weak'; at: string[] | null } {
  return {
    color: pick.color,
    toward: pick.opening.id,
    enter: pick.start === 'inside',
    lean: LEAN_FOR[pick.focus],
    at,
  };
}

/**
 * Where a run stands in your prep, for the segments Autopilot shows it with:
 * the plies played so far, out of the plies your prep reaches along the line.
 */
export interface PrepSpan {
  played: number;
  total: number;
  /** Plies played in the book past the prep, once its book phase has begun. */
  book?: number;
  /** The ply the prep leaves the book at, when it does: its segments from there are an extension's. */
  ext?: number;
}

/**
 * How many plies into `line` your prep reaches: up to and including your
 * last prepared move along it, stopping at the first move of yours it does
 * not have. The first `from` plies were played for you and count whatever
 * they were.
 */
export function prepDepth(line: string[], color: Color, prepAt: (fen: string) => string[], from = 0): number {
  let fen = START_FEN;
  let depth = 0;
  for (let i = 0; i < line.length; i += 1) {
    if (i < from) depth = i + 1;
    else if (fenTurn(fen) === color) {
      if (!prepAt(fen).includes(line[i])) break;
      depth = i + 1;
    }
    const move = applySan(fen, line[i]);
    if (!move) break;
    fen = move.after;
  }
  return depth;
}

/**
 * Where Autopilot's next run would start in your prep, for its button: the
 * way in played for you, out of how far your prep goes from there, on its
 * first choice in every position.
 */
export function roundSpan(rep: Repertoire | null, pick: Recommendation, at: string[] | null, limit = 60): PrepSpan {
  if (!rep) return { played: 0, total: 0 };
  const index = prepIndex(rep);
  const prepAt = (fen: string) => index.get(positionKey(fen)) ?? [];
  const way = at ?? (pick.start === 'inside' ? pick.opening.sans : []);
  const line = [...(at ?? pick.opening.sans)];
  const { fens } = walkSan(line);
  line.length = fens.length - 1;
  let fen = fens[fens.length - 1];
  while (line.length < limit) {
    const san = prepAt(fen)[0];
    const move = san ? applySan(fen, san) : null;
    if (!move) break;
    line.push(san);
    fen = move.after;
  }
  const total = prepDepth(line, pick.color, prepAt, way.length);
  return { played: Math.min(way.length, total), total };
}

/**
 * Mode Testing: Autopilot's runs in a cycle that plays every way a run can
 * begin before any repeats, for trying out how runs start.
 *
 * The cases are what the round intro treats differently — a run walked into
 * its opening, one walked to a position, a Cold Start from move one — each on
 * every side the selection covers, since a side whose opponent moves first
 * starts differently. A position start takes any position when none is owed;
 * a case that cannot run at all is skipped.
 */
export type TestVariant = 'survival' | 'position' | 'coldStart';

export const TEST_VARIANTS: TestVariant[] = ['survival', 'position', 'coldStart'];

export interface TestCase {
  variant: TestVariant;
  color: Color;
}

/** Where a test case starts its run. */
export type ForcedStart = Start | 'position';

export function forcedStart(variant: TestVariant): ForcedStart {
  switch (variant) {
    case 'survival':
      return 'inside';
    case 'coldStart':
      return 'first';
    default:
      return 'position';
  }
}

/** One cycle: every variant on every side, shuffled. */
export function testCycle(colors: Color[], rand: () => number): TestCase[] {
  const cases = TEST_VARIANTS.flatMap((variant) => colors.map((color) => ({ variant, color })));
  for (let i = cases.length - 1; i > 0; i -= 1) {
    const j = Math.floor(rand() * (i + 1));
    [cases[i], cases[j]] = [cases[j], cases[i]];
  }
  return cases;
}
