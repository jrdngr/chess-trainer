import type { Color } from '../chess/core';
import { positionKey } from '../chess/core';
import {
  evidenceFor,
  findCoverage,
  findHoles,
  rowUrgency,
  thinness,
  type Coverage,
  type Hole,
} from './growth';
import {
  descendantsOf,
  nodeById,
  regionsOf,
  starredWithin,
  type OpeningNode,
  type OpeningTree,
} from './openingTree';
import type { RepairItem } from './repair';
import { colorsOf, type Selection } from './selection';
import { allItems, type TrainingItem } from './session';
import { nodeStats, type ScoreMode, type ScoreState } from './scoring';
import { isDue } from './srs';
import type { Card, Repertoire } from './types';

/**
 * What the next round should be: an opening inside the selection, a colour,
 * and a focus — the settings the Run is played on.
 *
 * Every round under Autopilot is a Run. What changes between rounds is what
 * the opponent steers you toward and whether the run may add to the
 * repertoire, and that is the focus:
 *
 *   test    — lines drawn by how often you would meet them, nothing added.
 *             Whether the prep holds up when nothing says what it is.
 *   review  — lines drawn toward the positions you are worst at or due on,
 *             nothing added. Repetition, where it is needed.
 *   grow    — the opponent walks you to a reply you have no answer to, and
 *             you choose one from the book, a few moves a run.
 *
 * Every candidate is a focus, an opening and a colour together, because the
 * factors that decide it are per-opening factors. Need is how loudly the
 * work is asking — cards due, holes in the prep, prep no run has tested.
 * Holes only ask loudly once the prep around them is held: an opening still
 * being drilled is not ready to get wider — unless it is barely an opening
 * yet, and there is nothing there to drill first. Staleness is how long that
 * opening has gone without a run, measured against the other candidates
 * rather than the clock. A star on the opening or anything above it lifts
 * it. Fun tilts away from Grow, whose pickers interrupt the run, without
 * overriding the one that matters most. And a brake cuts a focus's weight
 * for every one of the last few rounds it was, so a standing backlog cannot
 * lock the session into one focus.
 *
 * Need is measured on everything inside a node, so a family always asks at
 * least as loudly as any of its variations. The winner is then narrowed
 * downward while a variation holds most of its parent's need, so a round is
 * steered to the variation that actually wants it and left at the family
 * when the need is spread thin.
 */
export type Focus = 'test' | 'review' | 'grow';

export const FOCUSES: Focus[] = ['test', 'review', 'grow'];

export const FUN: Record<Focus, number> = { test: 1, review: 1, grow: 0.7 };

/** How much a star is worth. */
export const STAR = 1.6;

/** How much the stalest candidate can outweigh the freshest. */
export const STALENESS = 2;

/** Each recent round of the same focus multiplies its weight by this. */
export const BRAKE = 0.6;

/** How many recent rounds the brake looks back over. */
export const BRAKE_WINDOW = 5;

/** A variation is worth steering toward once it holds more than this share of its parent's work. */
export const NARROWING = 0.5;

/** A review interval this long, in days, is a position fully held. */
export const HELD_DAYS = 7;

/** How loudly Grow can still ask when nothing in the opening is held yet. */
export const GROWTH_FLOOR = 0.1;

/**
 * The most moves one Grow round may add.
 *
 * An allowance rather than a quota: how many a round actually spends is
 * decided by how much line is left to build, not here — see `movesToFit`.
 */
export const MAX_NEW_MOVES = 8;

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
  /** Moves a Grow round may add here; 0 for the other focuses. */
  newMoves: number;
  /** need × staleness × star × fun × brake. Only comparable within one ranking. */
  score: number;
}

