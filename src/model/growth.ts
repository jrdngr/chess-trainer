import { applySan, fenTurn, positionKey, type Color } from '../chess/core';
import { deepestName, lookup, totalGamesAt, type ReferenceIndex } from './reference';
import { childrenOf, fenAt } from './repertoire';
import type { ExplorerMove, RepMove, Repertoire } from './types';

/**
 * Growth: the repertoire gets one move wider, every run.
 *
 * The other modes all need a repertoire to work on — Drill asks about what is
 * in it, Repair compares games against it, Opening Run replays it. Growth is
 * where it comes from after the first line: you walk your own prep from move
 * one, the opponent steers toward the nearest thing you have no answer to, and
 * when it arrives you choose one move and the run ends.
 *
 * One move per run is the whole point. It is small enough to finish in a few
 * taps, so the repertoire grows by repetition rather than by a long sitting.
 */

/** The least popular a reply can be and still be worth preparing for. */
export const DEFAULT_MIN_SHARE = 1;
/** Past here, a line running out is play rather than a hole in the prep. */
export const DEFAULT_MAX_PLY = 18;

export interface GrowthOptions {
  minShare?: number;
  maxPly?: number;
}

/**
 * A reply you have no answer to.
 *
 * Unlike `findGaps`, this counts positions where the prep stops outright. That
 * distinction matters here and nowhere else: a line that simply ends is not a
 * contradiction to report, but it is precisely the thing Growth exists to
 * extend, and on a thin repertoire it is the commonest shape there is.
 */
export interface Hole {
  /** Moves from the start to the position the opponent chooses in. */
  path: string[];
  /** That position — the opponent is to move. */
  fen: string;
  /** The reply you cannot meet. */
  san: string;
  share: number;
  games: number;
  /** The position their reply leads to, where your new move goes. */
  after: string;
  /** The repertoire node the opponent moved from, or null at the root. */
  nodeId: string | null;
}

/** Every unanswered reply in a repertoire, shallowest and most popular first. */
export function findHoles(
  rep: Repertoire,
  index: ReferenceIndex,
  opts: GrowthOptions = {},
): Hole[] {
  const minShare = opts.minShare ?? DEFAULT_MIN_SHARE;
  const maxPly = opts.maxPly ?? DEFAULT_MAX_PLY;
  const holes: Hole[] = [];
  const seen = new Set<string>();

  const walk = (nodeId: string | null, path: string[]) => {
    const fen = fenAt(rep, nodeId);
    const kids = childrenOf(rep, nodeId);
    if (path.length < maxPly && fenTurn(fen) !== rep.color) {
      const key = positionKey(fen);
      // Transpositions reach the same choice twice; the shallower route wins
      // because the walk is depth-first from the root.
      if (!seen.has(key)) {
        seen.add(key);
        const prepared = new Set(kids.map((kid) => kid.san));
        for (const move of popularReplies(index, fen, minShare)) {
          if (prepared.has(move.san)) continue;
          const after = applySan(fen, move.san);
          if (!after) continue;
          holes.push({
            path,
            fen,
            san: move.san,
            share: move.share,
            games: move.games,
            after: after.after,
            nodeId,
          });
        }
      }
    }
    if (path.length >= maxPly) return;
    for (const kid of kids) walk(kid.id, [...path, kid.san]);
  };

  walk(null, []);
  return holes.sort((a, b) => a.path.length - b.path.length || b.share - a.share);
}

/** Book replies at a position that are played often enough to prepare for. */
function popularReplies(
  index: ReferenceIndex,
  fen: string,
  minShare: number,
): (ExplorerMove & { share: number })[] {
  const entry = lookup(index, fen);
  if (!entry) return [];
  const total = totalGamesAt(entry);
  if (total === 0) return [];
  return entry.moves
    .map((move) => ({ ...move, share: Math.round((move.games / total) * 1000) / 10 }))
    .filter((move) => move.share >= minShare)
    .sort((a, b) => b.games - a.games);
}

/* ── the lobby ──────────────────────────────────────────────────────────── */

/**
 * One opening with work available in it.
 *
 * Rows are grouped by the deepest opening name above each hole, so a White
 * repertoire that has answered 1...c5 and 1...e6 offers a Sicilian row and a
 * French one. Holes too shallow to sit under any name — an unanswered 1...e5,
 * or a Black repertoire that meets 1.e4 but not 1.d4 — fall into a row named
 * after the repertoire itself. Those are exactly the most urgent ones, so they
 * must never be the ones without a home.
 */
export interface GrowthRow {
  id: string;
  repertoireId: string;
  color: Color;
  name: string;
  eco?: string;
  /** Plies to the shallowest hole in this row — the urgency signal. */
  depth: number;
  holes: Hole[];
}

export function growthRows(
  reps: Repertoire[],
  index: ReferenceIndex,
  opts: GrowthOptions = {},
): GrowthRow[] {
  const rows: GrowthRow[] = [];

  for (const rep of reps) {
    const byName = new Map<string, GrowthRow>();
    for (const hole of findHoles(rep, index, opts)) {
      const named = deepestName(index, hole.path);
      const name = named?.name ?? repertoireLabel(rep);
      const id = `${rep.id}#${name}`;
      const row = byName.get(id);
      if (row) {
        row.holes.push(hole);
        row.depth = Math.min(row.depth, hole.path.length);
        continue;
      }
      byName.set(id, {
        id,
        repertoireId: rep.id,
        color: rep.color,
        name,
        eco: named?.eco,
        depth: hole.path.length,
        holes: [hole],
      });
    }
    rows.push(...byName.values());
  }

  // Shallowest first: the shallower the hole, the more games fall into it.
  return rows.sort((a, b) => a.depth - b.depth || b.holes.length - a.holes.length);
}

