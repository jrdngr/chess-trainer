import type { Color } from '../chess/core';
import type { Focus, Recommendation, RoundMode, Start } from './recommend';

/**
 * Autopilot: one round after another, each in the mode the work asks for,
 * without going back to Home in between.
 *
 * A round is one sitting of a mode, cut to a size that plays in a few
 * minutes: a Survival run, eight positions of Drill, a few lines of Drill up
 * to `LINE_BUDGET` of your moves, or one batch of Growth. Which mode comes
 * next is the recommendation engine's — see "Which mode a round is in" in
 * `recommend.ts` — as is the opening, the side and what the mode would
 * otherwise ask on its setup screen; your own saved options in each mode
 * decide how it plays — the clock, the feedback, the explanations.
 *
 * A Survival run that starts from move one is a Cold Start: nothing is set
 * up for you, and you find your own way into the opening. Every `COLD_EVERY`th
 * run is one, whatever the recommendation's start — see `coldStart`.
 */
export { chooseMode, DRILL_MODES, rankModes, ROUND_MODES, type ModeScore, type RoundMode } from './recommend';

/** The size of a round of Drill positions. Drill lines is sized by `LINE_BUDGET`. */
export const ROUND_SIZE = { drillPositions: 8 } as const;

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

/** What each recommendation focus asks of a Survival run: the lines you would meet, or your weakest. */
export const LEAN_FOR: Record<Focus, 'popular' | 'weak'> = { test: 'popular', review: 'weak' };

/** What Autopilot decided a Survival round should be — see `SurvivalPlan`. */
export function survivalPlanFor(pick: Recommendation): { color: Color; toward: string; enter: boolean; lean: 'popular' | 'weak' } {
  return {
    color: pick.color,
    toward: pick.opening.id,
    enter: pick.start === 'inside',
    lean: LEAN_FOR[pick.focus],
  };
}

export const MODE_LABELS: Record<RoundMode, string> = {
  survival: 'Survival',
  drillPositions: 'Drill positions',
  drillLines: 'Drill lines',
  growth: 'Growth',
};

/** A Survival run from move one, by its banner name. */
export const COLD_START_LABEL = 'Survival: Cold Start';

/** A round's name as Autopilot announces it. */
export function roundLabel(mode: RoundMode, start?: Start): string {
  return mode === 'survival' && start === 'first' ? COLD_START_LABEL : MODE_LABELS[mode];
}

/**
 * Mode Testing: Autopilot's rounds in a cycle that plays every way a round
 * can begin before any repeats, for trying out how rounds start.
 *
 * The cases are what the round intro treats differently — a run walked into
 * its opening, a Cold Start from move one, the way to a Drill position played
 * out, a line drilled from move one, Growth walked to its hole — each on
 * every side the selection covers, since a side whose opponent moves first
 * starts differently. A case whose mode has nothing to do is forced where
 * it can run at all, and skipped where it cannot.
 */
export type TestVariant = 'survival' | 'coldStart' | 'drillPositions' | 'drillLines' | 'growth';

export const TEST_VARIANTS: TestVariant[] = ['survival', 'coldStart', 'drillPositions', 'drillLines', 'growth'];

export interface TestCase {
  variant: TestVariant;
  color: Color;
}

/** What a test case asks of the round picker: its mode, and for Survival where it starts. */
export interface ForcedRound {
  mode: RoundMode;
  start?: Start;
}

export function forcedRound(variant: TestVariant): ForcedRound {
  switch (variant) {
    case 'survival':
      return { mode: 'survival', start: 'inside' };
    case 'coldStart':
      return { mode: 'survival', start: 'first' };
    default:
      return { mode: variant };
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
