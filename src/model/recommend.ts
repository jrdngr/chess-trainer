import type { Color } from '../chess/core';
import { findHoles, rowUrgency, type Hole } from './growth';
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
 * What to do next: a mode, an opening inside the selection, and a colour.
 *
 * Every candidate is one of those three things together, because the
 * factors that decide it are per-opening factors. Need is how loudly the
 * work is asking — cards due, holes in the prep, positions your games
 * disagree with, prep no run has tested. Holes only ask loudly once the prep
 * around them is held: an opening still being drilled is not ready to get
 * wider. Staleness is how long that opening has gone without that mode,
 * measured against the other candidates rather than the clock. A star on the
 * opening or anything above it lifts it. Fun
 * tilts every decision toward Run and away from Growth without overriding
 * the one that matters most. And a brake cuts a mode's weight for every one
 * of the last few games it was, so a standing backlog cannot lock the
 * rotation into one mode and the most fun mode cannot run for ever.
 *
 * Need is measured on everything inside a node, so a family always asks at
 * least as loudly as any of its variations. The winner is then narrowed
 * downward while a variation holds most of its parent's need, so a game is
 * steered to the variation that actually wants it and left at the family
 * when the need is spread thin.
 */
export const FUN: Record<ScoreMode, number> = { run: 1, drill: 0.7, repair: 0.5, growth: 0.4 };

/** How much a star is worth. */
export const STAR = 1.6;

/** How much the stalest candidate can outweigh the freshest. */
export const STALENESS = 2;

/** Each recent game of the same mode multiplies its weight by this. */
export const BRAKE = 0.6;

/** How many recent games the brake looks back over. */
export const BRAKE_WINDOW = 5;

/** A variation is worth steering toward once it holds more than this share of its parent's work. */
export const NARROWING = 0.5;

/** A review interval this long, in days, is a position fully held. */
export const HELD_DAYS = 7;

/** How loudly Growth can still ask when nothing in the opening is held yet. */
export const GROWTH_FLOOR = 0.1;

export interface Candidate {
  mode: ScoreMode;
  openingId: string;
  color: Color;
  /** 0..1, how loudly this asks. */
  need: number;
  /** How many pieces of work sit strictly inside this opening, for narrowing. */
  work: number;
  lastAt: number | null;
  starred: boolean;
  /** need × staleness × star × fun × brake. Only comparable within one ranking. */
  score: number;
}

