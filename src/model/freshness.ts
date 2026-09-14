import { applySan, positionKey, START_FEN } from '../chess/core';
import { childrenOf, pathTo } from './repertoire';
import type { RepMove, Repertoire } from './types';

/**
 * Freshness: what the last few rounds were about, so the next one is not.
 *
 * Every round stamps the positions of the line it was drawn on with its
 * number. A line is then read in two parts — its tail, the moves past the
 * last place it parts from another line, which are what make it *this* line;
 * and its head, everything before, which is what makes it this opening. The
 * same line twice running has a fresh tail. A different variation of the
 * same opening has a fresh head and a stale tail. Those are different
 * repetitions and they cost different amounts.
 *
 * Read by the scorer, so a Test only asks loudly for an opening that has a
 * line worth running; and by the draw, so the line it picks is the one that
 * has been left longest. Nothing here schedules anything: a repertoire of one
 * line runs it, finds it fresh, and grows; a repertoire of forty cycles a
 * rotating few. The rhythm is a consequence of remembering.
 */

/** Rounds until a position seen counts as not seen. */
export const HORIZON = 3;

/** How much of a line's freshness its head carries, against its tail. */
export const HEAD_WEIGHT = 0.5;

/** What the rounds so far have been about: position key → the round that last saw it. */
export interface Seen {
  at: Record<string, number>;
  /** The number of the last round played, so "rounds since" has a now. */
  round: number;
}

export const NOTHING_SEEN: Seen = { at: {}, round: 0 };

/** How long ago a position was last seen, 0 (this round) to 1 (the horizon or never). */
export function staleness(seen: Seen, key: string): number {
  const last = seen.at[key];
  if (last === undefined) return 1;
  return Math.max(0, Math.min(1, (seen.round - last) / HORIZON));
}

/**
 * The positions a line reaches, one per move. Not the start: every line
 * begins there, and a position on every line says nothing about any of them.
 */
export function keysAlong(sans: string[]): string[] {
  const keys: string[] = [];
  let fen = START_FEN;
  for (const san of sans) {
    const move = applySan(fen, san);
    if (!move) break;
    fen = move.after;
    keys.push(positionKey(fen));
  }
  return keys;
}

/** Stamp every position along a line with the round that saw it. */
export function markSeen(at: Record<string, number>, sans: string[], round: number): Record<string, number> {
  const out = { ...at };
  for (const key of keysAlong(sans)) out[key] = round;
  return out;
}

/**
 * A line's positions, split where it last parts from the rest of the prep.
 *
 * The tail begins at the deepest move that has a sibling: from there on the
 * line is on its own. A repertoire of one line has no such move, and the
 * whole line is tail — there is nothing for it to be a variation of.
 */
export function lineParts(rep: Repertoire, tipId: string): { head: string[]; tail: string[] } {
  const path = pathTo(rep, tipId);
  let split = 0;
  path.forEach((node, i) => {
    if (childrenOf(rep, node.parentId).length > 1) split = i;
  });
  const key = (n: RepMove) => positionKey(n.fenAfter);
  return { head: path.slice(0, split).map(key), tail: path.slice(split).map(key) };
}

function mean(values: number[]): number {
  return values.length ? values.reduce((sum, v) => sum + v, 0) / values.length : 1;
}

/**
 * How long a line has been left, 0..1.
 *
 * The tail decides most of it: a line run last round is fresh whatever
 * opening it is in. The head tempers it, so that among lines equally left,
 * one in an opening the last rounds were not in is preferred to a variation
 * of the one they were.
 */
export function lineStaleness(seen: Seen, rep: Repertoire, tipId: string): number {
  const { head, tail } = lineParts(rep, tipId);
  const tailStale = mean(tail.map((key) => staleness(seen, key)));
  const headStale = mean(head.map((key) => staleness(seen, key)));
  return tailStale * (1 - HEAD_WEIGHT + HEAD_WEIGHT * headStale);
}

/** True when the line's own moves were what the round being decided came after. */
export function justRun(seen: Seen, rep: Repertoire, tipId: string): boolean {
  const { tail } = lineParts(rep, tipId);
  return tail.length > 0 && tail.every((key) => seen.at[key] === seen.round);
}
