import { fenTurn, type Color } from '../chess/core';
import type { DrillDraw } from './modes';
import { lineOdds } from './openingRun';
import { lineStatus, type OpeningNode, type OpeningTree } from './openingTree';
import type { ReferenceIndex } from './reference';
import { childrenOf, leafLines, nodeAtLine, pathTo } from './repertoire';
import { isDue, lineCardId } from './srs';
import type { LineCard, RepMove, Repertoire } from './types';

/**
 * Line drills: Drill's way of asking a whole line.
 *
 * A single-position drill jumps straight to the position the schedule wants.
 * A line drill starts from move one and plays the opponent's side of one of
 * your lines, so every answer is asked in the context it comes up in. Which
 * line is drawn the way the opponent in Survival draws one: by how often you
 * would actually meet it, or tilted toward the positions you answer worst.
 *
 * A miss does not end the line. It shows what your prep says, and the line
 * carries on from your prep's move, so the back half of a line you slip on
 * early still gets its practice. A line got through without a miss is a clean
 * finish, which is what Growth's readiness reads.
 *
 * Each line has a schedule of its own — a `LineCard` — moved only by the one
 * grade given at the end of it. Position cards are Drill positions' alone.
 */

export interface DrillLine {
  repertoireId: string;
  color: Color;
  /** The leaf the line ends on. */
  tipId: string;
  sans: string[];
}

/** What a drawn line leans toward — see `drawLines`. */
export type LineLean = 'popular' | 'weak';

/** Your moves along a line: the positions it asks you, by position key. */
export function askedKeys(rep: Repertoire, tipId: string): string[] {
  return pathTo(rep, tipId)
    .filter((move) => fenTurn(move.fenBefore) === rep.color)
    .map((move) => move.key);
}

/**
 * Lines worth drilling inside a region: every leaf line of yours that reaches
 * it and asks you at least one move.
 */
export function drillableLines(rep: Repertoire, tree: OpeningTree, region: OpeningNode): DrillLine[] {
  return leafLines(rep)
    .filter((line) => lineStatus(tree, region, line.sans) === 'reached')
    .filter((line) => askedKeys(rep, line.tipId).length > 0)
    .map((line) => ({ repertoireId: rep.id, color: rep.color, tipId: line.tipId, sans: line.sans }));
}

/**
 * How much a line wants practice, from its card: a lapse, a low ease, a
 * Guessed still being relearned or a line overdue all count. A line never
 * drilled is worth seeing, but not the emergency a lapse is. Only ever
 * compared against other lines, so the scale does not matter.
 */
export function lineCardWeakness(card: LineCard | undefined, now = Date.now()): number {
  if (!card) return 1.5;
  let score = 1 + card.lapses * 1.2 + Math.max(0, 2.5 - card.ease) * 2;
  if (card.stage === 'learning') score += 1;
  if (card.due <= now) score += 1;
  const answered = card.correct + card.incorrect;
  if (answered > 0) score += (card.incorrect / answered) * 2;
  return score;
}

/** Lines whose card is due: drilled before, and the schedule wants them back. */
export function dueLines(lines: DrillLine[], cards: Record<string, LineCard>, now = Date.now()): DrillLine[] {
  return lines.filter((line) => {
    const card = cards[lineCardId(line.repertoireId, line.tipId)];
    return !!card && isDue(card, now);
  });
}

/** The most of your own moves a round of lines asks, when it is sized — see `drawLines`. */
export const LINE_BUDGET = 15;

/** The most lines in a sized round. */
export const MAX_LINES = 3;

/** How many of your own moves a line asks. */
export function yourMoves(line: DrillLine): number {
  return line.sans.filter((_, ply) => yoursAt(line.color, ply)).length;
}

/** How many moves two lines share from the start. */
export function sharedMoves(a: string[], b: string[]): number {
  let n = 0;
  while (n < a.length && n < b.length && a[n] === b[n]) n += 1;
  return n;
}

/**
 * Draw up to `count` different lines.
 *
 * What is drawn first follows `draw`, the way Drill positions reads it:
 * Scheduled takes the lines due, then the lines never drilled, then the rest
 * so a sitting never runs dry; New only starts with the lines never drilled;
 * Everything draws from all of them at once. Inside each tier a line is drawn
 * in proportion to how often you would meet it (the opponent's choices
 * weighted by the book, your own split evenly), and for `weak` that weight is
 * multiplied by how badly the line's card wants practice. With `only` given
 * and any of its lines in reach, the draw is held to those: what Autopilot
 * asks for when lines are new or due. Lines in `avoid` are left out while
 * anything else is in reach: the group just played, so the next is elsewhere.
 *
 * With `budget`, lines are added only while your moves across them stay
 * within it, and the first line always goes in: short lines come several to
 * a round, a long one alone.
 *
 * With `similar`, the first line is drawn as above and the rest are the
 * lines that share the most moves with it — its siblings in your tree, which
 * split late — so a round stays on one idea. Ties go by the draw.
 */
