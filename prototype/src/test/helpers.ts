/**
 * Small helpers the tests lean on that the app itself never calls. They read
 * live model code, so a test written with them still tests the app.
 */
import { applySan, sansToMoveText, START_FEN } from '../chess/core';
import type { PgnGame, PgnNode } from '../chess/pgn';
import { NAMED_LATE, playerOf, type OpeningPick } from '../model/onboarding';
import { lineStatus, type OpeningNode, type OpeningTree } from '../model/openingTree';
import type { ReferenceIndex } from '../model/reference';
import { childrenOf, pathTo } from '../model/repertoire';
import { ratingAfter } from '../model/scoring';
import { setOpenings, STARTER_SETS, type SeedOpening, type StarterSet } from '../model/starterSets';
import { EMPTY_SURVIVAL_SCORE, type SurvivalRecord } from '../model/survival';
import { findAt, sortFinds, tidyPositions, type TidyFind, type TidyOptions } from '../model/tidy';
import type { RepMove, Repertoire } from '../model/types';

/** Whether the whole line is in the repertoire, move by move from the root. */
export function hasLine(rep: Repertoire, sans: string[]): boolean {
  if (!sans.length) return false;
  let nodeId: string | null = null;
  for (const san of sans) {
    const kid: RepMove | undefined = childrenOf(rep, nodeId).find((child) => child.san === san);
    if (!kid) return false;
    nodeId = kid.id;
  }
  return true;
}

/** The moves to a node, written out the way a score sheet does. */
export function lineText(rep: Repertoire, nodeId: string | null): string {
  return sansToMoveText(pathTo(rep, nodeId).map((m) => m.san), rep.rootFen);
}

export function countNodes(rep: Repertoire): number {
  return Object.keys(rep.nodes).length;
}

/** Can a line still be part of this region? */
export function insideRegion(tree: OpeningTree, node: OpeningNode, sans: string[]): boolean {
  return lineStatus(tree, node, sans) !== 'outside';
}

/** The openings these ids name, each once, with the side that plays it. */
export function picksFrom(tree: OpeningTree, ids: Iterable<string>): OpeningPick[] {
  const out: OpeningPick[] = [];
  const seen = new Set<string>();
  for (const id of ids) {
    if (seen.has(id)) continue;
    seen.add(id);
    const node = tree.byId.get(id);
    if (!node || node.sans.length === 0) continue;
    out.push({ id: node.id, name: node.name, color: playerOf(node.sans), sans: node.sans });
  }
  return out;
}

/** The openings named a move late, which `playerOf` corrects. */
export const NAMED_LATE_IDS = Object.keys(NAMED_LATE);

export function starterSet(id: string): StarterSet | null {
  return STARTER_SETS.find((set) => set.id === id) ?? null;
}

export function setSeed(set: StarterSet): SeedOpening[] {
  return setOpenings(set).map(({ id, color }) => ({ sans: id.split(' '), color }));
}

/** Every Tidy find in a region, biggest savings first: the list Tidy shows. */
export function tidyFinds(
  reps: Repertoire[],
  index: ReferenceIndex,
  tree: OpeningTree,
  region: OpeningNode,
  opts: TidyOptions,
): TidyFind[] {
  const out: TidyFind[] = [];
  for (const { rep, node } of tidyPositions(reps, tree, region)) {
    const find = findAt(rep, index, node, opts);
    if (find) out.push(find);
  }
  return sortFinds(out);
}

/** What one right and one wrong answer would do to a rating. */
export function ratingSwing(rating: number): { up: number; down: number } {
  return {
    up: ratingAfter(rating, true) - rating,
    down: ratingAfter(rating, false) - rating,
  };
}

export const EMPTY_SURVIVAL_RECORD: SurvivalRecord = { global: { ...EMPTY_SURVIVAL_SCORE }, openings: {} };

/** A parsed game flattened into every distinct line, the mainline and each variation. */
export function allLines(game: PgnGame, startFen = START_FEN, maxLines = 200): { sans: string[]; branchPly: number }[] {
  const out: { sans: string[]; branchPly: number }[] = [];
  const rootFen = game.headers.FEN ?? startFen;
  const walk = (nodes: PgnNode[], fen: string, sans: string[], branchPly: number) => {
    if (out.length >= maxLines) return;
    if (!nodes.length) {
      if (sans.length) out.push({ sans, branchPly });
      return;
    }
    nodes.forEach((node, idx) => {
      const move = applySan(fen, node.san);
      if (!move) return;
      walk(node.children, move.after, [...sans, move.san], idx === 0 ? branchPly : sans.length);
    });
  };
  walk(game.moves, rootFen, [], 0);
  return out;
}