export interface Recommendation {
  focus: Focus;
  opening: OpeningNode;
  color: Color;
  /**
   * Moves the round may add to the repertoire — an allowance, not a quota.
   * What a round actually spends is decided by the line it walks to: see
   * `movesToFit`.
   */
  newMoves: number;
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
  growth: { minShare: number; maxPly: number };
  /** The focuses of the session's rounds so far, oldest first, for the brake. */
  recentFocuses: Focus[];
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
 * How firmly one position is held, 0..1.
 *
 * Nothing until the card has graduated and is not waiting to be reviewed;
 * from there, how long it has been trusted to stay known. A position seen
 * once yesterday is not held the way one is that has come back right for
 * a fortnight.
 */
export function cardStrength(card: Card | undefined, now: number): number {
  if (!card || card.stage !== 'review' || isDue(card, now)) return 0;
  return clamp(card.interval / HELD_DAYS);
}

/**
 * How ready an opening is to grow: the mean strength of its positions.
 *
 * An opening with nothing in it yet is ready — there is nothing to drill
 * first — which is what lets a new repertoire get its first lines at all.
 */
export function readiness(strengths: number[]): number {
  if (!strengths.length) return 1;
  return clamp(strengths.reduce((sum, s) => sum + s, 0) / strengths.length);
}

/**
 * How much a set of holes costs: the shallowest and most played one, and how
 * many — then how ready the prep around them is to take on more.
 *
 * Adding lines to an opening whose existing moves are still being learned
 * makes more to drill, not a stronger repertoire, so the readiness gate is
 * steep: half held is a quarter of the voice, and only prep that is nearly
 * all held asks at full strength.
 *
 * Thinness lifts the floor that gate cannot go below, because the rule was
 * never about an opening this bare. A repertoire with nothing in it is not
 * prep being learned — it is prep that does not exist yet, and the openings it
 * cannot meet will still be played against it whatever its cards say. So an
 * opening with nothing in it asks at full voice however little of it is held.
 *
 * That lift is as steep as the gate it undoes, and for the same reason. An
 * opening that answers half of what it meets is half prepared, not bare, and
 * lifting the floor for it would buy breadth with the review the other half
 * has earned. Only prep that barely exists gets to ignore the gate.
 */
export function growNeed(holes: Hole[], ready = 1, thin = 0): number {
  if (!holes.length) return 0;
  const depth = Math.min(...holes.map((hole) => hole.path.length));
  const topShare = Math.max(...holes.map((hole) => hole.share));
  const floor = GROWTH_FLOOR + (1 - GROWTH_FLOOR) * clamp(thin) ** 2;
  const gate = floor + (1 - floor) * clamp(ready) ** 2;
  return clamp(rowUrgency(depth, topShare, holes.length) * gate);
}

/**
 * A Test has no queue behind it: what it measures is whether the prep holds
 * up when nothing on screen says what it is. That is always worth asking,
 * and more so the more prep has been added since it was last asked here.
 */
export function testNeed(untested: number, everRun: boolean): number {
  const base = 0.4 + 0.4 * saturate(untested, 10);
  return clamp(everRun ? base : Math.max(base, 0.55));
}

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
    const score =
      cand.need * (1 + STALENESS * freshness) * (cand.starred ? STAR : 1) * FUN[cand.focus] * brake;
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

const ORDER: Record<Focus, number> = { test: 0, review: 1, grow: 2 };

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

/** Holes with the evidence of your games folded into their share. */
export function weighHoles(holes: Hole[], repairs: RepairItem[]): Hole[] {
  const weight = evidenceFor(repairs);
  return holes.map((hole) => ({ ...hole, share: hole.share * weight(hole) }));
}

/**
 * Every (focus, opening, colour) that could be started now, with its need.
 *
 * A candidate with nothing to work on is not offered at all: there is no
 * honest way to review an opening with no prep in it. A side with no prep at
 * all is offered one thing, a Grow round in the selection, because the book
 * can hand out a first line whether or not anything has been prepared.
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
  const push = (
    focus: Focus,
    node: OpeningNode,
    color: Color,
    need: number,
    work: number,
    newMoves = 0,
  ) => {
    if (need <= 0) return;
    out.push({
      focus,
      openingId: node.id,
      color,
      need,
      work,
      lastAt: lastAt(node.id),
      starred: starredWithin(tree, node.id, starred),
      newMoves,
    });
  };

  for (const color of colorsOf(selection.color)) {
    const reps = input.reps.filter((rep) => rep.color === color);
    if (!reps.length) {
      push('grow', region, color, 0.5, 1, MAX_NEW_MOVES);
      continue;
    }
    const repairs = input.repairs.filter((item) => item.color === color);
    const items = place(tree, nodes, allItems(reps), (item: TrainingItem) => item.pathSans);
    const moves = place(tree, nodes, reps.flatMap(repMoves), (m) => m.sans);
    const holes = place(
      tree,
      nodes,
      weighHoles(
        reps.flatMap((rep) => findHoles(rep, tree.index, { ...input.growth, region: { tree, node: region } })),
        repairs,
      ),
      (hole: Hole) => [...hole.path, hole.san],
    );
    // What the side already answers at each of the opponent's choices, placed
    // like the holes are, so an opening's breadth is read off the positions
    // inside it rather than by walking the repertoire again per node.
    const coverage = place(
      tree,
      nodes,
      reps.flatMap((rep) =>
        findCoverage(rep, tree.index, { ...input.growth, region: { tree, node: region } }),
      ),
      (at: Coverage) => at.path,
    );
    // Positions your games got wrong where you had a move: they want
    // repeating whatever the schedule says, so they count as due.
    const slipped = new Set(
      repairs.filter((item) => item.kind === 'offprep').map((item) => positionKey(item.fen)),
    );

    for (const node of nodes) {
      // Only openings the player actually has prep in, past the selection
      // itself: a hundred untouched variations would otherwise all ask for a
      // round at once, none of them for any reason the player would recognise.
      // "In" means past the position that names the opening — a first move
      // is on the way to everything and prep in nothing.
      const mine = reachedIn(moves, node);
      if (node !== region && mine.length === 0) continue;

      const wanting = (item: TrainingItem) => {
        const card = input.cards[item.cardId];
        return !card || isDue(card, now) || slipped.has(item.key);
      };
      let due = 0;
      let unseen = 0;
      const strengths: number[] = [];
      for (const item of within(items, node)) {
        const card = input.cards[item.cardId];
        if (!card) unseen += 1;
        else if (isDue(card, now) || slipped.has(item.key)) due += 1;
        strengths.push(cardStrength(card, now));
      }
      push(
        'review',
        node,
        color,
        reviewNeed(due, unseen, input.newPerSession),
        reachedIn(items, node).filter(wanting).length,
      );
      const ready = readiness(strengths);
      const thin = thinness(within(coverage, node));
      push(
        'grow',
        node,
        color,
        growNeed(within(holes, node), ready, thin),
        reachedIn(holes, node).length,
        MAX_NEW_MOVES,
      );

      if (mine.length) {
        const since = lastAt(node.id) ?? 0;
        const untested = mine.filter((m) => m.addedAt > since).length;
        push('test', node, color, testNeed(untested, everRun), untested || mine.length);
      }
    }
  }
  return out;
}

/**
 * The one thing to start. Never null: with nothing prepared at all, a Grow
 * round in the selection hands out a first line.
 *
 * The winner is narrowed while a variation inside it holds most of its need
 * for the same focus and colour, so a Review asked for by one variation's due
 * cards is a Review on that variation.
 */
export function recommend(input: RecommendInput): Recommendation {
  const ranked = rank(candidates(input), input.recentFocuses);
  const tree = input.tree;
  let best = ranked[0];
  if (!best) {
    return {
      focus: 'grow',
      opening: nodeById(tree, input.selection.opening),
      color: colorsOf(input.selection.color)[0],
      newMoves: MAX_NEW_MOVES,
    };
  }
  for (;;) {
    const node = nodeById(tree, best.openingId);
    const parent = best;
    const child = ranked
      .filter(
        (c) =>
          c.focus === parent.focus &&
          c.color === parent.color &&
          node.children.some((kid) => kid.id === c.openingId) &&
          c.work > parent.work * NARROWING,
      )
      .sort((a, b) => b.work - a.work)[0];
    if (!child) break;
    best = child;
  }
  return {
    focus: best.focus,
    opening: nodeById(tree, best.openingId),
    color: best.color,
    newMoves: best.newMoves,
  };
}

export const MODE_NAMES: Record<ScoreMode, string> = {
  run: 'Run',
  drill: 'Drill',
  growth: 'Growth',
  repair: 'Repair',
};