export interface Recommendation {
  mode: ScoreMode;
  opening: OpeningNode;
  color: Color;
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
  /** Games most recently played, oldest first, for the brake. */
  recentModes: ScoreMode[];
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
export function drillNeed(due: number, unseen: number, newPerSession: number): number {
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
 * all held asks at full strength. It never goes silent, so a thin opening is
 * still grown now and then rather than never.
 */
export function growthNeed(holes: Hole[], ready = 1): number {
  if (!holes.length) return 0;
  const depth = Math.min(...holes.map((hole) => hole.path.length));
  const topShare = Math.max(...holes.map((hole) => hole.share));
  const gate = GROWTH_FLOOR + (1 - GROWTH_FLOOR) * clamp(ready) ** 2;
  return clamp(rowUrgency(depth, topShare, holes.length) * gate);
}

/** What your own games disagree with your prep about. */
export function repairNeed(items: RepairItem[]): number {
  if (items.length === 0) return 0;
  const worst = items.reduce((max, item) => Math.max(max, item.weight), 0);
  return clamp(0.55 * saturate(worst, 5) + 0.45 * saturate(items.length, 8));
}

/**
 * Run has no queue behind it: what it measures is whether the prep holds up
 * when nothing on screen says what it is. That is always worth asking, and
 * more so the more prep has been added since it was last asked here.
 */
export function runNeed(untested: number, everRun: boolean): number {
  const base = 0.4 + 0.4 * saturate(untested, 10);
  return clamp(everRun ? base : Math.max(base, 0.55));
}

/* ── ranking ────────────────────────────────────────────────────────────── */

/**
 * How many of the last few games were this mode.
 *
 * Counted over a window rather than only consecutively: two modes taking
 * turns would never trip a consecutive brake, and would leave a third mode
 * with real work waiting for ever.
 */
export function recentCount(recentModes: ScoreMode[], mode: ScoreMode): number {
  return recentModes.slice(-BRAKE_WINDOW).filter((m) => m === mode).length;
}

/**
 * Score and sort, best first.
 *
 * Staleness is read off the other candidates rather than off the clock: the
 * candidate nothing has been left longer than is the stalest, whether that is
 * an hour or a month. Candidates never played are all equally stale.
 */
export function rank(list: Omit<Candidate, 'score'>[], recentModes: ScoreMode[]): Candidate[] {
  const when = (c: Omit<Candidate, 'score'>) => c.lastAt ?? 0;
  const scored = list.map((cand) => {
    const staler = list.filter((other) => when(other) < when(cand)).length;
    const freshness = list.length < 2 ? 1 : 1 - staler / (list.length - 1);
    const brake = BRAKE ** recentCount(recentModes, cand.mode);
    const score =
      cand.need * (1 + STALENESS * freshness) * (cand.starred ? STAR : 1) * FUN[cand.mode] * brake;
    return { ...cand, score };
  });
  return scored.sort(
    (a, b) =>
      b.score - a.score ||
      b.need - a.need ||
      ORDER[a.mode] - ORDER[b.mode] ||
      a.openingId.localeCompare(b.openingId) ||
      a.color.localeCompare(b.color),
  );
}

const ORDER: Record<ScoreMode, number> = { run: 0, drill: 1, growth: 2, repair: 3 };

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
 * Every (mode, opening, colour) that could be started now, with its need.
 *
 * A candidate with nothing to work on is not offered at all: there is no
 * honest way to recommend Repair to someone who has imported no games. Run is
 * the exception and is always here for the selection itself, because the book
 * can hand out a line whether or not anything has been prepared.
 */
export function candidates(input: RecommendInput): Omit<Candidate, 'score'>[] {
  const { tree, selection, score, starred } = input;
  const region = nodeById(tree, selection.opening);
  const nodes = [region, ...descendantsOf(region)];
  const out: Omit<Candidate, 'score'>[] = [];
  const now = input.now ?? Date.now();

  const lastAt = (mode: ScoreMode, id: string) => nodeStats(score, id).byMode[mode].lastAt;
  const everRun = score.global.byMode.run.games > 0;
  const push = (mode: ScoreMode, node: OpeningNode, color: Color, need: number, work: number) => {
    if (need <= 0) return;
    out.push({
      mode,
      openingId: node.id,
      color,
      need,
      work,
      lastAt: lastAt(mode, node.id),
      starred: starredWithin(tree, node.id, starred),
    });
  };

  for (const color of colorsOf(selection.color)) {
    const reps = input.reps.filter((rep) => rep.color === color);
    const items = place(tree, nodes, allItems(reps), (item: TrainingItem) => item.pathSans);
    const moves = place(tree, nodes, reps.flatMap(repMoves), (m) => m.sans);
    const holes = place(
      tree,
      nodes,
      reps.flatMap((rep) => findHoles(rep, tree.index, { ...input.growth, region: { tree, node: region } })),
      (hole: Hole) => [...hole.path, hole.san],
    );
    const repairs = place(
      tree,
      nodes,
      input.repairs.filter((item) => item.color === color),
      (item: RepairItem) => item.path,
    );

    for (const node of nodes) {
      // Only openings the player actually has prep in, past the selection
      // itself: a hundred untouched variations would otherwise all ask for a
      // Run at once, none of them for any reason the player would recognise.
      // "In" means past the position that names the opening — a first move
      // is on the way to everything and prep in nothing.
      const mine = reachedIn(moves, node);
      if (node !== region && mine.length === 0) continue;

      const wanting = (item: TrainingItem) => {
        const card = input.cards[item.cardId];
        return !card || isDue(card, now);
      };
      let due = 0;
      let unseen = 0;
      const strengths: number[] = [];
      for (const item of within(items, node)) {
        const card = input.cards[item.cardId];
        if (!card) unseen += 1;
        else if (isDue(card, now)) due += 1;
        strengths.push(cardStrength(card, now));
      }
      push(
        'drill',
        node,
        color,
        drillNeed(due, unseen, input.newPerSession),
        reachedIn(items, node).filter(wanting).length,
      );
      push(
        'growth',
        node,
        color,
        growthNeed(within(holes, node), readiness(strengths)),
        reachedIn(holes, node).length,
      );
      push('repair', node, color, repairNeed(within(repairs, node)), reachedIn(repairs, node).length);

      const since = lastAt('run', node.id) ?? 0;
      const untested = mine.filter((m) => m.addedAt > since).length;
      push('run', node, color, runNeed(untested, everRun), untested || mine.length);
    }
  }
  return out;
}

/**
 * The one thing to start. Never null: Run in the selection always qualifies.
 *
 * The winner is narrowed while a variation inside it holds most of its need
 * for the same mode and colour, so a Drill asked for by one variation's due
 * cards is a Drill on that variation.
 */
export function recommend(input: RecommendInput): Recommendation {
  const ranked = rank(candidates(input), input.recentModes);
  const tree = input.tree;
  let best = ranked[0];
  if (!best) {
    return {
      mode: 'run',
      opening: nodeById(tree, input.selection.opening),
      color: colorsOf(input.selection.color)[0],
    };
  }
  for (;;) {
    const node = nodeById(tree, best.openingId);
    const parent = best;
    const child = ranked
      .filter(
        (c) =>
          c.mode === parent.mode &&
          c.color === parent.color &&
          node.children.some((kid) => kid.id === c.openingId) &&
          c.work > parent.work * NARROWING,
      )
      .sort((a, b) => b.work - a.work)[0];
    if (!child) break;
    best = child;
  }
  return { mode: best.mode, opening: nodeById(tree, best.openingId), color: best.color };
}

export const MODE_NAMES: Record<ScoreMode, string> = {
  run: 'Run',
  drill: 'Drill',
  growth: 'Growth',
  repair: 'Repair',
};
