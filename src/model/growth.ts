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
import { ancestorsOf, descendantsOf, type OpeningNode, type OpeningTree } from './openingTree';
import { childrenOf, fenAt } from './repertoire';
import type { ExplorerMove, RepMove, Repertoire } from './types';

/**
 * Growth: the repertoire gets wider, every run.
 *
 * The other modes all need a repertoire to work on — Drill asks about what is
 * in it, Repair compares games against it, Run replays it. Growth is where it
 * comes from after the first line: a run starts standing on the reply you
 * would most often meet with no answer to it, and you choose one.
 *
 * A run adds a batch of answers, sized to how much room the line has left —
 * see `addsToFit` — so a hole at the second move is grown into a line and one
 * near the end of the opening is given the next move and no more. Answering
 * one move opens the next position for the same choice, you can stop at any of
 * them, and the reveal offers another batch rather than running on by itself.
 */

/** The least popular a reply can be and still be worth preparing for. */
export const DEFAULT_MIN_SHARE = 1;
/**
 * The most one batch of answers may add, however shallow the hole.
 *
 * The same ceiling a run carries at the edge of its prep: eight answers is
 * already a real line, and past that a batch stops being something you finish
 * in a sitting.
 */
export const MAX_ADDS = 8;
/** Past here, a line running out is play rather than a hole in the prep. */
export const DEFAULT_MAX_PLY = 18;

/**
 * How many moves are worth adding at a hole this far into a line.
 *
 * A line is grown to about the same length whether it starts at the first
 * move or the fifteenth. Nothing prepared against 1.e4 wants a line, not a
 * move: eight answers take it to a real position in one round. A line already
 * fourteen plies deep wants the next move or two and no more — it is nearly
 * out of opening, and what is added there is play rather than prep.
 *
 * Each answer carries the line two plies on: yours, then theirs. So the
 * budget is the plies left to the horizon, halved, and never less than one —
 * a hole past the horizon is still worth an answer, just not a line.
 */
export function movesToFit(depth: number, maxPly = 18): number {
  return Math.max(1, Math.round((maxPly - depth) / 2));
}

/**
 * What a batch of answers may add, starting at this depth.
 *
 * A flat three was the older rule, and it grew a stub of an opening at the
 * same rate as a line already out of book: a hole at the second move is worth
 * a line, a hole at the fourteenth is worth the next move and no more. The
 * ceiling keeps the shallowest holes from turning a run into a sitting.
 */
export function addsToFit(depth: number, maxPly = DEFAULT_MAX_PLY): number {
  return Math.min(MAX_ADDS, movesToFit(depth, maxPly));
}

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
   * the position the book names. Rows are then narrowed again, by name, to the
   * openings the selection covers — see `openingsInSelection`.
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
  /**
   * The share of games that get as far as this position, 0..1: every reply
   * the opponent chose on the way, multiplied together. Your own moves cost
   * nothing, because you are the one making them.
   *
   * `reach` times `share` is how often you would actually be sitting in front
   * of this unanswered reply — the only honest measure of what a hole is
   * worth. It is what separates a reply at move three from one at move
   * fourteen without any rule about depth, and a sideline nobody plays from a
   * main line, on the same scale.
   */
  reach: number;
}

/**
 * One position where the opponent chooses, as the walk finds it.
 *
 * Holes and coverage are two readings of the same walk — what you cannot meet,
 * and how much of what they would play you can — so they are taken together
 * rather than by walking the repertoire twice.
 */
interface Choice {
  path: string[];
  fen: string;
  nodeId: string | null;
  /** The share of games that get this far, 0..1. */
  reach: number;
  /** Book replies here worth preparing for, inside the region. */
  replies: (ExplorerMove & { share: number })[];
  /** The replies your prep answers. */
  prepared: Set<string>;
}

