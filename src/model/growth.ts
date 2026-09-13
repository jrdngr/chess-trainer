import { applySan, fenTurn, positionKey, type Color, type Square } from '../chess/core';
import {
  familyName,
  lookup,
  namesAlong,
  totalGamesAt,
  type NamedLine,
  type ReferenceIndex,
} from './reference';
import { lineInRegion } from './selection';
import type { OpeningNode, OpeningTree } from './openingTree';
import { childrenOf, fenAt } from './repertoire';
import type { ExplorerMove, RepMove, Repertoire } from './types';

/**
 * Growth: the repertoire gets wider, every run.
 *
 * The other modes all need a repertoire to work on — Drill asks about what is
 * in it, Repair compares games against it, Run replays it. Growth is where it
 * comes from after the first line: you walk your own prep from move one, the
 * opponent steers toward the nearest thing you have no answer to, and when it
 * arrives you choose an answer to it.
 *
 * A run is a few moves at most — three — so it stays small enough to finish in
 * a few taps and the repertoire grows by repetition rather than by a long
 * sitting. Answering one move opens the next position for the same choice, and
 * you can stop at any of them.
 */

/** The least popular a reply can be and still be worth preparing for. */
export const DEFAULT_MIN_SHARE = 1;
/**
 * How many moves one run may add.
 *
 * Three rather than one, so a line can be given a shape — their reply, your
 * answer, their reply again — but still bounded, because the mode is meant to
 * be finished rather than sat with.
 */
export const MAX_ADDS = 3;
/** Past here, a line running out is play rather than a hole in the prep. */
export const DEFAULT_MAX_PLY = 18;

