import type { Color } from '../chess/core';
import { positionKey } from '../chess/core';
import { lineStaleness, NOTHING_SEEN, type Seen } from './freshness';
import {
  descendantsOf,
  nodeById,
  regionsOf,
  starredWithin,
  type OpeningNode,
  type OpeningTree,
} from './openingTree';
import type { RepairItem } from './repair';
import { leafLines } from './repertoire';
import { colorsOf, type Selection } from './selection';
import { allItems, type TrainingItem } from './session';
import { nodeStats, type ActivityMode, type ScoreState } from './scoring';
import { isDue } from './srs';
import type { Card, Repertoire } from './types';

/**
 * What the next round should be: an opening inside the selection, a colour,
 * and a focus — what the opponent steers toward.
 *
 * Every round under Autopilot is a Run of what you already have. Autopilot
 * never adds to the repertoire — building is Growth's, and the reveal's —
 * so what changes between rounds is only what the opponent steers you
 * toward, and that is the focus:
 *
 *   test    — lines drawn by how often you would meet them. Whether the prep
 *             holds up when nothing says what it is.
 *   review  — lines drawn toward the positions you are worst at or due on.
 *             Repetition, where it is needed.
 *
 * Every candidate is a focus, an opening and a colour together, because the
 * factors that decide it are per-opening factors. Need is how loudly the
 * work is asking — cards due, prep no run has tested. Staleness is how long
 * that opening has gone without a run, measured against the other
 * candidates rather than the clock — and a Test asks only as loudly as the
 * line it would run has been left, so a line just built is run once and the
 * others come round before it runs again (see `freshness.ts`). Depth is how
 * far below the selection the opening sits: the selection itself, played
 * from move one and following the player wherever they go, is where most
 * rounds should be spent; a first move next; a family after that; a
 * variation least. A star on the opening or anything above it lifts it one
 * level. And a brake cuts a focus's weight for every one of the last few
 * rounds it was, so a standing backlog cannot lock the session into one
 * focus.
 *
 * Need is measured on everything inside a node, so a family always asks at
 * least as loudly as any of its variations. A Review that wins is then
 * narrowed downward while a variation holds most of its parent's need —
 * most of it, and more of it the deeper the variation — so a round is
 * steered to the variation that actually wants it and left at the family
 * when the need is spread thin. A Test is never narrowed: it is always the
 * selection, from move one, with the opponent reacting to what is played.
 *
 * With nothing prepared inside the selection there is nothing to drill, and
 * the engine says so rather than inventing a round: see `recommend`.
 */
export type Focus = 'test' | 'review';

export const FOCUSES: Focus[] = ['test', 'review'];

/**
 * How much each level below the selection is worth.
 *
 * The selection is 1, a first move under it 0.6, a family 0.36, a variation
 * 0.22 and so on. Staleness can lift a candidate to three times its need, so
 * a family left alone while the selection was just played still comes round;
 * a fresh one does not.
 */
export const DEPTH = 0.6;

/** How much the stalest candidate can outweigh the freshest. */
export const STALENESS = 2;

/**
 * Each recent round of the same focus multiplies its weight by this.
 *
 * Half, so that three rounds of one focus running leaves it an eighth of its
 * voice: a focus with real work behind it still comes round, and nothing
 * takes the table for five rounds because its need is steady.
 */
export const BRAKE = 0.5;

/** How many recent rounds the brake looks back over. */
export const BRAKE_WINDOW = 5;

/**
 * How many rounds from move one must pass between rounds steered into an
 * opening below the selection.
 *
 * Narrowing reads how concentrated the work is, and a repertoire of one line
 * per opening concentrates all of it at every level: every Review would
 * start inside the deepest variation there is. A round started inside is
 * the exception, so the session spaces them: with an opening steered to in
 * the last three rounds, the ranking and the narrowing both stop at the
 * openings a round can start from move one.
 */
export const STEER_GAP = 3;

/** Whether one of the last few rounds was steered into an opening below the selection. */
export function steeredRecently(recentSteered: boolean[]): boolean {
  return recentSteered.slice(-STEER_GAP).some(Boolean);
}

/**
 * The share of its parent's work a variation must hold to be steered toward.
 *
 * Rises with the level: half for a first move under the selection, two
 * thirds for a family, three quarters for a variation. A star takes a level
 * off. Steering a round at a deeper opening starts it in that opening's
 * position (see `Recommendation.start`), which skips the way in and cannot
 * be played out of, so it is asked for less the further in it goes.
 */
