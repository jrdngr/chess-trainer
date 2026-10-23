import type { Color } from '../chess/core';
import { favoritesIn, isAnyFavorite, resolveFavorite } from '../model/anyFavorite';
import { AUTO_DRILL } from '../model/autopilotPrefs';
import { coldStart, forcedStart, positionStart, testCycle, type ForcedStart, type TestCase } from '../model/autopilot';
import { ACCURACY_RUNS } from '../model/recommend';
import { buildRepairs, type RepairItem } from '../model/repair';
import { openingTree } from '../model/openingTree';
import { isSteered, recommend, type Focus, type RecommendInput, type Recommendation, type Start } from '../model/recommend';
import { referenceIndex } from '../model/referenceIndex';
import { seenIn, type RoundRecord } from '../model/scoring';
import { itemsInRegion, lineInRegion, regionOf, repertoiresIn, type Selection } from '../model/selection';
import { itemsFor, repertoireList, useStore } from './useStore';

type State = ReturnType<typeof useStore.getState>;

/**
 * The store as a session held to one selection sees it: the saved selection
 * swapped for that one, and nothing written back.
 */
export function withSelection(state: State, selection?: Selection): State {
  return selection ? { ...state, settings: { ...state.settings, selection } } : state;
}

/* ── Any favorite ────────────────────────────────────────────────────────── */

/** The favorite the last round landed on, so the next one is another. */
let lastFavorite: string | null = null;
/** A round already looked ahead at (Home's Autopilot button), kept for the round that starts. */
let ahead: { key: string; selection: Selection } | null = null;

const aheadKey = (state: State, selection: Selection) =>
  `${selection.color}|${selection.opening}|${state.settings.favoriteOpenings.join(',')}`;

/**
 * Resolve "Any favorite" now. Favorites you have something prepared in come
 * first: a round in one you have nothing for would have nothing to ask.
 */
function resolveNow(state: State, selection: Selection): Selection {
  const tree = openingTree(referenceIndex());
  const reps = repertoireList(state);
  const prepared = favoritesIn(tree, state.settings.favoriteOpenings, selection.color)
    .filter(({ node, side }) => reps.some((rep) => rep.color === side && itemsInRegion(tree, node, itemsFor(rep)).length > 0))
    .map(({ node }) => node.id);
  return resolveFavorite(
    tree,
    selection,
    prepared.length ? prepared : state.settings.favoriteOpenings,
    (id) => state.score.nodes[id]?.lastAt ?? 0,
    lastFavorite,
    Math.random,
  );
}

/**
 * The selection the next round starts on: the saved one (or `selection`), with
 * "Any favorite" resolved to one favorite and its side. The same answer until
 * a round on it is played (`playedRound`), so saying it ahead of time (Home's
 * Autopilot button) and starting it agree, and asking twice is harmless.
 */
export function peekRoundSelection(state: State, selection: Selection = state.settings.selection): Selection {
  if (!isAnyFavorite(selection)) return selection;
  const key = aheadKey(state, selection);
  if (ahead?.key !== key) ahead = { key, selection: resolveNow(state, selection) };
  return ahead.selection;
}

/** A round on `selection` is under way: the next one lands on another favorite. */
export function playedRound(selection: Selection): void {
  if (selection.opening) lastFavorite = selection.opening;
  ahead = null;
}

