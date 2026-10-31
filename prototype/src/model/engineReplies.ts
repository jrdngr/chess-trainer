import { positionKey } from '../chess/core';

/**
 * What the engine would play in positions the book knows nothing about.
 *
 * The book ends where a position stops being played often enough to record,
 * and Growth used to end there with it. Past that edge the engine stands in
 * for both sides: its top moves are the answers you choose from, and the
 * replies the opponent is prepared for. It has no idea how often anyone plays
 * them, only that they are good, so they carry no share.
 *
 * The engine is asynchronous and the model is not, so the model reads what
 * has been worked out so far from here and the screens ask for the rest —
 * see `src/engine/engineReplies.ts`. Kept for the page's lifetime.
 */

/** How many moves the engine is asked for past the book. */
export const ENGINE_REPLIES = 4;
/** How many of them the opponent is prepared for: their replies past the book. */
export const ENGINE_THEIR_REPLIES = 2;
/**
 * How close to the engine's best a move of yours must be to be offered past
 * the book, in centipawns: a line grown there should be one a strong player
 * would play, not merely one that survives.
 */
export const NEAR_BEST = 20;

const known = new Map<string, string[]>();
/** What each of those moves gives away against the best, by position and move. */
const losses = new Map<string, Map<string, number>>();
const listeners = new Set<() => void>();

/** The engine's moves here, best first; undefined when it has not been asked yet. */
export function engineReplies(fen: string): string[] | undefined {
  return known.get(positionKey(fen));
}

/** What a remembered move gives away against the engine's best; undefined when unknown. */
export function engineLoss(fen: string, san: string): number | undefined {
  return losses.get(positionKey(fen))?.get(san);
}

/**
 * Record the engine's moves for a position, best first, with what each gives
 * away against the best when the search said. An empty list means there are
 * none.
 */
export function rememberEngineReplies(fen: string, sans: string[], lost?: number[]): void {
  const kept = sans.slice(0, ENGINE_REPLIES);
  known.set(positionKey(fen), kept);
  if (lost) losses.set(positionKey(fen), new Map(kept.map((san, i) => [san, lost[i] ?? 0])));
  for (const listen of listeners) listen();
}

/** Called whenever a new position is worked out. Returns the unsubscribe. */
export function onEngineReplies(listen: () => void): () => void {
  listeners.add(listen);
  return () => {
    listeners.delete(listen);
  };
}

/** Forget everything — for tests. */
export function clearEngineReplies(): void {
  known.clear();
  losses.clear();
}
