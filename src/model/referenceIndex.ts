import { buildReferenceIndex, type ReferenceIndex } from './reference';
import { REFERENCE_GAMES } from './seed/games';
import { OPENING_NAMES, OPENING_PATHS } from './seed/openingPaths';

let cached: ReferenceIndex | null = null;

/** Built on first use — walking the tree costs a few hundred milliseconds. */
export function referenceIndex(): ReferenceIndex {
  if (!cached) {
    cached = buildReferenceIndex({
      paths: OPENING_PATHS,
      openingNames: OPENING_NAMES,
      games: REFERENCE_GAMES,
      // A round number for a curated sample; the explorer shows relative
      // popularity, and this is what those percentages are scaled against.
      totalGames: 4_200_000,
    });
  }
  return cached;
}
