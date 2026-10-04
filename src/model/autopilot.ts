import type { Color } from '../chess/core';
import type { Focus, Recommendation, Start } from './recommend';

/**
 * Autopilot: one round after another, each in the mode the work asks for,
 * without going back to Home in between.
 *
 * A round is one sitting of a mode, cut to a size that plays in a few
 * minutes: a Survival run, eight positions of Drill, three lines of Drill, or
 * one batch of Growth. Autopilot decides the mode, the opening and the side,
 * and what the mode would otherwise ask on its setup screen; your own saved
 * options in each mode decide how it plays — the clock, the feedback, the
 * explanations. Nothing on screen names the choice; the round is just there.
 *
 * Survival is the default: it is the most fun, the only mode that rates, and
 * the one that tests your prep the way a game does. The others come round
 * when the work asks loudly enough:
 *
 *   drillPositions — cards due, more of them the louder.
 *   drillLines     — lines no round has finished clean since they last
 *                    changed, which is what Growth leaves behind, and
 *                    lines whose own card is due.
 *   growth         — an opening every line of which is held, and nothing
 *                    owed: ready to widen.
 *
 * Each mode's weight is its fun times its need. A brake halves a mode's
 * weight for every one of the last few rounds it already had, and no mode
 * plays more than `MAX_RUN` rounds in a row while another has anything to
 * ask, so a standing backlog cannot lock the session into one mode.
 *
 * A Drill round, of positions or of lines, is always followed by Survival:
 * what was just drilled is tested at once, the way a game would, and two
 * drills never run back to back. Growth carries no such rule; what follows
 * it is weighed as usual, which is Drill lines while what it grew is new.
 *
 * A Survival run that starts from move one is a Cold Start: nothing is set
 * up for you, and you find your own way into the opening. Every `COLD_EVERY`th
 * run is one, whatever the recommendation's start — see `coldStart`.
 */
export type RoundMode = 'survival' | 'drillPositions' | 'drillLines' | 'growth';

/** How much each mode is worth at full need. Survival is always at full need. */
export const FUN: Record<RoundMode, number> = {
  survival: 1,
  drillPositions: 1.2,
  drillLines: 1.3,
  growth: 0.9,
};

/** The size of a round in each mode that has one. */
export const ROUND_SIZE = { drillPositions: 8, drillLines: 3 } as const;

/** Each recent round of the same mode multiplies its weight by this. */
export const MODE_BRAKE = 0.5;

/** How many recent rounds the brake looks back over. */
export const MODE_WINDOW = 5;

/** The most rounds of one mode in a row, while any other mode has work. */
export const MAX_RUN = 3;

/** Need from a count: `half` is the count that scores 0.5. */
function saturate(count: number, half: number): number {
  return count <= 0 ? 0 : count / (count + half);
}

/** How loudly each mode is asking, 0..1. Survival's is fixed. */
export interface ModeNeeds {
  /** Cards due inside the selection. */
  due: number;
  /** Lines inside the selection with no clean finish since they last changed. */
  unpracticed: number;
  /** Lines inside the selection whose line card is due. */
  dueLines?: number;
  /** Whether an opening in the selection is ready to grow. */
  growReady: boolean;
}

export function modeNeed(mode: RoundMode, needs: ModeNeeds): number {
  switch (mode) {
    case 'survival':
      return 1;
    case 'drillPositions':
      return saturate(needs.due, 8);
    case 'drillLines':
      // One unpracticed line is already enough to come before Survival: a
      // line just grown is drilled before it is tested.
      // A due line asks like due positions do, a line being worth a few.
      return Math.max(saturate(needs.unpracticed, 0.25), saturate(needs.dueLines ?? 0, 2));
    case 'growth':
      return needs.growReady ? 1 : 0;
  }
}

export const ROUND_MODES: RoundMode[] = ['survival', 'drillLines', 'drillPositions', 'growth'];

export interface ModeScore {
  mode: RoundMode;
  score: number;
}

/** The modes after which the next round is always Survival. */
export const DRILL_MODES: RoundMode[] = ['drillPositions', 'drillLines'];

/**
 * Every mode's weight for the next round, highest first. Ties go to the
 * earlier mode in `ROUND_MODES`, so Survival wins a tie. Right after a Drill
 * round, every other mode scores 0, so Survival comes next.
 */
export function rankModes(needs: ModeNeeds, recent: RoundMode[]): ModeScore[] {
  const window = recent.slice(-MODE_WINDOW);
  const scored = ROUND_MODES.map((mode) => {
    const repeats = window.filter((m) => m === mode).length;
    return { mode, score: FUN[mode] * modeNeed(mode, needs) * MODE_BRAKE ** repeats };
  });
  // A mode that has had the last MAX_RUN rounds sits out, if anything else asks.
  const tail = recent.slice(-MAX_RUN);
  const streak = tail.length === MAX_RUN && tail.every((m) => m === tail[0]) ? tail[0] : null;
  const others = scored.some((s) => s.mode !== streak && s.score > 0);
  const capped = scored.map((s) => (s.mode === streak && others ? { ...s, score: 0 } : s));
  // A Drill round is tested straight away: only Survival is left standing.
  const last = recent[recent.length - 1];
  const afterDrill = last !== undefined && DRILL_MODES.includes(last);
  const ruled = afterDrill ? capped.map((s) => (s.mode === 'survival' ? s : { ...s, score: 0 })) : capped;
  return ruled
    .map((s, i) => ({ ...s, i }))
    .sort((a, b) => b.score - a.score || a.i - b.i)
    .map(({ mode, score }) => ({ mode, score }));
}

export function chooseMode(needs: ModeNeeds, recent: RoundMode[]): RoundMode {
  return rankModes(needs, recent)[0].mode;
}

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