/** Every position inside a repertoire where the opponent has the move. */
function walkChoices(
  rep: Repertoire,
  index: ReferenceIndex,
  opts: GrowthOptions,
  visit: (choice: Choice) => void,
): void {
  const minShare = opts.minShare ?? DEFAULT_MIN_SHARE;
  const maxPly = opts.maxPly ?? DEFAULT_MAX_PLY;
  const seen = new Set<string>();
  const region = opts.region;
  const wanted = (line: string[]) => !region || lineInRegion(region.tree, region.node, line);

  const walk = (nodeId: string | null, path: string[], reach: number) => {
    const fen = fenAt(rep, nodeId);
    const kids = childrenOf(rep, nodeId);
    const theirs = fenTurn(fen) !== rep.color;
    if (path.length < maxPly && theirs) {
      const key = positionKey(fen);
      // Transpositions reach the same choice twice; the shallower route wins
      // because the walk is depth-first from the root.
      if (!seen.has(key)) {
        seen.add(key);
        visit({
          path,
          fen,
          nodeId,
          reach,
          replies: popularReplies(index, fen, minShare).filter((move) => wanted([...path, move.san])),
          prepared: new Set(kids.map((kid) => kid.san)),
        });
      }
    }
    if (path.length >= maxPly) return;
    // Only their moves narrow the field. A move of yours is one you have
    // decided to play, so every game down your own prep goes through it.
    const shares = theirs ? shareMap(index, fen) : null;
    for (const kid of kids) {
      // A branch that has already left the region has nothing in it to count.
      if (!wanted([...path, kid.san])) continue;
      walk(kid.id, [...path, kid.san], shares ? reach * (shares.get(kid.san) ?? RARE) : reach);
    }
  };

  walk(null, [], 1);
}

/**
 * How often the book plays each move at a position, as a share of 0..1.
 *
 * Every move, not only the popular ones: a reply below the threshold is not
 * worth preparing for, but it is still the way into everything prepared past
 * it, and calling that way in impossible would hide those holes entirely.
 */
function shareMap(index: ReferenceIndex, fen: string): Map<string, number> {
  const entry = lookup(index, fen);
  const total = entry ? totalGamesAt(entry) : 0;
  const out = new Map<string, number>();
  if (!entry || total === 0) return out;
  for (const move of entry.moves) out.set(move.san, Math.max(move.games / total, RARE));
  return out;
}

/** What a move the book has never seen is worth, so a line through it is not lost. */
const RARE = 0.0001;

/** Every unanswered reply in a repertoire, shallowest and most popular first. */
export function findHoles(
  rep: Repertoire,
  index: ReferenceIndex,
  opts: GrowthOptions = {},
): Hole[] {
  const holes: Hole[] = [];
  walkChoices(rep, index, opts, (choice) => {
    for (const move of choice.replies) {
      if (choice.prepared.has(move.san)) continue;
      const after = applySan(choice.fen, move.san);
      if (!after) continue;
      holes.push({
        path: choice.path,
        fen: choice.fen,
        san: move.san,
        share: move.share,
        games: move.games,
        after: after.after,
        nodeId: choice.nodeId,
        reach: choice.reach,
      });
    }
  });
  return holes.sort((a, b) => a.path.length - b.path.length || b.share - a.share);
}

/* ── breadth ──────────────────────────────────────────────────────────── */

/** How much of what the opponent would play, at one choice of theirs, you meet. */
export interface Coverage {
  /** Moves from the start to the position the opponent chooses in. */
  path: string[];
  /** The share of the book's replies there that you answer, 0..1. */
  covered: number;
  /**
   * How much of a choice the position really is, 0..1: what is left once the
   * one most played reply is taken out. A recapture nobody declines is not a
   * place a repertoire can be broad or narrow, and answering it says nothing
   * either way.
   */
  choice: number;
}

/** How much an opening's coverage at one depth counts: the first choices most. */
function earliness(depth: number): number {
  return 1 / (1 + depth / 3);
}

/** How much one of the opponent's choices counts toward how bare an opening is. */
function coverageWeight(at: Coverage): number {
  return earliness(at.path.length) * Math.max(at.choice, 0.05);
}

/**
 * What you answer at each of the opponent's choices your prep passes through.
 *
 * Only the junctions: a position where you answer nothing at all is the tip of
 * a line, and a line that has not been extended yet is not the same failing as
 * a reply you have chosen never to meet. Counting tips would read a repertoire
 * of twelve short lines as barer than one of a single long one, which is the
 * wrong way round for every purpose this number has.
 */
