import { fenTurn, positionKey, walkSan } from '../chess/core';
import { growthRows, optionsAt, recommended, type GrowthOptions, type GrowthRow, type Hole } from './growth';
import {
  ancestorsOf,
  deepestNodeWithin,
  lineStatus,
  type OpeningNode,
  type OpeningTree,
} from './openingTree';
import type { Run } from './openingRun';
import { familyName, type ReferenceIndex } from './reference';
import { childrenOf, leafLines, pathTo } from './repertoire';
import type { RoundRecord } from './scoring';
import type { RepMove, Repertoire } from './types';

/**
 * The offer to grow: when a Run or Autopilot round finishes clean at the end
 * of your prep, and the opening has nothing more a round could teach you, the
 * end-of-round screen offers Growth from where the round stopped.
 *
 * Two things make an opening worth growing rather than drilling again:
 *
 *   stub  — the round asked you nothing. An opening saved as its own move
 *           order and no further, started inside its position, is one
 *           opponent move and the end of the prep. Such a round is not
 *           counted: nothing was found, so nothing is logged.
 *   ready — every line in the opening has been finished clean enough times
 *           since it last changed. Adding a move to a line resets its count,
 *           so the new move is drilled before growing is suggested again.
 *
 * The offer is only ever an offer. Next run is "not now", and it comes back
 * whenever the opening qualifies.
 */

/** Clean finishes every line needs, since it last changed, before the opening is ready to grow. */
export const CLEAN_FINISHES = 3;

/**
 * A round that finished clean at the end of your prep without asking you a
 * single move: every move of yours was played for you on the way in.
 */
export function isStubFinish(run: Run): boolean {
  return run.prepDone !== null && !run.leftPrep && !run.bookRun && !run.extended && run.survived === 0;
}

/**
 * The opening an offer is about: the one the round was started inside, or the
 * selection it was drawn in, since that is what the player chose. A round
 * from move one with nothing selected offers the family it ended in — a
 * King's Indian round that ended in the Sämisch offers to grow the King's
 * Indian, not the variation it wandered into.
 */
export function offerOpening(
  tree: OpeningTree,
  region: OpeningNode,
  entered: OpeningNode | null,
  played: string[],
): OpeningNode {
  const within = entered ?? region;
  if (within.depth > 0) return within;
  const deepest = deepestNodeWithin(tree, within, played);
  const family = familyName(tree.index, deepest.name);
  return ancestorsOf(tree, deepest.id).find((node) => familyName(tree.index, node.name) === family) ?? deepest;
}

export interface LineFinishes {
  tipId: string;
  sans: string[];
  /** Clean finishes of this line since its newest move was added. */
  finishes: number;
}

function startsWith(line: string[], prefix: string[]): boolean {
  return prefix.length <= line.length && prefix.every((san, i) => line[i] === san);
}

/**
 * Every line of yours inside an opening, with how often it has been finished
 * clean since it last changed.
 *
 * A clean finish is a Run round, Autopilot's included, that reached the end
 * of the prep without a miss and without leaving it: `perfect` on the round.
 * The round's line is the one it was drawn on, which at a clean finish is the
 * line it played to its end. Only rounds after the line's newest move count,
 * so a line grown by a move starts again from nothing.
 */
export function lineFinishes(
  rep: Repertoire,
  tree: OpeningTree,
  opening: OpeningNode,
  rounds: RoundRecord[],
): LineFinishes[] {
  const clean = rounds.filter(
    (round) => round.mode === 'run' && round.color === rep.color && round.perfect && !!round.line?.length,
  );
  return leafLines(rep)
    .filter((line) => lineStatus(tree, opening, line.sans) === 'reached')
    .map((line) => {
      const since = Math.max(0, ...pathTo(rep, line.tipId).map((move) => move.addedAt));
      const finishes = clean.filter((round) => round.at > since && startsWith(round.line!, line.sans)).length;
      return { tipId: line.tipId, sans: line.sans, finishes };
    });
}

/** Every line in the opening finished clean `CLEAN_FINISHES` times since it last changed. */
export function readyToGrow(
  rep: Repertoire,
  tree: OpeningTree,
  opening: OpeningNode,
  rounds: RoundRecord[],
): boolean {
  const lines = lineFinishes(rep, tree, opening, rounds);
  return lines.length > 0 && lines.every((line) => line.finishes >= CLEAN_FINISHES);
}

/**
 * How much practice an opening is owed: its lines, and how many of them are
 * short of `CLEAN_FINISHES` since they last changed.
 *
 * Growth reads this to point back at Autopilot or Run, and the end of a
 * round reads it to stop offering Growth, so the two never send you to each
 * other at once. It is the same count that decides `readyToGrow`, read the
 * other way: ready is nothing owed, and the cap is owing too much.
 */
export interface PracticeOwed {
  /** Every line of yours inside the opening. */
  lines: number;
  /** Lines not yet finished clean `CLEAN_FINISHES` times since they last changed. */
  owed: number;
  /** How many owed lines send you back to practice them. */
  cap: number;
}

