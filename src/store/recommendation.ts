import type { Color } from '../chess/core';
import { chooseMode, coldStart, type RoundMode } from '../model/autopilot';
import { ACCURACY_RUNS } from '../model/recommend';
import { growLaunch, lineFinishes, readyToGrow, type GrowLaunch } from '../model/growOffer';
import { drillableLines, dueLines } from '../model/lineDrill';
import { buildRepairs, type RepairItem } from '../model/repair';
import { openingTree } from '../model/openingTree';
import { isSteered, recommend, type Focus, type RecommendInput, type Recommendation, type Start } from '../model/recommend';
import { referenceIndex } from '../model/referenceIndex';
import { seenIn, type RoundRecord } from '../model/scoring';
import { itemsInRegion, lineInRegion, regionOf, repertoiresIn, type Selection } from '../model/selection';
import { isDue } from '../model/srs';
import { itemsFor, repertoireList, useStore } from './useStore';

type State = ReturnType<typeof useStore.getState>;

/**
 * The store as a session held to one selection sees it: the saved selection
 * swapped for that one, and nothing written back.
 */
export function withSelection(state: State, selection?: Selection): State {
  return selection ? { ...state, settings: { ...state.settings, selection } } : state;
}

/**
 * What your games say about the selection: the positions you got wrong with
 * a move prepared, and the ones you kept reaching with nothing.
 */
export function evidenceIn(state: State): RepairItem[] {
  const tree = openingTree(referenceIndex());
  const selection = state.settings.selection;
  const region = regionOf(tree, selection);
  const reps = repertoiresIn(repertoireList(state), selection.color);
  return buildRepairs(state.importedGames, reps, { mistakes: state.mistakes }).filter((item) => lineInRegion(tree, region, item.path));
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

/* ── Autopilot's rounds ─────────────────────────────────────────────────── */

/** What Autopilot's next round is, with what its mode needs to start. */
export type AutoRound =
  | { mode: 'survival'; pick: Recommendation }
  /** `weak`: nothing due or new, so the round asks the positions you answer worst. */
  | { mode: 'drillPositions'; color: Color; openingId: string; weak: boolean }
  | { mode: 'drillLines'; color: Color; openingId: string; only: string[] }
  | { mode: 'growth'; color: Color; launch: GrowLaunch };

/** What a session remembers of its rounds so far, oldest first. Nothing is saved. */
export interface AutoHistory {
  modes: RoundMode[];
  /** The focuses of its Survival rounds, for the recommendation's brake. */
  focuses: Focus[];
  /** For each of those, whether it was steered into an opening below the selection. */
  steered: boolean[];
  /** Where each of those started, for the Cold Start rule — see `coldStart`. */
  starts: Start[];
}

export const NO_HISTORY: AutoHistory = { modes: [], focuses: [], steered: [], starts: [] };

/**
 * Autopilot's next round, or null with nothing prepared inside the selection.
 *
 * The recommendation engine picks what a Survival run would be about; the
 * other modes are weighed against it by what they have to do inside the same
 * selection — see `autopilot.ts`.
 */
export function nextRound(state: State, history: AutoHistory): AutoRound | null {
  const recommended = recommendNow(state, history.focuses, history.steered);
  if (!recommended) return null;
  const pick = coldStart(recommended, history.starts);
  const tree = openingTree(referenceIndex());
  const index = referenceIndex();
  const selection = state.settings.selection;
  const region = regionOf(tree, selection);
  const reps = repertoiresIn(repertoireList(state), selection.color);
  const rounds = state.score.rounds;
  const now = Date.now();

  /** Per side: cards due and never drilled, and lines unpracticed and due. */
  const sides = reps.map((rep) => {
    const keys = new Set(itemsInRegion(tree, region, itemsFor(rep)).map((item) => item.cardId));
    const due = [...keys].filter((id) => state.cards[id] && isDue(state.cards[id], now)).length;
    const unseen = [...keys].filter((id) => !state.cards[id] || state.cards[id].stage === 'new').length;
    const lines = drillableLines(rep, tree, region);
    const unpracticed = lineFinishes(rep, tree, region, rounds)
      .filter((line) => line.finishes === 0)
      .map((line) => line.tipId);
    const linesDue = dueLines(lines, state.lineCards, now).map((line) => line.tipId);
    return { rep, positions: keys.size, due, unseen, lines: lines.length, unpracticed, linesDue };
  });
  const owed = (side: (typeof sides)[number]) => side.unpracticed.length + side.linesDue.length;
  const toDrill = (side: (typeof sides)[number]) => side.due + side.unseen;
  const byPositions = [...sides].sort((a, b) => toDrill(b) - toDrill(a) || b.positions - a.positions)[0];
  const byLines = [...sides].sort((a, b) => owed(b) - owed(a) || b.lines - a.lines)[0];
  const sum = (key: 'positions' | 'due' | 'unseen' | 'lines') => sides.reduce((n, side) => n + side[key], 0);

  /** An opening ready to widen: the one Survival would run, or the selection itself. */
  const growth = (() => {
    const openings = [pick.opening, ...(region.depth > 0 ? [region] : [])];
    for (const side of sides) {
      for (const opening of openings) {
        if (!readyToGrow(side.rep, tree, opening, rounds)) continue;
        const launch = growLaunch(side.rep, index, tree, opening, [], {
          minShare: state.settings.growth.minShare,
          maxPly: state.settings.growth.maxPly,
          starred: state.settings.favoriteOpenings,
        });
        if (launch) return { color: side.rep.color, launch };
      }
    }
    return null;
  })();

  const mode = chooseMode(
    {
      lines: sum('lines'),
      positions: sum('positions'),
      due: sum('due'),
      unseen: sum('unseen'),
      unpracticed: sides.reduce((n, side) => n + side.unpracticed.length, 0),
      dueLines: sides.reduce((n, side) => n + side.linesDue.length, 0),
      accuracy: prepAccuracy(rounds, reps.map((rep) => rep.color)),
      growReady: !!growth,
    },
    history.modes,
  );
  switch (mode) {
    case 'drillPositions':
      return { mode, color: byPositions.rep.color, openingId: region.id, weak: toDrill(byPositions) === 0 };
    case 'drillLines':
      return {
        mode,
        color: byLines.rep.color,
        openingId: region.id,
        only: [...new Set([...byLines.linesDue, ...byLines.unpracticed])],
      };
    case 'growth':
      return growth ? { mode, ...growth } : { mode: 'survival', pick };
    default:
      return { mode: 'survival', pick };
  }
}

/**
 * Your prep accuracy: prepared positions found over asked, across the last
 * `ACCURACY_RUNS` Survival runs on these sides that recorded it. Null with none.
 */
export function prepAccuracy(rounds: RoundRecord[], colors: Color[]): number | null {
  const runs = rounds.filter((round) => round.mode === 'survival' && round.prep && round.prep.asked > 0 && colors.includes(round.color));
  const recent = runs.slice(-ACCURACY_RUNS);
  const asked = recent.reduce((n, round) => n + round.prep!.asked, 0);
  return asked ? recent.reduce((n, round) => n + round.prep!.found, 0) / asked : null;
}

/** A round played: what the session remembers of it. */
export function afterRound(history: AutoHistory, round: AutoRound, selection: Selection): AutoHistory {
  return {
    modes: [...history.modes, round.mode],
    focuses: round.mode === 'survival' ? [...history.focuses, round.pick.focus] : history.focuses,
    steered: round.mode === 'survival' ? [...history.steered, isSteered(round.pick, selection)] : history.steered,
    starts: round.mode === 'survival' ? [...history.starts, round.pick.start] : history.starts,
  };
}
