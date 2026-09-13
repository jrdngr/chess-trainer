import {
  applySan,
  fenTurn,
  positionKey,
  sansToMoveText,
  START_FEN,
  type Color,
} from '../chess/core';
import type { MoveSource, RepMove, Repertoire } from './types';

let idCounter = 0;
export function newId(prefix = 'n'): string {
  idCounter += 1;
  return `${prefix}_${Date.now().toString(36)}_${idCounter.toString(36)}`;
}

export function createRepertoire(name: string, color: Color, id = newId('rep')): Repertoire {
  return {
    id,
    name,
    color,
    rootFen: START_FEN,
    rootChildren: [],
    nodes: {},
    createdAt: Date.now(),
  };
}

export function childrenOf(rep: Repertoire, nodeId: string | null): RepMove[] {
  const ids = nodeId === null ? rep.rootChildren : (rep.nodes[nodeId]?.children ?? []);
  return ids.map((id) => rep.nodes[id]).filter(Boolean);
}

/**
 * Is this whole line already in the repertoire?
 *
 * Read-only, so a screen can tell you there is nothing to add before you tap
 * rather than after.
 */
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

export function fenAt(rep: Repertoire, nodeId: string | null): string {
  if (nodeId === null) return rep.rootFen;
  return rep.nodes[nodeId]?.fenAfter ?? rep.rootFen;
}

/** Path of moves from the root down to (and including) `nodeId`. */
export function pathTo(rep: Repertoire, nodeId: string | null): RepMove[] {
  const out: RepMove[] = [];
  let cur = nodeId;
  while (cur) {
    const node = rep.nodes[cur];
    if (!node) break;
    out.unshift(node);
    cur = node.parentId;
  }
  return out;
}

export function lineText(rep: Repertoire, nodeId: string | null): string {
  return sansToMoveText(pathTo(rep, nodeId).map((m) => m.san), rep.rootFen);
}

/** Find an existing child of `parentId` that plays `san`. */
export function findChildBySan(
  rep: Repertoire,
  parentId: string | null,
  san: string,
): RepMove | undefined {
  return childrenOf(rep, parentId).find((m) => m.san === san);
}

export interface AddMoveResult {
  rep: Repertoire;
  node: RepMove;
  created: boolean;
}

/**
 * Add a single move under `parentId`. Idempotent: replaying the same move
 * returns the existing node instead of duplicating it.
 */
export function addMove(
  rep: Repertoire,
  parentId: string | null,
  san: string,
  source: MoveSource = 'manual',
): AddMoveResult | null {
  const fenBefore = fenAt(rep, parentId);
  const existing = findChildBySan(rep, parentId, san);
  if (existing) return { rep, node: existing, created: false };

  const move = applySan(fenBefore, san);
  if (!move) return null;

  const node: RepMove = {
    id: newId(),
    parentId,
    repertoireId: rep.id,
    fenBefore,
    key: positionKey(fenBefore),
    san: move.san,
    uci: move.uci,
    fenAfter: move.after,
    children: [],
    // First move added from a position becomes the preferred one.
    preferred: childrenOf(rep, parentId).length === 0,
    source,
    addedAt: Date.now(),
  };

  const nodes = { ...rep.nodes, [node.id]: node };
  let rootChildren = rep.rootChildren;
  if (parentId === null) {
    rootChildren = [...rep.rootChildren, node.id];
  } else {
    const parent = nodes[parentId];
    nodes[parentId] = { ...parent, children: [...parent.children, node.id] };
  }
  return { rep: { ...rep, nodes, rootChildren }, node, created: true };
}

/** Add a whole SAN line, reusing existing nodes where they already match. */
export function addLine(
  rep: Repertoire,
  sans: string[],
  source: MoveSource = 'manual',
  startNodeId: string | null = null,
): { rep: Repertoire; added: number; tipId: string | null } {
  let current = rep;
  let parentId = startNodeId;
  let added = 0;
  for (const san of sans) {
    const res = addMove(current, parentId, san, source);
    if (!res) break;
    current = res.rep;
    parentId = res.node.id;
    if (res.created) added += 1;
  }
  return { rep: current, added, tipId: parentId };
}