export function drawLines(opts: {
  rep: Repertoire;
  tree: OpeningTree;
  region: OpeningNode;
  index: ReferenceIndex | null;
  lean: LineLean;
  cards?: Record<string, LineCard>;
  draw?: DrillDraw;
  only?: Set<string> | null;
  avoid?: Set<string> | null;
  count: number;
  budget?: number;
  similar?: boolean;
  rand: () => number;
  now?: number;
}): DrillLine[] {
  const { rep } = opts;
  const cards = opts.cards ?? {};
  const now = opts.now ?? Date.now();
  let lines = drillableLines(rep, opts.tree, opts.region);
  if (opts.only?.size) {
    const held = lines.filter((line) => opts.only!.has(line.tipId));
    if (held.length) lines = held;
  }
  if (opts.avoid?.size) {
    const rest = lines.filter((line) => !opts.avoid!.has(line.tipId));
    if (rest.length) lines = rest;
  }
  if (!lines.length) return [];
  const odds = lineOdds(rep, rep.color, opts.index, new Set(lines.map((line) => line.tipId)));
  const cardOf = (line: DrillLine) => cards[lineCardId(line.repertoireId, line.tipId)];
  const weight = (line: DrillLine): number => {
    const meet = odds.size ? (odds.get(line.tipId) ?? 0) : 1;
    const want = opts.lean === 'weak' ? lineCardWeakness(cardOf(line), now) : 1;
    return meet * want;
  };

  const due = new Set(dueLines(lines, cards, now).map((line) => line.tipId));
  const tier = (line: DrillLine): number => {
    const draw = opts.draw ?? 'cram';
    if (draw === 'cram') return 0;
    const fresh = !cardOf(line);
    if (draw === 'new') return fresh ? 0 : 1;
    return due.has(line.tipId) ? 0 : fresh ? 1 : 2;
  };

  // Every line, in the order the draw would take them.
  const drawn: DrillLine[] = [];
  for (const level of [0, 1, 2]) {
    const pool = lines.filter((line) => tier(line) === level);
    while (pool.length) {
      const total = pool.reduce((sum, line) => sum + weight(line), 0);
      let at = 0;
      if (total > 0) {
        let roll = opts.rand() * total;
        at = pool.findIndex((line) => {
          roll -= weight(line);
          return roll <= 0;
        });
        if (at < 0) at = pool.length - 1;
      } else {
        at = Math.floor(opts.rand() * pool.length);
      }
      drawn.push(pool[at]);
      pool.splice(at, 1);
    }
  }

  const [first, ...others] = drawn;
  const order = opts.similar
    ? others
        .map((line, i) => ({ line, i, shared: sharedMoves(line.sans, first.sans) }))
        .sort((a, b) => b.shared - a.shared || a.i - b.i)
        .map(({ line }) => line)
    : others;
  const out: DrillLine[] = [first];
  let moves = yourMoves(first);
  for (const line of order) {
    if (out.length >= opts.count) break;
    if (opts.budget !== undefined && moves + yourMoves(line) > opts.budget) continue;
    out.push(line);
    moves += yourMoves(line);
  }
  return opts.count > 0 ? out : [];
}

/**
 * A line to carry on along after you played another of your prepared moves:
 * the played moves, then your preferred continuation to a leaf. The opponent
 * answers the way your prep expects them to most.
 */
export function continueLine(rep: Repertoire, prefix: string[]): DrillLine | null {
  const at = nodeAtLine(rep, prefix);
  if (!at) return null;
  const sans = [...prefix];
  let node: RepMove = at;
  for (;;) {
    const kids = childrenOf(rep, node.id);
    if (!kids.length) break;
    node = kids.find((kid) => kid.preferred) ?? kids[0];
    sans.push(node.san);
  }
  return { repertoireId: rep.id, color: rep.color, tipId: node.id, sans };
}

/** Whether it is your move at this ply of a line. */
export function yoursAt(color: Color, ply: number): boolean {
  return (ply % 2 === 0) === (color === 'w');
}
