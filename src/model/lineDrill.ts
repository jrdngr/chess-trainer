import { fenTurn, type Color } from '../chess/core';
import { lineOdds, lineWeakness, type Weakness } from './openingRun';
import { lineStatus, type OpeningNode, type OpeningTree } from './openingTree';
import type { ReferenceIndex } from './reference';
import { childrenOf, leafLines, nodeAtLine, pathTo } from './repertoire';
import type { RepMove, Repertoire } from './types';

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
 * Draw up to `count` different lines.
 *
 * Each is drawn in proportion to how often you would meet it (the opponent's
 * choices weighted by the book, your own split evenly), and for `weak` that
 * weight is multiplied by how badly the line's positions want practice. With
 * `only` given and any of its lines in reach, the draw is held to those: what
 * Autopilot asks for when lines have just been grown.
 */
export function drawLines(opts: {
  rep: Repertoire;
  tree: OpeningTree;
  region: OpeningNode;
  index: ReferenceIndex | null;
  lean: LineLean;
  weakness?: Weakness | null;
  only?: Set<string> | null;
  count: number;
  rand: () => number;
}): DrillLine[] {
  const { rep } = opts;
  let lines = drillableLines(rep, opts.tree, opts.region);
  if (opts.only?.size) {
    const held = lines.filter((line) => opts.only!.has(line.tipId));
    if (held.length) lines = held;
  }
  if (!lines.length) return [];
  const odds = lineOdds(rep, rep.color, opts.index, new Set(lines.map((line) => line.tipId)));
  const weight = (line: DrillLine): number => {
    const meet = odds.size ? (odds.get(line.tipId) ?? 0) : 1;
    const want =
      opts.lean === 'weak' && opts.weakness ? lineWeakness(rep.id, askedKeys(rep, line.tipId), opts.weakness) : 1;
    return meet * want;
  };
  const pool = [...lines];
  const out: DrillLine[] = [];
  while (out.length < opts.count && pool.length) {
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
    out.push(pool[at]);
    pool.splice(at, 1);
  }
  return out;
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