/** Remove a node and everything below it. */
export function removeSubtree(rep: Repertoire, nodeId: string): Repertoire {
  const node = rep.nodes[nodeId];
  if (!node) return rep;
  const nodes = { ...rep.nodes };
  const stack = [nodeId];
  while (stack.length) {
    const id = stack.pop()!;
    const n = nodes[id];
    if (!n) continue;
    stack.push(...n.children);
    delete nodes[id];
  }
  let rootChildren = rep.rootChildren;
  if (node.parentId === null) {
    rootChildren = rep.rootChildren.filter((id) => id !== nodeId);
  } else if (nodes[node.parentId]) {
    const parent = nodes[node.parentId];
    const remaining = parent.children.filter((id) => id !== nodeId);
    nodes[node.parentId] = { ...parent, children: remaining };
    // If we deleted the preferred move, promote the first remaining sibling.
    if (node.preferred && remaining.length && !remaining.some((id) => nodes[id]?.preferred)) {
      nodes[remaining[0]] = { ...nodes[remaining[0]], preferred: true };
    }
  }
  if (node.parentId === null && node.preferred && rootChildren.length) {
    const first = rootChildren[0];
    if (!rootChildren.some((id) => nodes[id]?.preferred)) {
      nodes[first] = { ...nodes[first], preferred: true };
    }
  }
  return { ...rep, nodes, rootChildren };
}

/**
 * Remove a node, everything below it, and the moves that only led to it.
 *
 * This is what deleting an opening means. A derived opening begins where the
 * book starts naming the position, which is often several moves in: a Black
 * King's Indian is named at 1.d4 Nf6 2.c4 g6 3.Nc3 Bg7 4.e4, so removing only
 * the subtree would leave six moves standing that now lead nowhere. Climbing
 * while the parent has nothing else under it stops at the first real branch
 * point, so an opening that shares a move order with another one keeps it.
 */
export function pruneLine(rep: Repertoire, nodeId: string): Repertoire {
  const start = rep.nodes[nodeId];
  if (!start) return rep;
  let next = removeSubtree(rep, nodeId);
  let parentId = start.parentId;
  while (parentId) {
    const parent = next.nodes[parentId];
    if (!parent || parent.children.length > 0) break;
    const grandparent = parent.parentId;
    next = removeSubtree(next, parentId);
    parentId = grandparent;
  }
  return next;
}

/** How many moves `pruneLine` would take, without taking them. */
export function pruneCount(rep: Repertoire, nodeId: string): number {
  const start = rep.nodes[nodeId];
  if (!start) return 0;
  let count = subtreeIds(rep, nodeId).length;
  let childId = nodeId;
  let parentId = start.parentId;
  while (parentId) {
    const parent = rep.nodes[parentId];
    if (!parent || parent.children.some((id) => id !== childId)) break;
    count += 1;
    childId = parentId;
    parentId = parent.parentId;
  }
  return count;
}

/** Make `nodeId` the preferred move among its siblings. */
export function setPreferred(rep: Repertoire, nodeId: string): Repertoire {
  const node = rep.nodes[nodeId];
  if (!node) return rep;
  const siblings = childrenOf(rep, node.parentId);
  const nodes = { ...rep.nodes };
  for (const sib of siblings) {
    nodes[sib.id] = { ...sib, preferred: sib.id === nodeId };
  }
  return { ...rep, nodes };
}

export function setNote(rep: Repertoire, nodeId: string, note: string): Repertoire {
  const node = rep.nodes[nodeId];
  if (!node) return rep;
  const trimmed = note.trim();
  const next: RepMove = { ...node, note: trimmed || undefined };
  return { ...rep, nodes: { ...rep.nodes, [nodeId]: next } };
}

