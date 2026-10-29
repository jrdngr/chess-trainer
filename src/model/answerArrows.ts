import { applySan, type Square } from '../chess/core';
import { byDelta } from './evalDelta';

/**
 * Growth's arrows at a hole: who recommends each one.
 *
 * Blue is the reply strong players choose most. The other two are the
 * engine's best, purple and then a lighter purple. When strong players and the
 * engine agree, the move stays blue and the engine's next move takes its
 * place, so there are three different moves whenever there are three to show.
 * Past the book nobody has a share, and all three are the engine's.
 */

export type AnswerRole = 'strong' | 'engine' | 'engine-next';

export interface RoleArrow {
  san: string;
  from: Square;
  to: Square;
  role: AnswerRole;
}

/** How many arrows the roles fill, at most. */
export const ROLE_ARROWS = 3;

/**
 * `listed` is every answer on offer, `deltaOf` what the engine makes of each
 * so far (null until it has weighed it). Before the engine has weighed any,
 * only the blue arrow is drawn; past the book, where `listed` already comes in
 * the engine's order, that order stands in until it has.
 */
export function roleArrows(
  fen: string,
  listed: readonly { san: string; share?: number }[],
  deltaOf: (san: string) => number | null,
): RoleArrow[] {
  const strong = listed.reduce<{ san: string; share?: number } | null>(
    (best, move) => ((move.share ?? 0) > (best?.share ?? 0) ? move : best),
    null,
  );
  const weighed = listed.filter((move) => deltaOf(move.san) !== null);
  const engine = (weighed.length ? byDelta(weighed, deltaOf) : strong ? [] : listed)
    .filter((move) => move.san !== strong?.san)
    .slice(0, ROLE_ARROWS - (strong ? 1 : 0));

  const out: RoleArrow[] = [];
  const add = (san: string, role: AnswerRole) => {
    const move = applySan(fen, san);
    if (move) out.push({ san, from: move.from, to: move.to, role });
  };
  if (strong) add(strong.san, 'strong');
  engine.forEach((move, i) => add(move.san, i === 0 ? 'engine' : 'engine-next'));
  return out;
}
