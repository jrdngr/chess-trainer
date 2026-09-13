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
 * A position is in scope while the line to it can still be part of the
 * opening: inside it, or on the way in — the choice that gets you there is as
 * much part of the opening as the moves after it.
 */
export function itemsInRegion(
  tree: OpeningTree,
  node: OpeningNode,
  items: TrainingItem[],
): TrainingItem[] {
  if (node.depth === 0) return items;
  return items.filter((item) => lineStatus(tree, node, item.pathSans) !== 'outside');
}

/** Is a line inside a region, or still able to get there? */
export function lineInRegion(tree: OpeningTree, node: OpeningNode, sans: string[]): boolean {
  return node.depth === 0 || lineStatus(tree, node, sans) !== 'outside';
}
