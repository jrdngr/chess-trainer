/**
 * Time and chance: the two inputs, besides the engine and the book, that a
 * replay has to fix. Everything in the app reads them from here, never from
 * `Date.now` or `Math.random` directly, so a test (or the native port's
 * scenario runner) can pin both in one place.
 */
export const env = {
  /** Milliseconds since the epoch. */
  now: (): number => Date.now(),
  /** A number in [0, 1). */
  random: (): number => Math.random(),
};

/** Replace either input, for a test or a scripted replay. */
export function setEnv(over: Partial<typeof env>): void {
  Object.assign(env, over);
}
