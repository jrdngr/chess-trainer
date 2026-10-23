import { applySan, fenTurn, positionKey, START_FEN, walkSan, type Color } from '../chess/core';
import { prepIndex } from './openingRun';
import type { Card, Repertoire } from './types';
import { missingPrep, type Focus, type Recommendation, type Start } from './recommend';
import { weakestFirst, type TrainingItem } from './session';
import { isDue } from './srs';

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
 *   inside   — the way into the opening is played for you. The default.
 *   position — the way to a position you're due on, or answer worst while
 *              your prep keeps missing, is played for you — see `positionStart`.
 *   first    — a Cold Start from move one, every `COLD_EVERY`th run, so the
 *              way in is tested too — see `coldStart`.
 */
/**
 * How often a Survival run starts from move one even where the
 * recommendation would start it inside an opening: once the last
 * `COLD_EVERY - 1` runs all started inside, the next is a Cold Start.
 *
 * Starting inside is how a run gets to the opening that needs the work, and
 * a selection that is itself a family starts every run there; but a game
 * never starts there, so now and then the way in is part of the test. A run
 * from move one for any reason counts, so a selection whose runs mostly
 * start there anyway is never pushed further.
 */
export const COLD_EVERY = 4;

/**
 * The recommendation as this run plays it: the same opening, side and focus,
 * but from move one when the last `COLD_EVERY - 1` runs all started inside.
 * The opponent is still steered toward the opening, from the first move.
 */
export function coldStart(pick: Recommendation, recentStarts: Start[]): Recommendation {
  if (pick.start === 'first') return pick;
  const tail = recentStarts.slice(-(COLD_EVERY - 1));
  const due = tail.length === COLD_EVERY - 1 && tail.every((start) => start === 'inside');
  return due ? { ...pick, start: 'first' } : pick;
}

/**
 * Where a run starts at a position, when it does: the one you're most
 * overdue on, or, with nothing due while your prep keeps missing in runs
 * (`missingPrep`), the one you answer worst. Never two runs running, so the
 * openings themselves still get played into, and never on a Cold Start.
 * A position at move one is no start at all: that is a Cold Start.
 */
export function positionStart(
  items: TrainingItem[],
  cards: Record<string, Card>,
  opts: { accuracy: number | null; lastWasPosition: boolean; now?: number },
): TrainingItem | null {
  if (opts.lastWasPosition) return null;
  const now = opts.now ?? Date.now();
  const reachable = items.filter((item) => item.pathSans.length > 0);
  const due = reachable
    .filter((item) => cards[item.cardId] && isDue(cards[item.cardId], now))
    .sort((a, b) => cards[a.cardId].due - cards[b.cardId].due);
  if (due.length) return due[0];
  if (missingPrep(opts.accuracy) === 0) return null;
  return weakestFirst(reachable.filter((item) => cards[item.cardId]), cards)[0] ?? null;
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
