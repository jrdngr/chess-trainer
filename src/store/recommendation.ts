import { buildRepairs } from '../model/repair';
import { openingTree } from '../model/openingTree';
import { recommend, type RecommendInput, type Recommendation } from '../model/recommend';
import { referenceIndex } from '../model/referenceIndex';
import { lineInRegion, regionOf, repertoiresIn } from '../model/selection';
import { repertoireList, useStore } from './useStore';

type State = ReturnType<typeof useStore.getState>;

/** Everything the engine needs, read off the store. */
export function recommendInput(state: State): RecommendInput {
  const tree = openingTree(referenceIndex());
  const selection = state.settings.selection;
  const region = regionOf(tree, selection);
  const reps = repertoiresIn(repertoireList(state), selection.color);
  const repairs = buildRepairs(state.importedGames, reps, {
    kinds: state.settings.repair.kinds,
    minGames: state.settings.repair.minGames,
    lossesOnly: state.settings.repair.lossesOnly,
    mistakes: state.mistakes,
  }).filter((item) => lineInRegion(tree, region, item.path));
  return {
    tree,
    selection,
    reps,
    cards: state.cards,
    repairs,
    score: state.score,
    starred: state.settings.favoriteOpenings,
    newPerSession: state.settings.drill.newPerSession,
    growth: state.settings.growth,
    recentModes: state.score.games.map((game) => game.mode),
  };
}

/** What Autopilot would start now. */
export function recommendNow(state: State): Recommendation {
  return recommend(recommendInput(state));
}