export function narrowingBar(level: number): number {
  const at = Math.max(1, level);
  return at / (at + 1);
}

/** A star is worth one level: a starred family ranks like a first move. */
export function effectiveLevel(level: number, starred: boolean): number {
  return Math.max(0, level - (starred ? 1 : 0));
}

/**
 * Whether a round on this opening starts in its position rather than from
 * move one. A first move is not a position worth starting in: a round toward
 * 1.e4 as Black is a round from move one where the opponent opens 1.e4.
 */
export function startsInside(opening: OpeningNode): boolean {
  return opening.depth >= 2;
}

/**
 * Whether a round was steered: started inside an opening below the
 * selection. A selection that is itself a family starts every round inside
 * it, and that is the selection's doing, not the engine's.
 */
export function isSteered(pick: Pick<Recommendation, 'opening' | 'start'>, selection: Selection): boolean {
  return pick.start === 'inside' && pick.opening.id !== selection.opening;
}

export interface Candidate {
  focus: Focus;
  openingId: string;
  color: Color;
  /** 0..1, how loudly this asks. */
  need: number;
  /** How many pieces of work sit strictly inside this opening, for narrowing. */
  work: number;
  lastAt: number | null;
  starred: boolean;
  /** How many levels below the selection the opening sits; 0 for the selection itself. */
  level: number;
  /** need × staleness × depth × brake. Only comparable within one ranking. */
  score: number;
}

/**
 * Where a round begins.
 *
 *   first  — from move one. The opponent opens, or you do, and whatever you
 *            play the round follows: the opening is only what the opponent
 *            is steered toward, never a fence.
 *   inside — in the opening's own position, the moves to it already played.
 *            The round is spent on that opening and nothing else.
 */
export type Start = 'first' | 'inside';

export interface Recommendation {
  focus: Focus;
  opening: OpeningNode;
  color: Color;
  start: Start;
}

export interface RecommendInput {
  tree: OpeningTree;
  selection: Selection;
  reps: Repertoire[];
  cards: Record<string, Card>;
  /** Repairs already scoped to the selection's region and colours. */
  repairs: RepairItem[];
  score: ScoreState;
  starred: string[];
  newPerSession: number;
  /** The focuses of the session's rounds so far, oldest first, for the brake. */
  recentFocuses: Focus[];
  /** For each of those rounds, whether it was steered into an opening below the selection — see `STEER_GAP`. */
  recentSteered?: boolean[];
  /** What the last few rounds were about — see `freshness.ts`. */
  seen?: Seen;
  now?: number;
}

/* ── need ───────────────────────────────────────────────────────────────── */

/**
 * Diminishing returns on a count: `half` is the count that scores 0.5.
 *
 * The difference between two due cards and twenty is the whole decision; the
 * difference between two hundred and four hundred is not a decision at all.
 */
export function saturate(count: number, half: number): number {
  return count <= 0 ? 0 : count / (count + half);
}

function clamp(n: number): number {
  return Math.max(0, Math.min(1, n));
}

/**
 * Review debt. Cards that are due are the closest thing the app has to a
 * deadline, so they lead; unseen positions are worth doing but never urgent.
 */
export function reviewNeed(due: number, unseen: number, newPerSession: number): number {
  const review = 0.9 * saturate(due, 24);
  const learn = 0.5 * saturate(Math.min(unseen, Math.max(newPerSession, 0)), 4);
  return clamp(Math.max(review, learn));
}

/**
 * A Test has no queue behind it: what it measures is whether the prep holds
 * up when nothing on screen says what it is. That is always worth asking,
 * and more so the more prep has been added since it was last asked here —
 * but mostly as loudly as the line it would run has been left. An opening
 * whose every line the last rounds were drawn on has little to test yet,
 * whatever the prep in it; one with a line never run asks at full voice.
 * That one factor is what keeps a young repertoire from being the same
 * round over and over: a line just built has never run, so Test takes it;
 * once it has, the other openings and a Review come round before it again.
 * Never quite silent, though: Autopilot has nothing but your lines to run,
 * and a line just run is still a round when nothing else asks.
 */
export function testNeed(untested: number, everRun: boolean, stalest = 1): number {
  const base = 0.4 + 0.4 * saturate(untested, 10);
  const left = TEST_FLOOR + (1 - TEST_FLOOR) * clamp(stalest);
  return clamp((everRun ? base : Math.max(base, 0.55)) * left);
}

/** How much of a Test's voice is left once every line in it was just run. */
export const TEST_FLOOR = 0.25;

