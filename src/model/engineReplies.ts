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

/** How many moves the engine offers past the book, for either side. */
export const ENGINE_REPLIES = 3;

const known = new Map<string, string[]>();
const listeners = new Set<() => void>();

/** The engine's moves here, best first; undefined when it has not been asked yet. */
export function engineReplies(fen: string): string[] | undefined {
  return known.get(positionKey(fen));
}

/** Record the engine's moves for a position. An empty list means there are none. */
export function rememberEngineReplies(fen: string, sans: string[]): void {
  known.set(positionKey(fen), sans.slice(0, ENGINE_REPLIES));
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
}