export function findCoverage(
  rep: Repertoire,
  index: ReferenceIndex,
  opts: GrowthOptions = {},
): Coverage[] {
  const out: Coverage[] = [];
  walkChoices(rep, index, opts, (choice) => {
    if (choice.prepared.size === 0) return;
    const all = choice.replies.reduce((sum, move) => sum + move.share, 0);
    if (all <= 0) return;
    const met = choice.replies
      .filter((move) => choice.prepared.has(move.san))
      .reduce((sum, move) => sum + move.share, 0);
    const top = Math.max(...choice.replies.map((move) => move.share));
    out.push({ path: choice.path, covered: met / all, choice: 1 - top / all });
  });
  return out;
}

/**
 * How bare an opening still is, 0..1.
 *
 * Not how much prep is in it — a King's Indian eighteen plies deep down one
 * pawn storm is a great deal of prep and the narrowest repertoire there is,
 * and the player meeting it will not play the storm. What is measured is how
 * much of what the opponent would actually play you have an answer to, at
 * each position where they choose, weighted toward the early ones — a reply
 * unanswered at move three is met in every game, one unanswered at move
 * twelve in almost none — and toward the ones that are a choice at all,
 * because a forced recapture is not an opening met, however well it is
 * prepared.
 *
 * An opening with nothing in it at all is as thin as it gets, which is what
 * lets a new repertoire be given breadth from its first round rather than
 * after its first line is held.
 */
export function thinness(coverage: Coverage[]): number {
  let weighted = 0;
  let total = 0;
  for (const at of coverage) {
    const weight = coverageWeight(at);
    weighted += weight * (1 - at.covered);
    total += weight;
  }
  return total > 0 ? Math.max(0, Math.min(1, weighted / total)) : 1;
}

/**
 * How much more a hole is worth for what your own games say about it.
 *
 * A position you keep reaching with nothing prepared is a hole your games
 * have already found for you. Each game you played into it adds a whole
 * share's worth again, so a hole met three times asks four times as loudly
 * as one met never.
 */
export function evidenceFor(
  repairs: { kind: 'offprep' | 'unprepared'; fen: string; games: number }[],
): (hole: Hole) => number {
  const games = new Map<string, number>();
  for (const item of repairs) {
    if (item.kind !== 'unprepared') continue;
    const key = positionKey(item.fen);
    games.set(key, (games.get(key) ?? 0) + item.games);
  }
  if (!games.size) return () => 1;
  return (hole) => 1 + (games.get(positionKey(hole.after)) ?? 0);
}