function repertoireLabel(rep: Repertoire): string {
  return rep.name.replace(/^\s*(white|black)\s*[—–\-:]\s*/i, '').trim() || rep.name;
}

/* ── the run ────────────────────────────────────────────────────────────── */

export interface GrowthRun {
  repertoireId: string;
  color: Color;
  /** Which row's holes the opponent is steering toward. */
  rowId: string;
  /** Position keys the run is aiming for. */
  targets: Set<string>;
  path: string[];
  fen: string;
  /** Where we are in the repertoire, or null at the root. */
  nodeId: string | null;
  /**
   * The unanswered reply the opponent has just played, once it has. Stepping
   * into a hole leaves the repertoire tree — there is no node for a move the
   * repertoire does not have — so the run has to carry it rather than infer it
   * from where it stands.
   */
  hole: Hole | null;
}

export function startGrowth(rep: Repertoire, row: GrowthRow): GrowthRun {
  return {
    repertoireId: rep.id,
    color: rep.color,
    rowId: row.id,
    targets: new Set(row.holes.map((hole) => positionKey(hole.fen))),
    path: [],
    fen: rep.rootFen,
    nodeId: null,
    hole: null,
  };
}

export function isUsersTurn(run: GrowthRun): boolean {
  return fenTurn(run.fen) === run.color;
}

/** The moves the repertoire prepares at the run's current position. */
export function preparedHere(rep: Repertoire, run: GrowthRun): RepMove[] {
  return childrenOf(rep, run.nodeId);
}

/** Play a move that the repertoire already has. */
export function advance(rep: Repertoire, run: GrowthRun, san: string): GrowthRun | null {
  const kid = preparedHere(rep, run).find((child) => child.san === san);
  if (!kid) return null;
  return { ...run, path: [...run.path, kid.san], fen: kid.fenAfter, nodeId: kid.id };
}

/**
 * The opponent's reply, chosen to reach a hole as soon as possible.
 *
 * A hole right here is taken at once; otherwise the run continues down whichever
 * prepared reply has one nearest. Steering makes the opponent slightly
 * artificial and that is the trade: without it the walk wanders, and the mode's
 * whole point is to reach the next unanswered move quickly.
 */
export function steer(
  rep: Repertoire,
  index: ReferenceIndex,
  run: GrowthRun,
  opts: GrowthOptions = {},
): { san: string; hole: Hole | null } | null {
  const here = findHoles(rep, index, opts).filter(
    (hole) => positionKey(hole.fen) === positionKey(run.fen) && run.targets.has(positionKey(hole.fen)),
  );
  if (here.length) return { san: here[0].san, hole: here[0] };

  const kids = childrenOf(rep, run.nodeId);
  if (!kids.length) return null;
  let best: { kid: RepMove; distance: number } | null = null;
  for (const kid of kids) {
    const distance = distanceToTarget(rep, kid.id, run.targets, 0);
    if (distance === null) continue;
    if (!best || distance < best.distance) best = { kid, distance };
  }
  const chosen = best?.kid ?? kids[0];
  return { san: chosen.san, hole: null };
}

/** Plies from a node down to the nearest position the run is aiming at. */
function distanceToTarget(
  rep: Repertoire,
  nodeId: string,
  targets: Set<string>,
  depth: number,
): number | null {
  if (depth > DEFAULT_MAX_PLY) return null;
  const node = rep.nodes[nodeId];
  if (!node) return null;
  if (targets.has(positionKey(node.fenAfter))) return depth;
  let best: number | null = null;
  for (const kid of childrenOf(rep, nodeId)) {
    const found = distanceToTarget(rep, kid.id, targets, depth + 1);
    if (found !== null && (best === null || found < best)) best = found;
  }
  return best;
}

/** Step into the unanswered reply. The run is now outside the repertoire. */
export function enterHole(run: GrowthRun, hole: Hole): GrowthRun {
  return { ...run, path: [...run.path, hole.san], fen: hole.after, hole };
}

/**
 * True once the run has arrived somewhere the repertoire says nothing.
 *
 * Either the opponent played a reply with no answer, or — for a repertoire
 * whose line ends on the opponent's move rather than yours — it is simply your
 * turn and there is nothing prepared.
 */
export function atHole(rep: Repertoire, run: GrowthRun): boolean {
  if (run.hole) return true;
  return isUsersTurn(run) && childrenOf(rep, run.nodeId).length === 0;
}

/** What to offer at the hole: the book's replies, most played first. */
export function optionsAt(
  index: ReferenceIndex,
  fen: string,
  limit = 4,
): (ExplorerMove & { share: number })[] {
  return popularReplies(index, fen, 0).slice(0, limit);
}

/** The line a chosen move writes into the repertoire. */
export function lineFor(run: GrowthRun, san: string): string[] {
  return [...run.path, san];
}