/** The next round's selection, taken: for starting a round from a tap. */
export function takeRoundSelection(state: State, selection: Selection = state.settings.selection): Selection {
  const taken = peekRoundSelection(state, selection);
  if (isAnyFavorite(selection)) playedRound(taken);
  return taken;
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
    newPerSession: AUTO_DRILL.newPerSession,
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

/**
 * What Autopilot's next run is: the recommendation it plays, and, for a run
 * that starts at a position, the moves to it.
 */
export interface AutoRound {
  pick: Recommendation;
  at: string[] | null;
}

/** What a session remembers of its runs so far, oldest first. Nothing is saved. */
export interface AutoHistory {
  /** Their focuses, for the recommendation's brake. */
  focuses: Focus[];
  /** For each, whether it was steered into an opening below the selection. */
  steered: boolean[];
  /** Where each started, for the Cold Start rule — see `coldStart`. */
  starts: Start[];
  /** Whether each started at a position — see `positionStart`. */
  positions: boolean[];
}

export const NO_HISTORY: AutoHistory = { focuses: [], steered: [], starts: [], positions: [] };

/**
 * Autopilot's next run, or null with nothing prepared inside the selection.
 *
 * The recommendation engine picks what the run is about; every 4th starts
 * from move one, and the rest may start at a position your cards say is due
 * — see `autopilot.ts`. `force` is Mode Testing's: where this run starts,
 * whatever is owed, or null where it cannot.
 */
export function nextRound(state: State, history: AutoHistory, force?: ForcedStart): AutoRound | null {
  const recommended = recommendNow(state, history.focuses, history.steered);
  if (!recommended) return null;
  if (force === 'inside' && recommended.start !== 'inside') return null;
  if (force === 'inside' || force === 'first') return { pick: { ...recommended, start: force }, at: null };
  const pick = force ? { ...recommended, start: 'inside' as const } : coldStart(recommended, history.starts);
  if (pick.start === 'first') return { pick, at: null };

  const tree = openingTree(referenceIndex());
  const rep = repertoireList(state).find((r) => r.color === pick.color);
  const items = rep ? itemsInRegion(tree, pick.opening, itemsFor(rep)) : [];
  const owed = positionStart(items, state.cards, {
    accuracy: prepAccuracy(state.score.rounds, [pick.color]),
    lastWasPosition: !force && history.positions[history.positions.length - 1] === true,
  });
  // Mode Testing takes any position the opening has, when none is owed.
  const at = owed ?? (force ? (items.find((item) => item.pathSans.length > 0) ?? null) : null);
  if (force && !at) return null;
  return { pick, at: at ? at.pathSans : null };
}

/* ── Mode Testing ───────────────────────────────────────────────────────── */

/** The cases left in this cycle, and what the cycle was built for. */
let testQueue: TestCase[] = [];
let testKey = '';

/** The sides a selection covers that you have a repertoire for. */
function testColors(state: State, selection: Selection): Color[] {
  const sides: Color[] = selection.color === 'random' ? ['w', 'b'] : [selection.color];
  const held = sides.filter((side) => repertoireList(state).some((rep) => rep.color === side));
  return held.length ? held : sides;
}

/** A round Autopilot is about to play, with the selection it plays in and, under Mode Testing, its case. */
export interface PickedRound {
  round: AutoRound | null;
  within: Selection;
  test?: TestCase;
}

/**
 * Autopilot's next round. Normally `nextRound` on the next selection; with
 * Mode Testing on, the first case left in the cycle that can run, a fresh
 * cycle once every case has been played — see `testCycle`. Nothing is taken
 * from the cycle here: `tookTest` does that once the round is under way, so
 * Home's button can say what is next.
 */
export function pickRound(state: State, history: AutoHistory, scope?: Selection): PickedRound {
  const saved = scope ?? state.settings.selection;
  if (state.settings.autopilot.modeTesting) {
    const colors = testColors(state, saved);
    const key = `${saved.color}|${saved.opening}|${colors.join('')}`;
    if (key !== testKey || !testQueue.length) {
      testKey = key;
      testQueue = testCycle(colors, Math.random);
    }
    for (const attempt of [0, 1]) {
      for (const test of testQueue) {
        const sided: Selection = { ...saved, color: test.color };
        const within = scope ? sided : peekRoundSelection(state, sided);
        const round = nextRound(withSelection(state, within), history, forcedStart(test.variant));
        if (round) return { round, within, test };
      }
      // Nothing left in this cycle can run: start the next one.
      if (attempt === 0) testQueue = testCycle(colors, Math.random);
    }
  }
  const within = scope ?? peekRoundSelection(state);
  return { round: nextRound(withSelection(state, within), history), within };
}

/** A Mode Testing case has been played: the cycle moves on. */
export function tookTest(test: TestCase): void {
  const at = testQueue.findIndex((t) => t.variant === test.variant && t.color === test.color);
  if (at >= 0) testQueue = [...testQueue.slice(0, at), ...testQueue.slice(at + 1)];
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

/** A run played: what the session remembers of it. */
export function afterRound(history: AutoHistory, round: AutoRound, selection: Selection): AutoHistory {
  return {
    focuses: [...history.focuses, round.pick.focus],
    steered: [...history.steered, isSteered(round.pick, selection)],
    starts: [...history.starts, round.pick.start],
    positions: [...history.positions, round.at !== null],
  };
}
