import { fenTurn, positionKey } from '../chess/core';
import type { MoveKind } from './extensions';
import { lookup, totalGamesAt, type ReferenceIndex } from './reference';
import { childrenOf, pathTo, subtreeIds } from './repertoire';
import type { RepMove, Repertoire } from './types';

/**
 * The Extensions review's graph: one opening drawn as a grid of moves, laid
 * out by fixed rules so the picture is computed, never hand-tuned (the rules
 * are in the extensions design doc):
 *
 * - Columns are half-moves from the opening's root; every column is the same
 *   width, so all the choices at one move line up.
 * - Rows go depth first. A node's first child carries on along its row, and
 *   each other child starts a new row below the whole subtree of the sibling
 *   before it, so a fork line never has to cross anything.
 * - At your move the move you play comes first, then book moves, extensions,
 *   and mistakes last. At the opponent's, book replies by share, extensions
 *   last.
 * - A move into a position already drawn higher up ends its row with a join
 *   pointing at that row. A line past `MAX_PLIES` ends in a "+N" cell.
 * - The Extensions filter drops every subtree without an extension in it,
 *   keeping the path down to each one.
 */

export const MAX_PLIES = 16;

export type CellKind = MoveKind | 'join' | 'more';

export interface GraphCell {
  kind: CellKind;
  /** The move's node; absent on a join or a "+N". */
  nodeId?: string;
  label: string;
  /** For a join, the row that already holds the position. */
  joinRow?: number;
}

export interface GraphRow {
  /** Where the row forks off: a row and column of the parent's cell. Null for a top row. */
  parent: { row: number; col: number } | null;
  /** The column of the row's first cell. */
  start: number;
  cells: GraphCell[];
}

const RANK: Record<MoveKind, number> = { book: 0, rare: 1, past: 1, mistake: 2 };

function shareOf(index: ReferenceIndex, node: RepMove): number {
  const entry = lookup(index, node.fenBefore);
  const total = totalGamesAt(entry);
  const games = entry?.moves.find((m) => m.san === node.san)?.games ?? 0;
  return total > 0 ? games / total : 0;
}

/** A node's children in the order the graph draws them. */
export function orderedKids(rep: Repertoire, index: ReferenceIndex, kinds: Map<string, MoveKind>, nodeId: string): RepMove[] {
  const kids = childrenOf(rep, nodeId);
  if (kids.length < 2) return kids;
  const yours = fenTurn(kids[0].fenBefore) === rep.color;
  const rank = (n: RepMove) => RANK[kinds.get(n.id) ?? 'book'];
  return [...kids].sort((a, b) => {
    if (yours) return Number(b.preferred) - Number(a.preferred) || rank(a) - rank(b);
    return rank(a) - rank(b) || shareOf(index, b) - shareOf(index, a);
  });
}

/** Lay out the moves under `rootId`, the opening's root, as rows of cells. */
export function layoutGraph(
  rep: Repertoire,
  index: ReferenceIndex,
  kinds: Map<string, MoveKind>,
  rootId: string,
  { extOnly = false }: { extOnly?: boolean } = {},
): GraphRow[] {
  const holdsExtension = new Map<string, boolean>();
  const hasExt = (node: RepMove): boolean => {
    const known = holdsExtension.get(node.id);
    if (known !== undefined) return known;
    const own = (kinds.get(node.id) ?? 'book') !== 'book';
    const out = own || childrenOf(rep, node.id).some(hasExt);
    holdsExtension.set(node.id, out);
    return out;
  };

  const rows: GraphRow[] = [];
  const seen = new Map<string, number>();
  const root = rep.nodes[rootId];
  if (root) seen.set(positionKey(root.fenAfter), -1);

  const walk = (nodeId: string, col: number, rowIdx: number | null, parent: GraphRow['parent']) => {
    let kids = orderedKids(rep, index, kinds, nodeId);
    if (extOnly) kids = kids.filter(hasExt);
    kids.forEach((child, i) => {
      let r = rowIdx;
      if (i > 0 || r === null) {
        rows.push({ parent, start: col, cells: [] });
        r = rows.length - 1;
      }
      const row = rows[r];
      if (col >= MAX_PLIES) {
        row.cells.push({ kind: 'more', label: `+${subtreeIds(rep, child.id).length}` });
        return;
      }
      const kind = kinds.get(child.id) ?? 'book';
      row.cells.push({ kind, nodeId: child.id, label: child.san });
      const key = positionKey(child.fenAfter);
      const earlier = seen.get(key);
      if (earlier !== undefined && earlier >= 0) {
        row.cells.push({ kind: 'join', label: `↗${earlier + 1}`, joinRow: earlier });
        return;
      }
      seen.set(key, r);
      walk(child.id, col + 1, r, { row: r, col });
    });
  };
  walk(rootId, 0, null, null);
  return rows;
}

/** Where a node's extension begins: its first move off the book, or null for a book move. */
export function extensionRoot(rep: Repertoire, kinds: Map<string, MoveKind>, nodeId: string): RepMove | null {
  let found: RepMove | null = null;
  for (const node of [...pathTo(rep, nodeId)].reverse()) {
    if ((kinds.get(node.id) ?? 'book') === 'book') break;
    found = node;
  }
  return found;
}

/** Every extension's first move in a tree, top of the tree first. */
export function extensionRoots(rep: Repertoire, kinds: Map<string, MoveKind>): RepMove[] {
  return Object.values(rep.nodes)
    .filter((node) => (kinds.get(node.id) ?? 'book') !== 'book')
    .filter((node) => !node.parentId || (kinds.get(node.parentId) ?? 'book') === 'book')
    .sort((a, b) => pathTo(rep, a.id).length - pathTo(rep, b.id).length);
}

/** A kept extension stays reviewed until something under it is newer than the keep. */
export function keptCurrent(rep: Repertoire, node: RepMove): boolean {
  if (!node.keptAt) return false;
  return subtreeIds(rep, node.id).every((id) => (rep.nodes[id]?.addedAt ?? 0) <= node.keptAt!);
}