/* ── ranking ────────────────────────────────────────────────────────────── */

/**
 * How many of the last few rounds were this focus.
 *
 * Counted over a window rather than only consecutively: two focuses taking
 * turns would never trip a consecutive brake, and would leave a third focus
 * with real work waiting for ever.
 */
export function recentCount(recentFocuses: Focus[], focus: Focus): number {
  return recentFocuses.slice(-BRAKE_WINDOW).filter((f) => f === focus).length;
}

/**
 * Score and sort, best first.
 *
 * Staleness is read off the other candidates rather than off the clock: the
 * candidate nothing has been left longer than is the stalest, whether that is
 * an hour or a month. Candidates never played are all equally stale.
 */
export function rank(list: Omit<Candidate, 'score'>[], recentFocuses: Focus[]): Candidate[] {
  const when = (c: Omit<Candidate, 'score'>) => c.lastAt ?? 0;
  const scored = list.map((cand) => {
    const staler = list.filter((other) => when(other) < when(cand)).length;
    const freshness = list.length < 2 ? 1 : 1 - staler / (list.length - 1);
    const brake = BRAKE ** recentCount(recentFocuses, cand.focus);
    const depth = DEPTH ** effectiveLevel(cand.level, cand.starred);
    const score = cand.need * (1 + STALENESS * freshness) * depth * brake;
    return { ...cand, score };
  });
  return scored.sort(
    (a, b) =>
      b.score - a.score ||
      b.need - a.need ||
      ORDER[a.focus] - ORDER[b.focus] ||
      a.openingId.localeCompare(b.openingId) ||
      a.color.localeCompare(b.color),
  );
}

const ORDER: Record<Focus, number> = { test: 0, review: 1 };

/* ── candidates ─────────────────────────────────────────────────────────── */

/** A line with the openings it belongs to, computed once. */
interface Placed<T> {
  item: T;
  regions: Map<string, 'reached' | 'onWay' | 'outside'>;
}

function place<T>(tree: OpeningTree, nodes: OpeningNode[], items: T[], line: (item: T) => string[]): Placed<T>[] {
  return items.map((item) => ({ item, regions: regionsOf(tree, nodes, line(item)) }));
}

/** Items inside a node's region, or on the way into it. */
function within<T>(placed: Placed<T>[], node: OpeningNode): T[] {
  return placed.filter((p) => p.regions.get(node.id) !== 'outside').map((p) => p.item);
}

/** Items strictly inside a node's region: past the position that names it. */
function reachedIn<T>(placed: Placed<T>[], node: OpeningNode): T[] {
  return placed.filter((p) => p.regions.get(node.id) === 'reached').map((p) => p.item);
}

/** Every move in a repertoire, with the line that reaches it. */
function repMoves(rep: Repertoire): { sans: string[]; addedAt: number }[] {
  const out: { sans: string[]; addedAt: number }[] = [];
  const visit = (ids: string[], path: string[]) => {
    for (const id of ids) {
      const node = rep.nodes[id];
      if (!node) continue;
      const line = [...path, node.san];
      out.push({ sans: line, addedAt: node.addedAt });
      visit(node.children, line);
    }
  };
  visit(rep.rootChildren, []);
  return out;
}

/**
 * Every (focus, opening, colour) that could be started now, with its need.
 *
 * A candidate with nothing to work on is not offered at all: there is no
 * honest way to review an opening with no prep in it, and a side with no
 * prep at all is offered nothing — Autopilot drills what you have.
 */