/**
 * How many unpracticed lines an opening may carry before Growth points back.
 *
 * Three while it is small: a stub grown by one line at a time would take a
 * week to become a repertoire. Fewer as it fills in, because every line a
 * round could be drawn on makes any one new line slower to come round, and
 * each needs three clean finishes before it counts as learned.
 */
export function practiceCap(lines: number): number {
  if (lines < 6) return 3;
  if (lines < 12) return 2;
  return 1;
}

export function practiceOwed(
  rep: Repertoire,
  tree: OpeningTree,
  opening: OpeningNode,
  rounds: RoundRecord[],
): PracticeOwed {
  const lines = lineFinishes(rep, tree, opening, rounds);
  const owed = lines.filter((line) => line.finishes < CLEAN_FINISHES).length;
  return { lines: lines.length, owed, cap: practiceCap(lines.length) };
}

/** The opening owes as much practice as it may: time to stop growing it. */
export function atPracticeCap(practice: PracticeOwed): boolean {
  return practice.owed > 0 && practice.owed >= practice.cap;
}

/** What Growth's card says an opening is owed. */
export function practiceText(name: string, owed: number): string {
  return owed > 0 ? `${owed} ${name} line${owed === 1 ? '' : 's'} to practice.` : `${name} line grown.`;
}

/** The repertoire node a line of moves reaches, or null at the root or off the tree. */
function nodeAt(rep: Repertoire, sans: string[], fen: string): string | null {
  let nodeId: string | null = null;
  for (const san of sans) {
    const kid: RepMove | undefined = childrenOf(rep, nodeId).find((child) => child.san === san);
    if (!kid) {
      // Reached by another move order: the same position is the same node.
      const key = positionKey(fen);
      return Object.values(rep.nodes).find((node) => positionKey(node.fenAfter) === key)?.id ?? null;
    }
    nodeId = kid.id;
  }
  return nodeId;
}

/**
 * The hole a round ended on: the opponent's last move, with you to answer it
 * and nothing prepared. Null when there is nothing to grow from right here —
 * it is not your move, the line is already as deep as Growth goes, or the
 * book has nothing to offer.
 */
export function holeAtEnd(
  rep: Repertoire,
  index: ReferenceIndex,
  played: string[],
  maxPly: number,
): Hole | null {
  if (played.length === 0 || played.length >= maxPly) return null;
  const walked = walkSan(played);
  if (walked.moves.length !== played.length) return null;
  const fen = walked.fens[played.length];
  const before = walked.fens[played.length - 1];
  if (fenTurn(fen) !== rep.color) return null;
  if (optionsAt(index, fen, 1).length === 0) return null;
  // Something prepared here, by any move order, is not a hole.
  const key = positionKey(fen);
  if (Object.values(rep.nodes).some((node) => node.key === key)) return null;
  const path = played.slice(0, -1);
  const nodeId = nodeAt(rep, path, before);
  const san = played[played.length - 1];
  const book = optionsAt(index, before, 99).find((move) => move.san === san);
  return {
    path,
    fen: before,
    san,
    share: book?.share ?? 0,
    games: book?.games ?? 0,
    after: fen,
    nodeId,
    reach: 0,
  };
}

/** Where a Growth run offered at the end of a round begins. */
export interface GrowLaunch {
  opening: OpeningNode;
  row: GrowthRow;
  /** The hole the round ended on, when growing starts right there. */
  hole: Hole | null;
}

/**
 * Where growing an opening starts: the position the round ended on, when
 * there is room to grow there, and otherwise the opening's most urgent gap.
 * Null when the opening has nothing left to grow within Growth's settings.
 */
export function growLaunch(
  rep: Repertoire,
  index: ReferenceIndex,
  tree: OpeningTree,
  opening: OpeningNode,
  played: string[],
  opts: Pick<GrowthOptions, 'minShare' | 'maxPly' | 'starred'>,
): GrowLaunch | null {
  const maxPly = opts.maxPly ?? 18;
  const hole = holeAtEnd(rep, index, played, maxPly);
  if (hole) {
    const row: GrowthRow = {
      id: `${rep.id}#${opening.name}`,
      repertoireId: rep.id,
      color: rep.color,
      name: opening.name,
      depth: hole.path.length,
      topShare: hole.share,
      starred: false,
      urgency: 0,
      score: 0,
      holes: [hole],
    };
    return { opening, row, hole };
  }
  const row = recommended(growthRows([rep], index, { ...opts, region: { tree, node: opening } }));
  return row ? { opening, row, hole: null } : null;
}

/** A ply as it is written: 2.c4, or 2...e6 for Black. */
export function plyLabel(ply: number, san: string): string {
  const number = Math.floor(ply / 2) + 1;
  return ply % 2 === 0 ? `${number}.${san}` : `${number}...${san}`;
}

/** Your last move in a line, as it is written, or null when you had none. */
export function yourLastMove(played: string[], color: 'w' | 'b'): string | null {
  for (let ply = played.length - 1; ply >= 0; ply -= 1) {
    if ((ply % 2 === 0) === (color === 'w')) return plyLabel(ply, played[ply]);
  }
  return null;
}