/** Reorder a node among its siblings (used by the branch editor). */
export function moveSibling(rep: Repertoire, nodeId: string, delta: number): Repertoire {
  const node = rep.nodes[nodeId];
  if (!node) return rep;
  const listIds = node.parentId === null ? [...rep.rootChildren] : [...rep.nodes[node.parentId].children];
  const idx = listIds.indexOf(nodeId);
  const next = idx + delta;
  if (idx < 0 || next < 0 || next >= listIds.length) return rep;
  [listIds[idx], listIds[next]] = [listIds[next], listIds[idx]];
  if (node.parentId === null) return { ...rep, rootChildren: listIds };
  const parent = rep.nodes[node.parentId];
  return { ...rep, nodes: { ...rep.nodes, [parent.id]: { ...parent, children: listIds } } };
}

/** A position where it is the user's turn and the repertoire prescribes a move. */
export interface DecisionPoint {
  key: string;
  fen: string;
  repertoireId: string;
  /** Every repertoire move from this position (siblings), preferred first. */
  options: RepMove[];
  /** Shortest path from root to this position, in SAN. */
  pathSans: string[];
  /** Ply depth of the decision point. */
  depth: number;
}

/**
 * Every decision point in the repertoire, keyed by position.
 * Transpositions collapse: the same position reached two ways is one item.
 */
export function decisionPoints(rep: Repertoire): DecisionPoint[] {
  const byKey = new Map<string, DecisionPoint>();

  const visit = (nodeId: string | null, pathSans: string[]) => {
    const fen = fenAt(rep, nodeId);
    const kids = childrenOf(rep, nodeId);
    if (kids.length && fenTurn(fen) === rep.color) {
      const key = positionKey(fen);
      const existing = byKey.get(key);
      if (!existing || pathSans.length < existing.pathSans.length) {
        const options = [...kids].sort((a, b) => Number(b.preferred) - Number(a.preferred));
        byKey.set(key, {
          key,
          fen,
          repertoireId: rep.id,
          options,
          pathSans,
          depth: pathSans.length,
        });
      } else {
        // Same position reached by another route: merge the move options.
        const merged = [...existing.options];
        for (const kid of kids) {
          if (!merged.some((m) => m.san === kid.san)) merged.push(kid);
        }
        existing.options = merged;
      }
    }
    for (const kid of kids) visit(kid.id, [...pathSans, kid.san]);
  };

  visit(null, []);
  return [...byKey.values()].sort((a, b) => a.depth - b.depth);
}

export function countNodes(rep: Repertoire): number {
  return Object.keys(rep.nodes).length;
}

/** Leaf lines, longest first — useful for listing "your lines". */
export function leafLines(rep: Repertoire): { tipId: string; sans: string[] }[] {
  const out: { tipId: string; sans: string[] }[] = [];
  const visit = (nodeId: string | null, sans: string[]) => {
    const kids = childrenOf(rep, nodeId);
    if (!kids.length && nodeId) {
      out.push({ tipId: nodeId, sans });
      return;
    }
    for (const kid of kids) visit(kid.id, [...sans, kid.san]);
  };
  visit(null, []);
  return out.sort((a, b) => b.sans.length - a.sans.length);
}

/** All node ids inside the subtree rooted at `nodeId` (inclusive). */
export function subtreeIds(rep: Repertoire, nodeId: string): string[] {
  const out: string[] = [];
  const stack = [nodeId];
  while (stack.length) {
    const id = stack.pop()!;
    const n = rep.nodes[id];
    if (!n) continue;
    out.push(id);
    stack.push(...n.children);
  }
  return out;
}

/**
 * What a stored tree is called: "White repertoire" or "Black repertoire".
 *
 * There is exactly one tree per colour, and it is never named after an opening.
 * Naming it after whichever opening happened to create it was the old
 * behaviour, and it lied as soon as a second opening moved in: a container
 * called "King's Indian Defence" holding a Nimzo-Indian and a Dutch. Openings
 * are derived from the tree instead — see `openingsIn` — so the container only
 * has to say which side it is for.
 */
export function repertoireName(color: Color): string {
  return color === 'w' ? 'White repertoire' : 'Black repertoire';
}

/**
 * "White — Queen's Gambit" → "Queen's Gambit"; the side is shown separately.
 *
 * Kept for names a user typed themselves, and for trees saved before the
 * per-colour naming above.
 */
export function displayName(name: string): string {
  return name.replace(/^\s*(white|black)\s*[—–\-:]\s*/i, '').trim() || name;
}
