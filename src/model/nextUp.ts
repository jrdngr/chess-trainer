import type { GrowthRow } from './growth';
import type { DrillDraw } from './modes';
import type { OpeningRunRecord } from './openingRun';
import type { RepairItem } from './repair';
import type { Repertoire } from './types';

/**
 * What to do next.
 *
 * Every mode here is worth doing and none of them is worth doing forever. Left
 * to the grid, a player picks the one they like and the rest quietly rot: the
 * schedule falls behind, the repertoire stops widening, the mistakes from real
 * games never get looked at. Next Up answers the one question the grid does not
 * — of these five, which one, now — and then starts it, so the answer costs a
 * tap rather than a decision.
 *
 * Two things decide it. **Pressure** is how loudly a mode is asking: cards due,
 * holes in the prep, positions your own games disagree with. It is scaled onto
 * one shared 0..1 scale so forty due cards and an unanswered first move can be
 * compared at all. **Staleness** is how long it has been since you last did
 * that mode, measured against the others rather than against the clock — the
 * mode you have gone longest without gets the biggest push, whether that is an
 * hour or a month. Pressure alone would pin a big schedule to Drill forever;
 * staleness alone would march you round the four regardless of what is actually
 * waiting. Multiplied, a mode with real work rises as it is neglected, and a
 * mode with nothing to do stays where it is however long you ignore it.
 *
 * Play is deliberately not in here. It is the one mode with no backlog to
 * measure — there is no such thing as a game you are overdue to play — and
 * recommending it would mean recommending it on a coin flip.
 */

/** The modes Next Up chooses between. */
export type NextUpMode = 'drill' | 'openingRun' | 'repair' | 'growth';

/* ── what you have been doing ───────────────────────────────────────────── */

/**
 * When each mode last did something for you.
 *
 * Opening Run is absent because it has kept its own `lastAt` since long before
 * this, and one event with two timestamps is one too many. Play is absent
 * because Next Up never recommends it, and a number nothing reads is a number
 * that goes wrong quietly.
 */
export type ActivityMode = Exclude<NextUpMode, 'openingRun'>;
export type Activity = Record<ActivityMode, number | null>;

export const NO_ACTIVITY: Activity = { drill: null, repair: null, growth: null };

/** A save from before any of this was recorded simply reads as "never". */
export function normalizeActivity(saved: Partial<Activity> | undefined): Activity {
  return { ...NO_ACTIVITY, ...(saved ?? {}) };
}

/** Remember that a mode was just used. */
export function noted(activity: Activity, mode: ActivityMode, at = Date.now()): Activity {
  return { ...activity, [mode]: at };
}

/* ── pressure ───────────────────────────────────────────────────────────── */

/**
 * Diminishing returns on a count: `half` is the count that scores 0.5.
 *
 * Every mode's backlog wants this shape. The difference between two due cards
 * and twenty is the whole decision; the difference between two hundred and four
 * hundred is not a decision at all, and a linear count would let one enormous
 * backlog drown out every other mode in the app permanently.
 */
function saturate(count: number, half: number): number {
  return count <= 0 ? 0 : count / (count + half);
}

function clamp(n: number): number {
  return Math.max(0, Math.min(1, n));
}

/**
 * Review debt. Cards that are due are the closest thing the app has to a
 * deadline, so they lead; unseen positions are worth doing but are never
 * urgent, which is why learning tops out well below reviewing.
 */
export function drillPressure(due: number, unseen: number, newPerSession: number): number {
  const review = 0.9 * saturate(due, 24);
  const learn = 0.5 * saturate(Math.min(unseen, Math.max(newPerSession, 0)), 4);
  return clamp(Math.max(review, learn));
}

/**
 * How much a hole costs, which is how often you fall into it: how early it
 * sits, and how often the reply is actually played. A first-move reply you
 * cannot meet costs a quarter of your games as that colour; the same share at
 * move nine costs almost none of them.
 */
export function growthPressure(rows: GrowthRow[]): number {
  const top = rows[0];
  if (!top) return 0;
  const early = 1 / (1 + top.depth / 3);
  const played = saturate(top.topShare, 5);
  // Breadth counts for a little. A dozen openings to extend is a thinner
  // repertoire than one, even when the worst hole in each is the same.
  const breadth = 1 + 0.05 * Math.min(rows.length - 1, 4);
  return clamp(1.5 * early * played * breadth);
}

/**
 * What your own games disagree with your prep about.
 *
 * Weighted both ways on purpose: one position you have reached in six games and
 * lost four of them is a session's work on its own, and so is a long tail of
 * small ones. `weight` already folds in how often a position came up and what
 * it cost you.
 */
export function repairPressure(items: RepairItem[]): number {
  if (items.length === 0) return 0;
  const worst = items.reduce((max, item) => Math.max(max, item.weight), 0);
  return clamp(0.55 * saturate(worst, 5) + 0.45 * saturate(items.length, 8));
}

/**
 * Opening Run is the only mode here with no queue behind it, because what it
 * measures is not a backlog but a question: does the prep hold up when nothing
 * on screen tells you what it is? That question is always worth asking, which
 * is the baseline, and it gets sharper the more prep you have added since the
 * last time you asked it.
 */
export function openingRunPressure(untested: number, runs: number): number {
  const base = 0.4 + 0.4 * saturate(untested, 10);
  // Never run at all: the grid says "start here", and so does this.
  return clamp(runs === 0 ? Math.max(base, 0.55) : base);
}

