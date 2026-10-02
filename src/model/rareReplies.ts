import { fenTurn, type Color } from '../chess/core';
import { addedByYou, sourceLabel } from './moveSource';
import type { OpeningNode, OpeningTree } from './openingTree';
import { lookup, totalGamesAt, type ReferenceIndex } from './reference';
import { pathTo, subtreeIds } from './repertoire';
import { lineInRegion } from './selection';
import type { MoveSource, RepMove, Repertoire } from './types';

/**
 * Replies you prepared that strong players rarely or never choose.
 *
 * The book is games between strong players, so a move you meet at your level
 * all the time — 5.e5 against the King's Indian — can be missing from it
 * entirely. That is no reason to drop it: training plays it at its floor (see
 * `PREPARED_FLOOR`). Tidy lists it once so you know the book will not back it
 * up and where it came from, and you keep it or remove it.
 *
 * Only replies you put in yourself are listed. One that came from the book or
 * the engine is there because they offered it.
 */
export interface RareReply {
  /** Stable while the line is unchanged: the repertoire and the reply's node. */
  id: string;
  repertoireId: string;
  color: Color;
  nodeId: string;
  san: string;
  /** The line to the position the reply is played from, and that position. */
  path: string[];
  fen: string;
  source: MoveSource;
  /** How often strong players choose it, in percent; 0 when the book lacks it. */
  share: number;
  /** Moves Remove takes: the reply and everything under it. */
  removes: number;
}

/** A kept reply stays off the list until something under it is newer than the keep. */
export function keptCurrent(rep: Repertoire, node: RepMove): boolean {
  if (!node.keptAt) return false;
  return subtreeIds(rep, node.id).every((id) => (rep.nodes[id]?.addedAt ?? 0) <= node.keptAt!);
}

/** The book's share of a move at a position, in percent, 0 when it lacks it. */
export function bookShare(index: ReferenceIndex, fen: string, san: string): number {
  const entry = lookup(index, fen);
  const total = entry ? totalGamesAt(entry) : 0;
  const games = entry?.moves.find((move) => move.san === san)?.games ?? 0;
  return total > 0 ? Math.round((games / total) * 1000) / 10 : 0;
}

/** Every prepared reply inside the region that you added and the book rates under `minShare`. */
export function rareReplies(
  reps: Repertoire[],
  index: ReferenceIndex,
  tree: OpeningTree,
  region: OpeningNode,
  minShare: number,
): RareReply[] {
  const out: RareReply[] = [];
  for (const rep of reps) {
    const seen = new Set<string>();
    for (const node of Object.values(rep.nodes)) {
      if (fenTurn(node.fenBefore) === rep.color) continue;
      if (!addedByYou(node.source)) continue;
      const once = `${node.key}|${node.san}`;
      if (seen.has(once)) continue;
      seen.add(once);
      const share = bookShare(index, node.fenBefore, node.san);
      if (share >= minShare) continue;
      if (keptCurrent(rep, node)) continue;
      const path = pathTo(rep, node.parentId).map((move) => move.san);
      if (!lineInRegion(tree, region, [...path, node.san])) continue;
      out.push({
        id: `${rep.id}#${node.id}`,
        repertoireId: rep.id,
        color: rep.color,
        nodeId: node.id,
        san: node.san,
        path,
        fen: node.fenBefore,
        source: node.source,
        share,
        removes: subtreeIds(rep, node.id).length,
      });
    }
  }
  return out.sort((a, b) => a.path.length - b.path.length || b.removes - a.removes);
}

/**
 * What the card says: where the reply came from, then what the book thinks of
 * it. Never that you will meet it rarely — the book is strong players only,
 * which is the wrong crowd to ask about that.
 */
export function rareReason(reply: Pick<RareReply, 'source' | 'share'>): string {
  const book =
    reply.share > 0
      ? `strong players choose it in ${reply.share}% of games`
      : 'strong players never choose it';
  return `${sourceLabel(reply.source)} · ${book}`;
}
