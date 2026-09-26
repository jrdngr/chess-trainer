import { fenTurn, positionKey, type Color } from '../chess/core';
import { movesToDraw, popularReplies } from './growth';
import { bestSwitch, familiarOffBook, goneWith, isFirstMove, type NudgePrefs, type TowardKind } from './nudge';
import { lineInRegion } from './selection';
import type { OpeningNode, OpeningTree } from './openingTree';
import type { ReferenceIndex } from './reference';
import { addMove, pathTo, removeSubtree, setPreferred, subtreeIds } from './repertoire';
import type { RepMove, Repertoire } from './types';

/**
 * Tidy: finding the places a repertoire could converge.
 *
 * Every move you have chosen is compared with the moves you could have chosen
 * instead, by the same familiarity the Growth arrows use: does it transpose
 * into your other lines, head toward them, or repeat a habit from this opening
 * and its kin. Where another move is closer to the rest of your lines than
 * yours, that is a find: switch to it, and your move and everything under it
 * go.
 *
 * Your own move is judged against the repertoire *without* its subtree, so it
 * gets no credit for being the line it already is — only for meeting your
 * other lines.
 */

export interface TidyFind {
  /** Stable while the line is unchanged: the repertoire and your move's node. */
  id: string;
  repertoireId: string;
  color: Color;
  /** Your move at the position. */
  nodeId: string;
  mine: string;
  /** The line to the position, and the position itself. */
  path: string[];
  fen: string;
  key: string;
  /** The move to switch to. */
  suggestion: string;
  /** What makes the suggestion familiar. */
  kind: TowardKind;
  /** Green when the board would draw it anyway; yellow when it is pulled in. */
  tone: 'toward' | 'toward-far';
  /** A move the book does not have (or ranks under the minimum): the engine must pass it first. */
  offBook: boolean;
  reason: string;
  /** Why your move works against your lines, when it does. */
  against: string | null;
  /** Moves the switch removes: your move and everything under it. */
  removes: number;
}

export interface TidyOptions {
  prefs: NudgePrefs;
  /** The least share of games a book move needs to be offered, in percent. */
  minShare: number;
}

/** The one switch that would tidy a position, or null when your move is as familiar as any. */
export function findAt(
  rep: Repertoire,
  index: ReferenceIndex,
  node: RepMove,
  opts: TidyOptions,
  candidates?: string[],
): TidyFind | null {
  const line = pathTo(rep, node.parentId);
  const path = line.map((move) => move.san);
  // Your first move picks the opening; two first moves are two openings, not a loose end.
  if (isFirstMove(path)) return null;
  const fen = node.fenBefore;
  const gone = goneWith(rep, index, node.id);
  const pathKeys = [positionKey(rep.rootFen), ...line.map((move) => positionKey(move.fenAfter))];
  const siblings = new Set(
    (node.parentId ? (rep.nodes[node.parentId]?.children ?? []) : rep.rootChildren).map((id) => rep.nodes[id]?.san),
  );
  const book = popularReplies(index, fen, opts.minShare).map((move) => move.san);
  const extra = candidates
    ? []
    : familiarOffBook(rep, index, path, fen, opts.prefs, opts.minShare, { gone, pathKeys, habitsOnly: true });
  const options = (candidates ?? [...book, ...extra]).filter((san) => !siblings.has(san));
  if (!options.length) return null;

  const best = bestSwitch(rep, index, path, fen, node.san, options, opts.prefs, opts.minShare, {
    gone,
    pathKeys,
    against: false,
  });
  if (!best) return null;
  const drawn = new Set(movesToDraw(index, fen).map((move) => move.san));
  return {
    id: `${rep.id}#${node.id}`,
    repertoireId: rep.id,
    color: rep.color,
    nodeId: node.id,
    mine: node.san,
    path,
    fen,
    key: node.key,
    suggestion: best.san,
    kind: best.kind,
    tone: drawn.has(best.san) ? 'toward' : 'toward-far',
    offBook: !book.includes(best.san),
    reason: best.reason,
    against: best.against,
    removes: subtreeIds(rep, node.id).length,
  };
}

/** Your moves in a repertoire: the positions where you chose. */
export function yourMoves(rep: Repertoire): RepMove[] {
  return Object.values(rep.nodes).filter((node) => fenTurn(node.fenBefore) === rep.color);
}

/**
 * The positions a scan looks at: your moves inside a region. A position met
 * by two move orders is one decision, so it is looked at once.
 */
export function tidyPositions(
  reps: Repertoire[],
  tree: OpeningTree,
  region: OpeningNode,
): { rep: Repertoire; node: RepMove }[] {
  const out: { rep: Repertoire; node: RepMove }[] = [];
  for (const rep of reps) {
    const seen = new Set<string>();
    for (const node of yourMoves(rep)) {
      const once = `${node.key}|${node.san}`;
      if (seen.has(once)) continue;
      seen.add(once);
      const path = pathTo(rep, node.parentId).map((move) => move.san);
      if (lineInRegion(tree, region, path)) out.push({ rep, node });
    }
  }
  return out;
}

/** Every find inside a region, biggest savings first. */
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

export function sortFinds(finds: TidyFind[]): TidyFind[] {
  return [...finds].sort((a, b) => b.removes - a.removes || a.path.length - b.path.length);
}

/**
 * The hint at the end of a round: was the move you played off your prep
 * closer to the rest of your lines than the prepared one?
 *
 * `path` is the line played to the position; the prepared move is found by
 * position, since a round can reach it by a move order your tree files
 * elsewhere.
 */
export function offPrepHint(
  rep: Repertoire | null | undefined,
  index: ReferenceIndex,
  fen: string,
  played: string,
  expected: string,
  opts: TidyOptions,
): TidyFind | null {
  if (!rep) return null;
  const key = positionKey(fen);
  const node = Object.values(rep.nodes).find((n) => n.key === key && n.san === expected);
  if (!node) return null;
  return findAt(rep, index, node, opts, [played]);
}

/**
 * Switch your move at a position: the new move becomes yours there, and the
 * old one goes with everything under it. Null when the move is not legal.
 */
export function switchMove(rep: Repertoire, nodeId: string, san: string): Repertoire | null {
  const old = rep.nodes[nodeId];
  if (!old) return null;
  const added = addMove(rep, old.parentId, san, 'manual');
  if (!added) return null;
  return removeSubtree(setPreferred(added.rep, added.node.id), nodeId);
}

/** "6.g3", "6...Nf6": a move with its number, from the plies before it. */
export function moveLabel(ply: number, san: string): string {
  return `${Math.floor(ply / 2) + 1}${ply % 2 === 0 ? '.' : '...'}${san}`;
}
