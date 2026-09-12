import { describe, expect, it } from 'vitest';
import { sansToMoveText } from '../../chess/core';
import { findGaps } from '../gaps';
import { lookup, totalGamesAt } from '../reference';
import { referenceIndex } from '../referenceIndex';
import { childrenOf } from '../repertoire';
import { buildSeedRepertoires } from '../../store/seed';

/**
 * "All variations" is a claim, so it gets checked rather than asserted.
 *
 * The check runs on the same `findGaps` the Gap mode uses, so the guarantee and
 * the feature cannot drift apart: if the mode ever reports a gap in the seeded
 * repertoires, this fails first.
 *
 * The opening position is checked per colour rather than per repertoire: a
 * Black repertoire is allowed to answer only 1.d4 as long as a sibling
 * repertoire answers 1.e4.
 */
const MIN_SHARE = 3;

describe('repertoire coverage', () => {
  const reps = buildSeedRepertoires();
  const index = referenceIndex();

  for (const rep of reps) {
    it(`${rep.name} answers every reply played in at least ${MIN_SHARE}% of games`, () => {
      const gaps = findGaps(rep, index, { minShare: MIN_SHARE }).map(
        (g) =>
          `after ${sansToMoveText(g.path)}: no answer to ${g.san} (${g.share}% of games, have ${g.have.join('/')})`,
      );
      expect(gaps).toEqual([]);
    });
  }

  it('meets every mainstream first move across the Black repertoires', () => {
    const start = lookup(index, reps[0].rootFen)!;
    const total = totalGamesAt(start);
    const answered = new Set(
      reps.filter((r) => r.color === 'b').flatMap((r) => childrenOf(r, null).map((m) => m.san)),
    );
    const missing = start.moves
      .filter((m) => (m.games / total) * 100 >= MIN_SHARE && !answered.has(m.san))
      .map((m) => `${m.san} (${Math.round((m.games / total) * 100)}%)`);
    expect(missing).toEqual([]);
  });
});