/** Moves written into the repertoire since the last run tested any of it. */
export function untestedSince(reps: Repertoire[], lastAt: number | null): number {
  const since = lastAt ?? 0;
  let count = 0;
  for (const rep of reps) {
    for (const node of Object.values(rep.nodes)) if (node.addedAt > since) count += 1;
  }
  return count;
}

/* ── ranking ────────────────────────────────────────────────────────────── */

/**
 * How much the mode you have gone longest without can outweigh the mode you did
 * last. At 2, the stalest mode counts triple, which is enough to break out of a
 * standing backlog but not enough to send you to a mode with almost nothing in
 * it.
 */
export const STALENESS = 2;

/** One mode, with everything the ranking needs to place it. */
export interface Work {
  mode: NextUpMode;
  /** 0..1, on a scale shared with the other modes. */
  pressure: number;
  /** When this mode last did something for you. Null means never. */
  lastAt: number | null;
}

export interface Candidate extends Work {
  /** pressure × staleness. Only meaningful against the others in one ranking. */
  score: number;
}

export interface NextUpInput {
  /** Cards the schedule wants back today, across every repertoire. */
  due: number;
  /** Positions in the repertoire that have never been asked. */
  unseen: number;
  /** How many of those one drill session is willing to introduce. */
  newPerSession: number;
  /** Openings with holes, shallowest first — `growthRows()`. */
  growth: GrowthRow[];
  /** What your games disagree with — `buildRepairs()`. */
  repairs: RepairItem[];
  /** For counting prep added since the last run. */
  reps: Repertoire[];
  openingRun: OpeningRunRecord;
  activity: Activity;
}

/**
 * Every mode that could be started right now, unranked.
 *
 * A mode with nothing to work on is not offered at all: there is no honest way
 * to recommend Repair to someone who has imported no games, and "Growth (0
 * holes)" would be a button that opens onto an empty screen. Opening Run is the
 * exception and is always here, because the book can hand out a line whether or
 * not you have prepared one — which is what makes it the answer on a brand new
 * install, where nothing else can run at all.
 */
export function candidates(input: NextUpInput): Work[] {
  const out: Work[] = [];

  if (input.due > 0 || input.unseen > 0) {
    out.push({
      mode: 'drill',
      pressure: drillPressure(input.due, input.unseen, input.newPerSession),
      lastAt: input.activity.drill,
    });
  }

  if (input.growth.length > 0) {
    out.push({
      mode: 'growth',
      pressure: growthPressure(input.growth),
      lastAt: input.activity.growth,
    });
  }

  if (input.repairs.length > 0) {
    out.push({
      mode: 'repair',
      pressure: repairPressure(input.repairs),
      lastAt: input.activity.repair,
    });
  }

  const untested = untestedSince(input.reps, input.openingRun.lastAt);
  out.push({
    mode: 'openingRun',
    pressure: openingRunPressure(untested, input.openingRun.runs),
    lastAt: input.openingRun.lastAt,
  });

  return out;
}

/**
 * Score and sort, best first.
 *
 * Staleness is read off the other modes rather than off the clock: a mode's
 * place in the queue is how many of the things you could be doing instead you
 * have left longer than this one. The mode nothing has been left longer than is
 * the stalest, whether that means an hour or a month, which is what makes the
 * same rotation work for someone who opens the app daily and someone who opens
 * it twice a year.
 *
 * Modes you have never touched are all equally stale and share the front of
 * that queue rather than splitting it between them: "never" is not something
 * one mode can have done more recently than another.
 */
export function rank(list: Work[]): Candidate[] {
  const when = (c: Work) => c.lastAt ?? 0;
  const scored = list.map((cand) => {
    const staler = list.filter((other) => when(other) < when(cand)).length;
    const freshness = list.length < 2 ? 1 : 1 - staler / (list.length - 1);
    return { ...cand, score: cand.pressure * (1 + STALENESS * freshness) };
  });
  // Pressure breaks a tie: two modes equally neglected, the one with more
  // waiting wins. Mode order breaks the rest, so the answer never flickers
  // between two identical states.
  return scored.sort(
    (a, b) => b.score - a.score || b.pressure - a.pressure || ORDER[a.mode] - ORDER[b.mode],
  );
}

const ORDER: Record<NextUpMode, number> = { drill: 0, growth: 1, repair: 2, openingRun: 3 };

/** The one mode to start, and why. Never null: Opening Run always qualifies. */
export function nextUp(input: NextUpInput): Candidate {
  return rank(candidates(input))[0];
}

/**
 * Which draw a recommended drill session should use.
 *
 * Your own choice, unless it would open onto nothing. Someone who last drilled
 * "new only" and has since seen everything is being sent to Drill because cards
 * are *due*, and handing them an empty session would make the button a lie
 * about what it starts.
 */
export function drillDraw(preferred: DrillDraw, due: number, unseen: number): DrillDraw {
  if (preferred === 'new' && unseen === 0) return 'due';
  if (preferred === 'due' && due === 0 && unseen > 0) return 'new';
  return preferred;
}

export const MODE_NAMES: Record<NextUpMode, string> = {
  drill: 'Drill',
  growth: 'Growth',
  repair: 'Repair',
  openingRun: 'Run',
};
