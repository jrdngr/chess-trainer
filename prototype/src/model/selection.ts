import type { Color } from '../chess/core';
import type { ColorChoice } from './openingRun';
import { lineStatus, nodeById, type OpeningNode, type OpeningTree } from './openingTree';
import type { TrainingItem } from './session';
import type { Repertoire } from './types';

/**
 * The global selection: which side you sit on, and which region of the
 * opening tree you are working in. Every mode reads it and none of them asks
 * again, which is what lets the setup screens be short.
 */
export interface Selection {
  color: ColorChoice;
  /** An opening tree node id; '' is the root, every opening there is. */
  opening: string;
}

export const DEFAULT_SELECTION: Selection = { color: 'random', opening: '' };

/** The sides a selection covers: both, for random. */
export function colorsOf(choice: ColorChoice): Color[] {
  return choice === 'random' ? ['w', 'b'] : [choice];
}

export function colorLabel(choice: ColorChoice): string {
  return choice === 'w' ? 'White' : choice === 'b' ? 'Black' : 'Random';
}

/** The repertoires the selection covers. */
export function repertoiresIn(reps: Repertoire[], choice: ColorChoice): Repertoire[] {
  const wanted = colorsOf(choice);
  return reps.filter((rep) => wanted.includes(rep.color));
}

/** The region a selection names. */
export function regionOf(tree: OpeningTree, selection: Selection): OpeningNode {
  return nodeById(tree, selection.opening);
}

/**
 * The training items inside a region.
 *
 * A position is in scope while your answer keeps the line part of the
 * opening: inside it, or on the way in — the choice that gets you there is as
 * much part of the opening as the moves after it. The answer decides, not the
 * position: the book can reach the King's Indian from 1.e4 (1...d6 2.d4 Nf6
 * 3.Nc3 g6 4.Nf3 Bg7 5.c4), but a 1.e4 card answered 1...c5 never gets there.
 */
export function itemsInRegion(
  tree: OpeningTree,
  node: OpeningNode,
  items: TrainingItem[],
): TrainingItem[] {
  if (node.depth === 0) return items;
  return items.filter((item) =>
    item.expected.some((answer) => lineStatus(tree, node, [...item.pathSans, answer.san]) !== 'outside'),
  );
}

/** Is a line inside a region, or still able to get there? */
export function lineInRegion(tree: OpeningTree, node: OpeningNode, sans: string[]): boolean {
  return node.depth === 0 || lineStatus(tree, node, sans) !== 'outside';
}