/** Book replies at a position that are played often enough to prepare for. */
export function popularReplies(
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
export function family(index: ReferenceIndex, sans: string[]): NamedLine | null {
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

/**
 * The openings a selection puts on the lobby, by name.
 *
 * The region test the holes go through is positional and deliberately
 * generous: a line counts while the book can still transpose it into the
 * region, which is what makes an unanswered reply on the way into the Najdorf
 * count as Najdorf work. Asking it which openings to *offer* gets a different
 * answer, because 1.e4 d6 2.d4 Nf6 3.c4 g6 really is a King's Indian, so an
 * unanswered 1.e4 survives the test — and an unanswered first move outscores
 * everything else there is, so it wins the top of the list every time. Select
 * the King's Indian and the lobby leads with the King's Pawn Game.
 *
 * A row already carries the sharper test: it is named for the opening its
 * holes lead into. That name being the selection, something inside it, or
 * something on the way down to it is what makes the row the selected
 * opening's work rather than a branch that merely could have joined it.
 */
function openingsInSelection(tree: OpeningTree, node: OpeningNode): Set<string> {
  return new Set([
    ...ancestorsOf(tree, node.id).map((opening) => opening.name),
    ...descendantsOf(node).map((opening) => opening.name),
  ]);
}

export function growthRows(
  reps: Repertoire[],
  index: ReferenceIndex,
  opts: GrowthOptions = {},
): GrowthRow[] {
  const starred = (opts.starred ?? []).map((id) => id.split(/\s+/).filter(Boolean));
  const region = opts.region;
  // The root is every opening there is, so it scopes nothing.
  const offered =
    region && region.node.depth > 0 ? openingsInSelection(region.tree, region.node) : null;
  const rows: GrowthRow[] = [];

  for (const rep of reps) {
    const byName = new Map<string, GrowthRow>();
    // A reply the book knows nothing past is a hole in the prep, but not work
    // for Growth: a run sent there would arrive with nothing to choose. The
    // Repertoire screen is where those are filled, by hand.
    for (const hole of findHoles(rep, index, opts).filter((found) => answerable(index, found.after))) {
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
    rows.push(...[...byName.values()].filter((row) => !offered || offered.has(row.name)));
  }

  for (const row of rows) {
    row.urgency = rowUrgency(row.depth, row.topShare, row.holes.length);
    row.score = Math.min(1, row.urgency * (row.starred ? STAR_BOOST : 1));
  }

  // One ordering for the list and for the button, so Start never begins
  // something other than the row sitting at the top of the list.
  return rows.sort((a, b) => b.score - a.score || a.depth - b.depth || a.name.localeCompare(b.name));
}

/** The row the Start button would begin, or nothing when there is no work. */
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

/**
 * The hole in a row a run should start standing at: the one you would meet
 * most often, shallower first on a tie. Null when the book has nothing to
 * offer at any of them.
 */
export function firstHole(index: ReferenceIndex, row: GrowthRow): Hole | null {
  const open = row.holes.filter((hole) => answerable(index, hole.after));
  if (!open.length) return null;
  return open.reduce((best, hole) =>
    holeWorth(hole) > holeWorth(best) || (holeWorth(hole) === holeWorth(best) && hole.path.length < best.path.length)
      ? hole
      : best,
  );
}

/**
 * A run that begins standing at a hole rather than walking to one: the
 * position a Run ended on, handed over by the reveal's offer to grow it, or
 * the hole a row most wants answered. Walking your prep from move one to get
 * there made most of a run replaying moves you already know, and a walk that
 * lost its way arrived with nothing to add.
 */
export function startGrowthAt(rep: Repertoire, row: GrowthRow, hole: Hole): GrowthRun {
  const there = { ...startGrowth(rep, row), path: hole.path, fen: hole.fen, nodeId: hole.nodeId };
  return enterHole(there, hole);
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
 * How much reaching one hole is worth: how often the player would actually be
 * sitting in front of it.
 *
 * `reach` already compounds the opponent's shares on the way in, so a hole
 * behind a sideline is discounted for the sideline without anything here
 * saying so. Never quite zero, so that two holes the book has no numbers for
 * are still separated by how far away they are.
 */
function holeWorth(hole: Hole): number {
  return Math.max(hole.reach * hole.share, RARE);
}

/**
 * What a ply of walking costs, against the worth of what is at the end of it.
 *
 * A run adds three moves at most, so arriving somewhere is not free: a hole
 * eight plies down can cost the whole run to reach, and the player answers one
 * move instead of three. The decay is what stops the steering marching past
 * everything answerable toward one distant main line, while still preferring a
 * mainline hole three plies on to a sideline one right here.
 */
const STEER_DECAY = 0.85;

/**
 * The opponent's reply, chosen to reach the hole most worth having.
 *
 * A hole right here is taken at once; otherwise the run continues down the
 * prepared reply with the best hole under it — how often the player would
 * meet it, discounted by how far the walk has to go. Nearest-first was the
 * older rule, and inside a starred opening it steered by accident: a rare
 * sideline with a hole one ply down beat the main line with one three plies
 * down, so a run in the opening the player had chosen to learn walked into
 * its obscure corners. Starring says which openings are theirs; this says
 * which part of one a round should spend itself on.
 *
 * Steering makes the opponent slightly artificial and that is the trade:
 * without it the walk wanders, and the mode's whole point is to reach an
 * unanswered move worth answering, quickly.
 */
export function steer(
  rep: Repertoire,
  index: ReferenceIndex,
  run: GrowthRun,
  opts: GrowthOptions = {},
): { san: string; hole: Hole | null } | null {
  const holes = findHoles(rep, index, opts).filter((hole) =>
    run.targets.has(positionKey(hole.fen)),
  );
  const hereKey = positionKey(run.fen);
  const here = holes.filter((hole) => positionKey(hole.fen) === hereKey);
  // The reply they play most often among the ones with no answer. That is the
  // order findHoles already returns them in; taking the best explicitly means
  // the steering does not quietly depend on that.
  if (here.length) {
    // A hole the book cannot answer is still a hole in the prep — coverage
    // counts it, and the Repertoire screen can fill it by hand — but a run
    // arriving at it has nothing to offer, so it is taken last.
    const open = here.filter((hole) => answerable(index, hole.after));
    const best = (open.length ? open : here).reduce((a, b) => (holeWorth(b) > holeWorth(a) ? b : a));
    return { san: best.san, hole: best };
  }

  const kids = childrenOf(rep, run.nodeId);
  if (!kids.length) return null;
  const worth = worthByPosition(holes);
  let best: { kid: RepMove; value: number } | null = null;
  for (const kid of kids) {
    const value = bestBelow(rep, kid.id, worth, 0);
    if (value === null) continue;
    if (!best || value > best.value) best = { kid, value };
  }
  const chosen = best?.kid ?? kids[0];
  return { san: chosen.san, hole: null };
}

/** The best any one hole is worth, at each position the run is aiming at. */
function worthByPosition(holes: Hole[]): Map<string, number> {
  const out = new Map<string, number>();
  for (const hole of holes) {
    const key = positionKey(hole.fen);
    out.set(key, Math.max(out.get(key) ?? 0, holeWorth(hole)));
  }
  return out;
}

/**
 * The best a target under this node is worth from where the run stands, every
 * ply of walking discounted — see STEER_DECAY. Null when there is none.
 */
function bestBelow(
  rep: Repertoire,
  nodeId: string,
  worth: Map<string, number>,
  depth: number,
): number | null {
  if (depth > DEFAULT_MAX_PLY) return null;
  const node = rep.nodes[nodeId];
  if (!node) return null;
  const mine = worth.get(positionKey(node.fenAfter));
  let best: number | null = mine === undefined ? null : mine * STEER_DECAY ** depth;
  for (const kid of childrenOf(rep, nodeId)) {
    const found = bestBelow(rep, kid.id, worth, depth + 1);
    if (found !== null && (best === null || found > best)) best = found;
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

/** Whether the book has anything to offer in a position. */
function answerable(index: ReferenceIndex, fen: string): boolean {
  return popularReplies(index, fen, 0).length > 0;
}

/**
 * What they would play against the answer you just added, as the next hole.
 *
 * The book's most popular reply, since nothing steers any more: past the
 * repertoire there is no target left to walk toward, and the commonest move is
 * the one most worth having an answer to.
 *
 * A reply the book cannot answer is skipped rather than offered. The book ends
 * where a position stops being played often enough to record, and a hole past
 * that edge is a dead end: the run would arrive with nothing to choose. At the
 * edge itself that is every reply, and there is no next hole at all.
 */
export function nextHole(index: ReferenceIndex, run: GrowthRun): Hole | null {
  for (const reply of popularReplies(index, run.fen, 0)) {
    const after = applySan(run.fen, reply.san);
    if (!after || !answerable(index, after.after)) continue;
    return {
      path: run.path,
      fen: run.fen,
      san: reply.san,
      share: reply.share,
      games: reply.games,
      after: after.after,
      nodeId: null,
      // Past the repertoire there is no walk left to have counted the way here.
      reach: 0,
    };
  }
  return null;
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

/**
 * The run another batch of answers would carry on from, or null when there is
 * nothing left to answer.
 *
 * Either it is already standing at a hole — a batch stopped by hand, at the
 * reveal — or their commonest reply to the last answer becomes the next one.
 * Either way the book has to have something to offer there, since a hole it
 * knows no replies to is a dead end rather than a choice.
 */
export function resumeAdding(
  rep: Repertoire,
  index: ReferenceIndex,
  run: GrowthRun,
): GrowthRun | null {
  if (atHole(rep, run)) return optionsAt(index, run.fen, 1).length ? run : null;
  const hole = nextHole(index, run);
  if (!hole) return null;
  return optionsAt(index, hole.after, 1).length ? enterHole(run, hole) : null;
}