export interface GrowthOptions {
  minShare?: number;
  maxPly?: number;
  /**
   * Openings the player starred, as catalogue ids — the space-joined move order
   * that defines each one. Starring is how they say which openings they mean to
   * play, so it lifts those rows rather than reordering anything silently.
   */
  starred?: string[];
  /**
   * Only holes that lead into this region — or toward it: an unanswered reply
   * on the way into the Najdorf is Najdorf work, even though it sits before
   * the position the book names.
   */
  region?: { tree: OpeningTree; node: OpeningNode };
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
  const region = opts.region;
  const wanted = (line: string[]) => !region || lineInRegion(region.tree, region.node, line);

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
          if (!wanted([...path, move.san])) continue;
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
    for (const kid of kids) {
      // A branch that has already left the region has nothing in it to count.
      if (!wanted([...path, kid.san])) continue;
      walk(kid.id, [...path, kid.san]);
    }
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
 * One opening family with work available in it.
 *
 * A row is named for the opening its holes lead *into*, not the one they sit
 * in. That distinction is the whole usefulness of the lobby: a Black King's
 * Indian repertoire that cannot meet 1.e4 has its most urgent holes at the very
 * first move, and naming that row "King's Indian" — the repertoire it belongs
 * to — promises a King's Indian and then hands you a Sicilian.
 *
 * It is the *family* it leads into, not the exact variation. Named to the ply,
 * a thin King's Indian produces a dozen rows — Sämisch, Four Pawns, Averbakh,
 * Petrosian — which is an accurate reading of the prep and an unusable way to
 * choose what to do next. All of them are a King's Indian, and that is the
 * choice the player is actually making.
 */
export interface GrowthRow {
  id: string;
  repertoireId: string;
  color: Color;
  name: string;
  eco?: string;
  /** Plies to the shallowest hole in this row — the urgency signal. */
  depth: number;
  /** The share of the most played hole here, which is not always the first. */
  topShare: number;
  /** The player starred this opening, or something inside it. */
  starred: boolean;
  /** How badly this wants doing, 0..1, before the player's own preference. */
  urgency: number;
  /** Urgency with starring folded in. Orders the list and picks Recommended. */
  score: number;
  holes: Hole[];
}

/** How much a star is worth against raw urgency. */
export const STAR_BOOST = 1.6;

/**
 * How badly one row wants doing, 0..1.
 *
 * Depth dominates: the shallower a hole, the larger the share of your games
 * that fall into it, and an unanswered first move is a different order of
 * problem from a missing tenth. How often the reply is actually played scales
 * that, so a rare sideline at move two does not outrank a mainline at move
 * four. Breadth counts for a little — a family with six unanswered replies is
 * thinner than one with a single gap.
 */
export function rowUrgency(depth: number, topShare: number, holes: number): number {
  const early = 1 / (1 + depth / 3);
  const played = topShare <= 0 ? 0 : topShare / (topShare + 5);
  const breadth = 1 + 0.05 * Math.min(holes - 1, 4);
  return Math.max(0, Math.min(1, 1.5 * early * played * breadth));
}

/**
 * The family heading for a line.
 *
 * The shallowest name that says something, which is the first one past the
 * opening move: every line through 1.d4 is a "Queen's Pawn Opening", so that
 * heading groups a Black repertoire into one row and answers nothing. Where a
 * line has no name past the first move — an unanswered 1.e4 has nowhere deeper
 * to go — the first-move name is all there is, and it is still the right
 * heading for it.
 *
 * Walking positions rather than splitting names on ":" is what makes this work
 * for the book's abbreviations: "KID: Sämisch Variation" would give the family
 * "KID", where the position it passes through at move four is named "King's
 * Indian Defence".
 */
function family(index: ReferenceIndex, sans: string[]): NamedLine | null {
  const names = namesAlong(index, sans);
  const found = names.find((named) => named.ply >= 2) ?? names[names.length - 1];
  if (!found) return null;
  return { ...found, name: familyName(index, found.name) };
}

/** Is this line inside one of the openings the player starred? */
function isStarred(starred: string[][], sans: string[]): boolean {
  return starred.some(
    (fav) => fav.length > 0 && fav.length <= sans.length && fav.every((san, i) => sans[i] === san),
  );
}

export function growthRows(
  reps: Repertoire[],
  index: ReferenceIndex,
  opts: GrowthOptions = {},
): GrowthRow[] {
  const starred = (opts.starred ?? []).map((id) => id.split(/\s+/).filter(Boolean));
  const rows: GrowthRow[] = [];

  for (const rep of reps) {
    const byName = new Map<string, GrowthRow>();
    for (const hole of findHoles(rep, index, opts)) {
      const line = [...hole.path, hole.san];
      // A move the book cannot name anywhere gets a row of its own, called
      // after the move itself — filing 1.g3 under the name of the repertoire it
      // interrupts is how "pick King's Indian, get a Sicilian" happened.
      const named = family(index, line);
      const name = named?.name ?? moveLabel(hole);
      const id = `${rep.id}#${name}`;
      const row = byName.get(id);
      if (row) {
        row.holes.push(hole);
        row.depth = Math.min(row.depth, hole.path.length);
        row.topShare = Math.max(row.topShare, hole.share);
        row.starred = row.starred || isStarred(starred, line);
        continue;
      }
      byName.set(id, {
        id,
        repertoireId: rep.id,
        color: rep.color,
        name,
        eco: named?.eco,
        depth: hole.path.length,
        topShare: hole.share,
        starred: isStarred(starred, line),
        urgency: 0,
        score: 0,
        holes: [hole],
      });
    }
    rows.push(...byName.values());
  }

  for (const row of rows) {
    row.urgency = rowUrgency(row.depth, row.topShare, row.holes.length);
    row.score = Math.min(1, row.urgency * (row.starred ? STAR_BOOST : 1));
  }

  // One ordering for the list and for Recommended, so the button never starts
  // something other than the row sitting at the top of the list.
  return rows.sort((a, b) => b.score - a.score || a.depth - b.depth || a.name.localeCompare(b.name));
}

/** The row Start Recommended would begin, or nothing when there is no work. */
export function recommended(rows: GrowthRow[]): GrowthRow | null {
  return rows[0] ?? null;
}

/** A move the book has no name for, called after the move itself: "vs 1.g3". */
function moveLabel(hole: Hole): string {
  return `vs ${Math.floor(hole.path.length / 2) + 1}.${hole.path.length % 2 === 0 ? '' : '..'}${hole.san}`;
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

/**
 * Play your chosen answer. The run leaves the repertoire tree here.
 *
 * The move has just been written into the repertoire, but the run walks the
 * copy of the tree it started with — deliberately, so adding cannot re-steer it
 * mid-run — and that copy will never have it.
 */
export function answerHole(run: GrowthRun, san: string): GrowthRun | null {
  const move = applySan(run.fen, san);
  if (!move) return null;
  return { ...run, path: [...run.path, san], fen: move.after, hole: null };
}

/**
 * What they would play against the answer you just added, as the next hole.
 *
 * The book's most popular reply, since nothing steers any more: past the
 * repertoire there is no target left to walk toward, and the commonest move is
 * the one most worth having an answer to.
 */
export function nextHole(index: ReferenceIndex, run: GrowthRun): Hole | null {
  const reply = popularReplies(index, run.fen, 0)[0];
  if (!reply) return null;
  const after = applySan(run.fen, reply.san);
  if (!after) return null;
  return {
    path: run.path,
    fen: run.fen,
    san: reply.san,
    share: reply.share,
    games: reply.games,
    after: after.after,
    nodeId: null,
  };
}

/** What to offer at the hole: the book's replies, most played first. */
export function optionsAt(
  index: ReferenceIndex,
  fen: string,
  limit = 4,
): (ExplorerMove & { share: number })[] {
  return popularReplies(index, fen, 0).slice(0, limit);
}

/**
 * The moves worth drawing on the board: the best one for each of a few pieces.
 *
 * Arrows rather than a ranking, because two moves of the same piece draw two
 * arrows out of one square and read as a single choice. Once a piece has its
 * arrow the rest of its moves are skipped, and the book list is read further
 * down than the buttons go to find another piece — what makes an arrow useful
 * is a piece you can see it leaving, not where the move happens to rank.
 */
export function movesToDraw(
  index: ReferenceIndex,
  fen: string,
  count = 3,
): { san: string; from: Square; to: Square }[] {
  const out: { san: string; from: Square; to: Square }[] = [];
  const pieces = new Set<Square>();
  for (const option of popularReplies(index, fen, 0)) {
    const move = applySan(fen, option.san);
    if (!move || pieces.has(move.from)) continue;
    pieces.add(move.from);
    out.push({ san: option.san, from: move.from, to: move.to });
    if (out.length === count) break;
  }
  return out;
}

/** The line a chosen move writes into the repertoire. */
export function lineFor(run: GrowthRun, san: string): string[] {
  return [...run.path, san];
}
