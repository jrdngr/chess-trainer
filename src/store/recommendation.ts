import { buildRepairs, type RepairItem } from '../model/repair';
import { openingTree } from '../model/openingTree';
import { recommend, type Focus, type RecommendInput, type Recommendation } from '../model/recommend';
import { referenceIndex } from '../model/referenceIndex';
import { seenIn } from '../model/scoring';
import { lineInRegion, regionOf, repertoiresIn } from '../model/selection';
import { repertoireList, useStore } from './useStore';

type State = ReturnType<typeof useStore.getState>;

/**
 * What your games say about the selection: the positions you got wrong with
 * a move prepared, and the ones you kept reaching with nothing.
 */
export function evidenceIn(state: State): RepairItem[] {
  const tree = openingTree(referenceIndex());
  const selection = state.settings.selection;
  const region = regionOf(tree, selection);
  const reps = repertoiresIn(repertoireList(state), selection.color);
  return buildRepairs(state.importedGames, reps, {
    kinds: state.settings.repair.kinds,
    minGames: state.settings.repair.minGames,
    lossesOnly: state.settings.repair.lossesOnly,
    mistakes: state.mistakes,
  }).filter((item) => lineInRegion(tree, region, item.path));
}

/** Everything the engine needs, read off the store. */
export function recommendInput(
  state: State,
  recentFocuses: Focus[] = [],
  recentSteered: boolean[] = [],
): RecommendInput {
  const tree = openingTree(referenceIndex());
  const selection = state.settings.selection;
  return {
    tree,
    selection,
    reps: repertoiresIn(repertoireList(state), selection.color),
    cards: state.cards,
    repairs: evidenceIn(state),
    score: state.score,
    starred: state.settings.favoriteOpenings,
    newPerSession: state.settings.drill.newPerSession,
    recentFocuses,
    recentSteered,
    seen: seenIn(state.score),
  };
}

/**
 * What Autopilot would start now, or null with nothing prepared inside the
 * selection to drill. The focuses of the session's rounds so far are the
 * brake, and which of them were steered into an opening spaces the next;
 * they are the session's memory and nothing is saved.
 */
export function recommendNow(
  state: State,
  recentFocuses: Focus[] = [],
  recentSteered: boolean[] = [],
): Recommendation | null {
  return recommend(recommendInput(state, recentFocuses, recentSteered));
}
