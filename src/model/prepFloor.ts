/**
 * How often a reply you prepared comes up, at the least.
 *
 * The book is games between strong players, and what they play is not what
 * a club player meets: 5.e5 against the King's Indian never reaches the book,
 * and is one of the commonest things a 1500 sees. A reply you put in your
 * repertoire is one you mean to be tested on, so it gets a real share of the
 * position whatever the book thinks of it, and the book splits the rest.
 */
export const PREPARED_FLOOR = 0.15;

/**
 * The most of one position the lifted moves may take between them.
 *
 * A Black repertoire with an answer to every first move White has would
 * otherwise hand 1.b3, 1.f4, 1.g3 and the rest 15% each and leave 1.e4 and
 * 1.d4 a sliver. Past this the floor shrinks, shared evenly among them.
 */
export const MAX_LIFTED = 0.5;

/**
 * Shares for the moves at one position, 0..1 and summing to 1, with every
 * floored move lifted to at least `floor` and the others scaled down to make
 * room. Lifting can push a floored move that started just above the line
 * below it, so it settles in a few passes.
 */
export function withFloor(weights: number[], floored: boolean[], floor = PREPARED_FLOOR): number[] {
  const n = weights.length;
  if (!n) return [];
  const total = weights.reduce((sum, w) => sum + Math.max(0, w), 0);
  const base = total > 0 ? weights.map((w) => Math.max(0, w) / total) : weights.map(() => 1 / n);
  let shares = base;
  const lifted = new Set<number>();
  for (let pass = 0; pass <= n; pass++) {
    const each = Math.min(floor, MAX_LIFTED / Math.max(1, lifted.size));
    let changed = false;
    for (let i = 0; i < n; i++) {
      if (floored[i] && !lifted.has(i) && shares[i] < each - 1e-12) {
        lifted.add(i);
        changed = true;
      }
    }
    if (!changed) break;
    const level = Math.min(floor, MAX_LIFTED / lifted.size);
    const rest = 1 - level * lifted.size;
    const free = base.reduce((sum, s, i) => (lifted.has(i) ? sum : sum + s), 0);
    const others = n - lifted.size;
    shares = base.map((s, i) =>
      lifted.has(i) ? level : free > 0 ? (s / free) * rest : others ? rest / others : 0,
    );
  }
  return shares;
}