export function candidates(input: RecommendInput): Omit<Candidate, 'score'>[] {
  const { tree, selection, score, starred } = input;
  const region = nodeById(tree, selection.opening);
  const nodes = [region, ...descendantsOf(region)];
  const out: Omit<Candidate, 'score'>[] = [];
  const now = input.now ?? Date.now();

  /**
   * When this opening last had a round. A round is credited to the deepest
   * opening it went through and everything above, so a family is fresh when
   * any of its variations is, and a variation is fresh only when a round
   * actually went through it.
   */
  const lastAt = (id: string) => nodeStats(score, id).byMode.run.lastAt;
  const everRun = score.global.byMode.run.rounds > 0;
  const push = (focus: Focus, node: OpeningNode, color: Color, need: number, work: number) => {
    if (need <= 0) return;
    out.push({
      focus,
      openingId: node.id,
      color,
      need,
      work,
      lastAt: lastAt(node.id),
      starred: starredWithin(tree, node.id, starred),
      level: node.depth - region.depth,
    });
  };

  for (const color of colorsOf(selection.color)) {
    const reps = input.reps.filter((rep) => rep.color === color);
    if (!reps.length) continue;
    const repairs = input.repairs.filter((item) => item.color === color);
    const items = place(tree, nodes, allItems(reps), (item: TrainingItem) => item.pathSans);
    const moves = place(tree, nodes, reps.flatMap(repMoves), (m) => m.sans);
    // Every line a Test could run, with how long it has been left.
    const seen = input.seen ?? NOTHING_SEEN;
    const lines = place(
      tree,
      nodes,
      reps.flatMap((rep) =>
        leafLines(rep).map((line) => ({ sans: line.sans, stale: lineStaleness(seen, rep, line.tipId) })),
      ),
      (line) => line.sans,
    );
    // Positions your games got wrong where you had a move: they want
    // repeating whatever the schedule says, so they count as due.
    const slipped = new Set(
      repairs.filter((item) => item.kind === 'offprep').map((item) => positionKey(item.fen)),
    );

    for (const node of nodes) {
      // Only openings the player actually has prep in, the selection itself
      // included: a hundred untouched variations would otherwise all ask for
      // a round at once, none of them for any reason the player would
      // recognise, and a selection with nothing in it is Growth's, not a
      // Review of the way in. "In" means past the position that names the
      // opening — a first move is on the way to everything and prep in nothing.
      const mine = reachedIn(moves, node);
      if (mine.length === 0) continue;

      const wanting = (item: TrainingItem) => {
        const card = input.cards[item.cardId];
        return !card || isDue(card, now) || slipped.has(item.key);
      };
      let due = 0;
      let unseen = 0;
      for (const item of within(items, node)) {
        const card = input.cards[item.cardId];
        if (!card) unseen += 1;
        else if (isDue(card, now) || slipped.has(item.key)) due += 1;
      }
      push(
        'review',
        node,
        color,
        reviewNeed(due, unseen, input.newPerSession),
        reachedIn(items, node).filter(wanting).length,
      );

      // A Test is only ever the selection, from move one: what it measures is
      // whether the prep holds up when nothing says what it is, and a Test
      // started inside an opening has said what it is.
      if (mine.length && node === region) {
        const since = lastAt(node.id) ?? 0;
        const untested = mine.filter((m) => m.addedAt > since).length;
        const stalest = Math.max(0, ...reachedIn(lines, node).map((line) => line.stale));
        push('test', node, color, testNeed(untested, everRun, stalest), untested || mine.length);
      }
    }
  }
  return out;
}

/**
 * The one thing to start, or null when there is nothing to drill: no prep
 * inside the selection for any colour it asks for. Autopilot builds nothing
 * — that is Growth's — so an empty selection is a pointer to Growth rather
 * than a round.
 *
 * A Review that wins is narrowed while a variation inside it holds most of
 * its work for the same focus and colour — see `narrowingBar` — so a Review
 * asked for by one variation's due cards is a Review on that variation. A
 * Test is never narrowed.
 */
export function recommend(input: RecommendInput): Recommendation | null {
  const tree = input.tree;
  const { selection } = input;
  // Openings a round would be steered into are off the table for a while
  // after one was.
  const closed = steeredRecently(input.recentSteered ?? []);
  const open = (id: string) => !closed || !isSteered({ opening: nodeById(tree, id), start: 'inside' }, selection);
  const ranked = rank(candidates(input).filter((c) => open(c.openingId)), input.recentFocuses);
  const pick = (focus: Focus, opening: OpeningNode, color: Color): Recommendation => ({
    focus,
    opening,
    color,
    start: startsInside(opening) ? 'inside' : 'first',
  });
  let best = ranked[0];
  if (!best) return null;
  while (best.focus !== 'test') {
    const node = nodeById(tree, best.openingId);
    const parent = best;
    const child = ranked
      .filter(
        (c) =>
          c.focus === parent.focus &&
          c.color === parent.color &&
          node.children.some((kid) => kid.id === c.openingId) &&
          open(c.openingId) &&
          c.work > parent.work * narrowingBar(effectiveLevel(c.level, c.starred)),
      )
      .sort((a, b) => b.work - a.work)[0];
    if (!child) break;
    best = child;
  }
  return pick(best.focus, nodeById(tree, best.openingId), best.color);
}

export const MODE_NAMES: Record<ActivityMode, string> = {
  run: 'Run',
  drill: 'Drill',
  growth: 'Growth',
  repair: 'Repair',
};
