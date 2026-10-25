import { create } from 'zustand';
import { positionKey, walkSan, type Color } from '../chess/core';
import {
  addLine,
  recordLosses,
  createRepertoire,
  moveSibling,
  pruneLine,
  removeSubtree,
  repertoireName,
  setNote,
  setPreferred,
  type SourceFor,
} from '../model/repertoire';
import { allItems, cardId, type TrainingItem } from '../model/session';
import { switchMove } from '../model/tidy';
import { DEFAULT_AUTOPILOT } from '../model/autopilotPrefs';
import type { StartKind } from '../model/autopilot';
import { createCard, createLineCard, lineCardId, review } from '../model/srs';
import type {
  Card,
  Grade,
  ImportedGame,
  LineCard,
  Repertoire,
  ReviewLogEntry,
  Settings,
} from '../model/types';
import {
  DEFAULT_DRILL,
  DEFAULT_GROWTH,
  DEFAULT_PLAY,
} from '../model/modes';
import { addMistake, type Mistake } from '../model/mistakes';
import { importedOnly, mergeGames, playGames, withPlayGame } from '../model/play';
import { DEFAULT_SELECTION, type Selection } from '../model/selection';
import { ANY_FAVORITE } from '../model/anyFavorite';
import { selectionFor } from '../model/onboarding';
import type { SeedOpening } from '../model/starterSets';
import {
  applyResult,
  EMPTY_SCORE,
  normalizeScore,
  recordRound,
  recordStart,
  settleRun,
  type MoveResult,
  type RatingMove,
  type RoundRecord,
  type ScoreState,
} from '../model/scoring';
import { openingTree } from '../model/openingTree';
import {
  appendEvent,
  lineAt,
  normalizeEvents,
  removedBetween,
  type AppEvent,
  type EventPlace,
  type NewEvent,
} from '../model/events';
import { referenceIndex } from '../model/referenceIndex';
import { normalizeSources } from '../model/moveSource';
import { cloudAvailable, readCloud, writeCloud, type CloudStatus, type WriteResult } from './cloud';
import {
  DEFAULT_SURVIVAL,
  normalizeSurvival,
  recordEndedSurvival,
  recordSurvival,
  type SurvivalPrefs,
  type SurvivalRecord,
} from '../model/survival';
import { clearState, debounce, loadState, probeStorage, saveState, type StorageSupport } from './db';

export const DEFAULT_SETTINGS: Settings = {
  showCoordinates: true,
  engineEnabled: true,
  boardTheme: 'slate',
  hapticFeedback: true,
  autoplay: true,
  lichessUsername: '',
  chesscomUsername: '',
  cloudSync: true,
  selection: { ...DEFAULT_SELECTION },
  favoriteOpenings: [],
  pickerSort: 'popular',
  onboarded: false,
  survival: { ...DEFAULT_SURVIVAL },
  drill: { ...DEFAULT_DRILL },
  play: { ...DEFAULT_PLAY },
  growth: { ...DEFAULT_GROWTH },
  autopilot: { ...DEFAULT_AUTOPILOT },
};

/**
 * Saved settings over the defaults, one level deep, so a new field never comes
 * back undefined.
 *
 * Only keys the app still has survive: a setting that has been renamed or
 * dropped would otherwise ride along in saved state forever, unread and
 * confusing to anyone who opens the file later.
 */
function mergeSettings(saved: Partial<Settings> | undefined): Settings {
  const known = Object.fromEntries(
    Object.entries(saved ?? {}).filter(([key]) => key in DEFAULT_SETTINGS),
  ) as Partial<Settings>;
  return {
    ...DEFAULT_SETTINGS,
    ...known,
    selection: { ...DEFAULT_SELECTION, ...known.selection },
    survival: { ...DEFAULT_SURVIVAL, ...known.survival },
    drill: { ...DEFAULT_DRILL, ...known.drill },
    play: { ...DEFAULT_PLAY, ...known.play },
    growth: { ...DEFAULT_GROWTH, ...known.growth },
    autopilot: { ...DEFAULT_AUTOPILOT, ...known.autopilot },
  };
}

/**
 * Bump when the seeded repertoires change shape or content, or when the saved
 * shape itself changes. A saved state from an older schema is discarded rather
 * than migrated — this is a prototype, and the seed data is the thing most
 * likely to change.
 *
 * 4: permadeath became openingRun, settings and records included.
 * 5: each mode keeps its own options; Punish keeps a record.
 * 6: Punish became Repair, which is built from imported games.
 * 7: no seeded repertoires — everyone starts empty and builds their own.
 * 8: Gap became Growth, and keeps different options.
 * 9: one tree per colour, named for the side; openings are derived from it.
 * 0: the fresh start — global colour and opening, score and stats. Every save
 *    from before it, settings included, is discarded rather than migrated.
 */
export const SCHEMA_VERSION = 0;

/** Saved moves onto the current source labels — see `normalizeSources`. */
function upgradeSources(
  repertoires: Record<string, Repertoire>,
  games: ImportedGame[] | undefined,
): Record<string, Repertoire> {
  return normalizeSources(repertoires, referenceIndex(), importedOnly(games ?? []).length > 0);
}

interface PersistedState {
  version: number;
  /** When this state was last changed, used to resolve device conflicts. */
  updatedAt: number;
  repertoires: Record<string, Repertoire>;
  repertoireOrder: string[];
  cards: Record<string, Card>;
  /** Drill lines' schedule, one card per line — see `LineCard`. */
  lineCards: Record<string, LineCard>;
  log: ReviewLogEntry[];
  settings: Settings;
  importedGames: ImportedGame[];
  /** Moves survived, per opening and overall. */
  survival: SurvivalRecord;
  /** Mistakes made inside the app, which steer practice back to them. */
  mistakes: Mistake[];
  /** Every opening's rating and activity, and every round played. */
  score: ScoreState;
  /** What changed the repertoire, and what Growth offered — see `src/model/events.ts`. */
  events: AppEvent[];
}

interface StoreState extends PersistedState {
  ready: boolean;
  cloud: CloudStatus;
  /** An opening whose stats page was asked for, until the Stats tab picks it up. '' is the whole game. */
  statsTarget: string | null;
  openStats: (openingId: string) => void;
  clearStats: () => void;
  /** Which persistence backends actually work on this page. */
  storage: StorageSupport;
  syncNow: () => Promise<void>;
  init: () => Promise<void>;
  resetAll: () => Promise<void>;
  resetProgress: () => void;

  /** `via` says where the change came from, when the screen it happened on does not. */
  /** `lost` is what the engine said of each move of the line, where it was asked: see `recordLosses`. */
  addLine: (repId: string, sans: string[], source: SourceFor, via?: EventPlace, lost?: (number | undefined)[]) => { added: number };
  /** Delete a move and everything after it. Returns an undo, or null when there was nothing to delete. */
  removeNode: (repId: string, nodeId: string, via?: EventPlace) => (() => void) | null;
  /** Delete one line: its last move back to where it parts from another line. Returns an undo. */
  removeLine: (repId: string, tipId: string) => (() => void) | null;
  preferMove: (repId: string, nodeId: string) => void;
  /** Record something worth knowing later that changed nothing — what Growth offered, say. */
  logEvent: (event: NewEvent) => void;
  annotate: (repId: string, nodeId: string, note: string) => void;
  reorder: (repId: string, nodeId: string, delta: number) => void;
  addRepertoire: (name: string, color: Color) => string;
  /** The tree for one side, created if this is the first line for it. */
  ensureRepertoire: (color: Color) => string;
  /**
   * Delete a derived opening: the region, and the move order that only led to
   * it. `rootId` is the opening's own root node.
   */
  /** Delete an opening; with `tips`, only those lines, so the openings nested in it stay. */
  removeOpening: (repId: string, rootId: string, tips?: string[]) => void;
  /** Delete one side's tree outright, with everything that only existed for it. */
  removeRepertoire: (repId: string) => void;
  /**
   * Tidy: play `san` instead of your move at `nodeId`, dropping that move and
   * its line. The position starts over — its card is new again and its
   * logged mistakes go — but ratings stand. Returns an undo, or null when the
   * switch could not be made.
   */
  tidySwitch: (repId: string, nodeId: string, san: string) => (() => void) | null;
  /** Keep a reply Tidy listed as rarely chosen: it leaves the list until more is added under it. */
  tidyKeep: (repId: string, nodeId: string) => void;
  /** Remove that reply and everything under it; returns the undo. */
  tidyRemove: (repId: string, nodeId: string) => (() => void) | null;

  grade: (item: TrainingItem, grade: Grade, playedSan: string | null, correct: boolean) => void;
  /**
   * Change the grade just given: the card goes back to how it was before
   * that review and is reviewed again with the new grade, and the log entry
   * is replaced rather than joined.
   */
  regrade: (item: TrainingItem, before: Card, grade: Grade, playedSan: string | null) => void;
  ensureCard: (item: TrainingItem) => Card;
  /**
   * Grade a whole line, from Drill lines. With `before`, the line's card as
   * it was before this sitting's grade: the grade is changed rather than
   * given twice. Returns the card the grade was applied to.
   */
  gradeLine: (repertoireId: string, tipId: string, grade: Grade, before?: LineCard) => LineCard;

  setSettings: (patch: Partial<Settings>) => void;
  setSelection: (patch: Partial<Selection>) => void;
  toggleStar: (openingId: string) => void;
  /**
   * Answer the opening question a fresh profile is asked: star each opening,
   * put exactly its own move order into the tree for the side that plays it,
   * and point the global selection at what was picked. Nothing past an
   * opening's moves goes in, so nothing is tested that was never shown. An
   * empty list is the player saying they have none, which only records that
   * they were asked. `lines` are lines played in on the board, in before the
   * openings and kept with what the engine said of their moves.
   */
  finishOnboarding: (openings: SeedOpening[], lines?: OnboardingLine[]) => void;
  setSurvivalPrefs: (patch: Partial<SurvivalPrefs>) => void;
  /** Patch one mode's own options, without touching the rest of settings. */
  setModePrefs: <K extends 'drill' | 'growth' | 'play' | 'autopilot'>(
    mode: K,
    patch: Partial<Settings[K]>,
  ) => void;
  /** Replace the imported games. Games played here are kept. */
  setImportedGames: (games: ImportedGame[]) => void;
  /** Keep a game finished in Play, as evidence for steering and coverage. */
  recordPlayGame: (game: ImportedGame) => void;

  /** Log a finished Survival run: its moves survived, against every opening its line went through. */
  endSurvival: (line: string[], moves: number, points?: number) => void;
  /** Log a Survival run you ended yourself: a count, and nothing toward best or form. */
  endSurvivalEarly: (line: string[]) => void;
  /**
   * Record one answer: activity against the openings its line names, and, for
   * a rated one, the rating of every opening its line has reached. `earlier`
   * is the run's rated answers so far, which an opening reached for the first
   * time takes too. Returns the ratings that moved.
   */
  recordMove: (result: Omit<MoveResult, 'at'> & { at?: number }, earlier?: MoveResult[]) => RatingMove[];
  /**
   * A run is over: rate its answers into any opening only its last moves
   * reached. Returns the ratings that moved.
   */
  settleRun: (earlier: MoveResult[], line: string[]) => RatingMove[];
  /** Count a finished round against its opening. */
  endRound: (round: Omit<RoundRecord, 'at'>) => void;
  /** Autopilot started a run this way — see `chooseStart`. */
  noteStart: (kind: StartKind) => void;
  /** Remember a move the user got wrong somewhere in the app. */
  logMistake: (mistake: Omit<Mistake, 'id' | 'at'>) => void;
  /** Forget one, once it has been answered right. */
  clearMistake: (id: string) => void;
  /**
   * A correct move in a run, on a position your prep has an answer to. It is
   * a review: graded by how long it took where the position already has a
   * card, and a plain pass where this is the first time it has been asked.
   * Autopilot and Drill share one schedule, so what a round has shown you know is not
   * asked again until it is due.
   */
  answeredInOpeningRun: (repertoireId: string, fen: string, played: string, grade: Grade) => void;
  /** A miss in a run: a lapse, and a logged mistake. */
  missedInOpeningRun: (repertoireId: string, fen: string, played: string, expected: string) => void;
}

/**
 * A new install has no repertoires at all.
 *
 * Seeded lines made the first screen look busy, but they were somebody else's
 * openings: Drill asked about a Queen's Gambit nobody had chosen, and Repair
 * compared real games against prep the player had never agreed to. You now
 * build the repertoire yourself, one tap at a time — Growth answers the
 * replies you have none for, Run offers the line it ran at the reveal, Play
 * saves the opening from a game — and nothing writes into it unasked.
 */
function emptyPersisted(): PersistedState {
  return {
    version: SCHEMA_VERSION,
    updatedAt: Date.now(),
    repertoires: {},
    repertoireOrder: [],
    cards: {},
    lineCards: {},
    log: [],
    settings: { ...DEFAULT_SETTINGS },
    importedGames: [],
    survival: normalizeSurvival(undefined),
    mistakes: [],
    score: normalizeScore(EMPTY_SCORE),
    events: [],
  };
}

function persistedFrom(state: StoreState): PersistedState {
  return {
    version: SCHEMA_VERSION,
    updatedAt: state.updatedAt,
    repertoires: state.repertoires,
    repertoireOrder: state.repertoireOrder,
    cards: state.cards,
    lineCards: state.lineCards,
    log: state.log,
    settings: state.settings,
    importedGames: state.importedGames,
    survival: state.survival,
    mistakes: state.mistakes,
    score: state.score,
    events: state.events,
  };
}

/**
 * What goes to the cloud. Imported games are left out deliberately: they are
 * bulky, re-importable, and the payload has to stay under a 256 KiB document.
 * Games played here go: there is nowhere to re-import them from, and they are
 * capped and cut to their openings to stay small.
 */
function syncableFrom(state: StoreState): PersistedState {
  return { ...persistedFrom(state), importedGames: playGames(state.importedGames) };
}

const persist = debounce((state: StoreState) => {
  void saveState(persistedFrom(state));
}, 250);

/** A saved state is only usable if it exists and was written by this schema. */
function usable(saved: PersistedState | null | undefined): PersistedState | null {
  return saved?.repertoires && saved.version === SCHEMA_VERSION ? saved : null;
}

function statusAfterWrite(result: WriteResult): CloudStatus {
  if (result.ok) return { kind: 'synced', lastSyncedAt: Date.now() };
  if (result.reason === 'unavailable') return { kind: 'unavailable' };
  if (result.reason === 'too-large') return { kind: 'too-large', bytes: result.bytes ?? 0 };
  return { kind: 'error', message: result.message ?? 'Sync failed' };
}

/** Review one card and log it; shared by training and openingRun. */
function reviewed(
  state: StoreState,
  card: Card,
  gradeValue: Grade,
  entry: Pick<ReviewLogEntry, 'correct' | 'playedSan' | 'expectedSan'>,
): Pick<PersistedState, 'cards' | 'log'> {
  const now = Date.now();
  const { card: next } = review(card, gradeValue, now);
  return {
    cards: { ...state.cards, [card.id]: next },
    log: [
      ...state.log.slice(-499),
      {
        ...entry,
        cardId: card.id,
        at: now,
        grade: gradeValue,
        intervalBefore: card.interval,
        intervalAfter: next.interval,
      },
    ],
  };
}

/** A review a run made: the card remembers which run asked it, for Autopilot's starts. */
function testedInRun(
  state: StoreState,
  result: Pick<PersistedState, 'cards' | 'log'>,
  id: string,
): Pick<PersistedState, 'cards' | 'log'> {
  return { ...result, cards: { ...result.cards, [id]: { ...result.cards[id], testedRound: state.score.lineRounds } } };
}

/**
 * A logged mistake retires once the position is answered right. Until then it
 * steers practice back to it; after that the card's schedule takes over.
 */
function settled(mistakes: Mistake[], repertoireId: string, key: string): Mistake[] {
  const id = `${repertoireId}#${key}`;
  return mistakes.some((m) => m.id === id) ? mistakes.filter((m) => m.id !== id) : mistakes;
}

/** A line played in on the board during onboarding, and what the engine said of its moves. */
export interface OnboardingLine extends SeedOpening {
  lost?: (number | undefined)[];
}

/**
 * What answering the opening question changes, without changing it:
 * onboarding shows its ready screen from this and commits it only once the
 * player leaves that screen. See `finishOnboarding`.
 */
export function onboarded(
  state: Pick<StoreState, 'repertoires' | 'repertoireOrder' | 'events' | 'settings'>,
  openings: SeedOpening[],
  boardLines: OnboardingLine[] = [],
): Pick<StoreState, 'repertoires' | 'repertoireOrder' | 'events' | 'settings'> {
  const tree = openingTree(referenceIndex());
  // Only what the board can play: a move order that is not legal is not an opening.
  const legal = <T extends SeedOpening>(list: T[]) => list.filter(({ sans }) => walkSan(sans).fens.length === sans.length + 1);
  const lines: (OnboardingLine & { source: 'board' | 'picker' })[] = [
    ...legal(boardLines).map((line) => ({ ...line, source: 'board' as const })),
    ...legal(openings).map((line) => ({ ...line, source: 'picker' as const })),
  ];
  const repertoires = { ...state.repertoires };
  const order = [...state.repertoireOrder];
  const byColor = new Map<Color, string>(
    order.map((id) => repertoires[id]).filter((rep) => !!rep).map((rep) => [rep.color, rep.id]),
  );

  let events = state.events;
  for (const line of lines) {
    let repId = byColor.get(line.color);
    if (!repId) {
      const rep = createRepertoire(repertoireName(line.color), line.color);
      repertoires[rep.id] = rep;
      order.push(rep.id);
      byColor.set(line.color, rep.id);
      repId = rep.id;
    }
    const res = addLine(repertoires[repId], line.sans, line.source);
    repertoires[repId] = line.lost?.length ? recordLosses(res.rep, line.sans, line.lost) : res.rep;
    if (res.added > 0) {
      events = appendEvent(events, {
        kind: 'add',
        repertoireId: repId,
        color: line.color,
        line: line.sans.join(' '),
        added: res.added,
        source: line.source,
        via: 'onboarding',
      });
    }
  }

  // Starred where the book names them, so they lead the quick picker and Home's ladder.
  const picks = openings
    .map((opening) => ({ opening, node: tree.byId.get(opening.sans.join(' ')) }))
    .filter(({ node }) => node && node.depth > 0)
    .map(({ opening, node }) => ({ id: node!.id, name: node!.name, color: opening.color, sans: opening.sans }));

  return {
    repertoires,
    repertoireOrder: order,
    events,
    settings: {
      ...state.settings,
      favoriteOpenings: [
        ...new Set([...state.settings.favoriteOpenings, ...picks.map((pick) => pick.id)]),
      ],
      // Nothing picked says nothing about which side they play.
      selection: picks.length ? selectionFor(picks) : state.settings.selection,
      onboarded: true,
    },
  };
}

export const useStore = create<StoreState>((set, get) => {
  /**
   * Push well after the user stops interacting. Held back until the first
   * reconcile: a freshly seeded state must never overwrite the account copy
   * before it has been read.
   */
  let hydrated = false;

  const pushCloud = debounce(() => {
    const state = get();
    if (!hydrated) return;
    if (!state.settings.cloudSync) return;
    if (state.cloud.kind === 'unavailable') return;
    set({ cloud: { kind: 'syncing' } });
    void writeCloud(syncableFrom(state), state.updatedAt).then((result) => {
      set({ cloud: statusAfterWrite(result) });
    });
  }, 4000);

  const commit = (patch: Partial<StoreState>) => {
    set({ ...patch, updatedAt: Date.now() } as Partial<StoreState>);
    persist(get());
    pushCloud();
  };

  /** The log with one more event, for a commit to carry with the change it describes. */
  const logged = (event: NewEvent) => appendEvent(get().events, event);

  const updateRep = (
    repId: string,
    fn: (rep: Repertoire) => Repertoire,
    describe?: (before: Repertoire, after: Repertoire) => NewEvent | null,
  ) => {
    const rep = get().repertoires[repId];
    if (!rep) return;
    const next = fn(rep);
    const event = describe?.(rep, next);
    commit({
      repertoires: { ...get().repertoires, [repId]: next },
      ...(event ? { events: logged(event) } : {}),
    });
  };

  /**
   * Shrink a tree, and drop what only existed for the positions that went.
   *
   * A card, a logged mistake and a review entry are all keyed by position, and
   * a position that is no longer in the tree has nothing to ask about — left
   * behind they would keep counting toward "positions ready" for lines that
   * were deleted. Surviving keys are read back off the tree rather than
   * predicted, so a position still reachable by another move order keeps its
   * schedule.
   */
  const shrinkRep = (
    repId: string,
    fn: (rep: Repertoire) => Repertoire,
    describe?: (before: Repertoire, after: Repertoire) => NewEvent | null,
  ) => {
    const state = get();
    const rep = state.repertoires[repId];
    if (!rep) return;
    const next = fn(rep);
    const alive = new Set(Object.values(next.nodes).map((node) => node.key));
    const orphaned = (id: string, key: string) => id === repId && !alive.has(key);
    const event = describe?.(rep, next);
    commit({
      repertoires: { ...state.repertoires, [repId]: next },
      ...(event ? { events: logged(event) } : {}),
      cards: Object.fromEntries(
        Object.entries(state.cards).filter(([, card]) => !orphaned(card.repertoireId, card.key)),
      ),
      log: state.log.filter((entry) => {
        const [id, key] = splitCardId(entry.cardId);
        return !orphaned(id, key);
      }),
      mistakes: state.mistakes.filter((m) => !orphaned(m.repertoireId, m.key)),
    });
  };

  /** Put a tree back as it was before a delete, with what the delete took from cards, log and mistakes. */
  const undoFor = (repId: string, nodeId: string): (() => void) | null => {
    const before = get();
    const rep = before.repertoires[repId];
    if (!rep?.nodes[nodeId]) return null;
    const saved = { rep, cards: before.cards, log: before.log, mistakes: before.mistakes };
    return () => {
      commit({
        repertoires: { ...get().repertoires, [repId]: saved.rep },
        cards: saved.cards,
        log: saved.log,
        mistakes: saved.mistakes,
        events: logged({ kind: 'remove-undo', repertoireId: repId, color: saved.rep.color, line: lineAt(saved.rep, nodeId) }),
      });
    };
  };

  return {
    ...emptyPersisted(),
    ready: false,
    statsTarget: null,
    openStats(openingId) {
      set({ statsTarget: openingId });
    },
    clearStats() {
      set({ statsTarget: null });
    },
    cloud: cloudAvailable() ? { kind: 'idle', lastSyncedAt: null } : { kind: 'unavailable' },
    storage: { localStorage: false, indexedDB: false, any: false },

    async init() {
      const storage = await probeStorage();
      const saved = await loadState<PersistedState>();
      const usableLocal = usable(saved);

      // Read the account copy before deciding anything. When local storage is
      // blocked — which is the normal case inside the artifact sandbox — this
      // is the only place the user's progress exists.
      const remote = cloudAvailable() ? await readCloud<PersistedState>() : null;
      const usableRemote = remote && usable(remote.state) ? remote : null;

      const localAt = usableLocal?.updatedAt ?? 0;
      const remoteAt = usableRemote?.updatedAt ?? 0;
      const chosen = usableRemote && remoteAt >= localAt ? usableRemote.state : usableLocal;

      if (chosen) {
        set({
          ...chosen,
          repertoires: upgradeSources(chosen.repertoires, chosen.importedGames),
          survival: normalizeSurvival(chosen.survival),
          mistakes: chosen.mistakes ?? [],
          lineCards: chosen.lineCards ?? {},
          score: normalizeScore(chosen.score),
          events: normalizeEvents(chosen.events),
          updatedAt: Math.max(localAt, remoteAt),
          settings: mergeSettings(chosen.settings),
          storage,
          ready: true,
          cloud: usableRemote
            ? { kind: 'synced', lastSyncedAt: Date.now() }
            : cloudAvailable()
              ? { kind: 'idle', lastSyncedAt: null }
              : { kind: 'unavailable' },
        });
      } else {
        // Nothing anywhere, or a save from an older schema: a fresh start.
        set({
          ...emptyPersisted(),
          storage,
          ready: true,
        });
      }

      hydrated = true;
      if (storage.any) persist(get());
      // Make sure the account copy exists and is current.
      if (get().settings.cloudSync && cloudAvailable()) pushCloud();
    },

    async syncNow() {
      if (!cloudAvailable()) {
        set({ cloud: { kind: 'unavailable' } });
        return;
      }
      hydrated = true;
      set({ cloud: { kind: 'syncing' } });
      const remote = await readCloud<PersistedState>();
      const local = get();

      if (remote && usable(remote.state) && remote.updatedAt > local.updatedAt) {
        // Another device is ahead. Whole-state last-write-wins: right for one
        // person on two devices, and honest about not merging concurrent edits.
        set({
          ...remote.state,
          repertoires: upgradeSources(remote.state.repertoires, remote.state.importedGames),
          survival: normalizeSurvival(remote.state.survival),
          mistakes: remote.state.mistakes ?? [],
          lineCards: remote.state.lineCards ?? {},
          score: normalizeScore(remote.state.score),
          events: normalizeEvents(remote.state.events),
          importedGames: mergeGames(local.importedGames, remote.state.importedGames ?? []),
          settings: mergeSettings(remote.state.settings),
          updatedAt: remote.updatedAt,
          ready: true,
          cloud: { kind: 'synced', lastSyncedAt: Date.now() },
        });
        persist(get());
        return;
      }

      const result = await writeCloud(syncableFrom(get()), get().updatedAt);
      set({ cloud: statusAfterWrite(result) });
    },

    async resetAll() {
      await clearState();
      set({ ...emptyPersisted(), ready: true });
      persist(get());
      pushCloud();
    },

    resetProgress() {
      commit({ cards: {}, lineCards: {}, log: [] });
    },

    addLine(repId, sans, source, via, lost) {
      const rep = get().repertoires[repId];
      if (!rep) return { added: 0 };
      const res = addLine(rep, sans, source);
      commit({
        repertoires: { ...get().repertoires, [repId]: lost?.length ? recordLosses(res.rep, sans, lost) : res.rep },
        ...(res.added > 0
          ? {
              events: logged({
                kind: 'add',
                repertoireId: repId,
                color: rep.color,
                line: sans.join(' '),
                added: res.added,
                source: typeof source === 'function' ? 'growth' : source,
                ...(via ? { via } : {}),
              }),
            }
          : {}),
      });
      return { added: res.added };
    },

    removeNode(repId, nodeId, via) {
      const undo = undoFor(repId, nodeId);
      if (!undo) return null;
      shrinkRep(
        repId,
        (rep) => removeSubtree(rep, nodeId),
        (before, after) => ({
          kind: 'remove',
          repertoireId: repId,
          color: before.color,
          line: lineAt(before, nodeId),
          ...removedBetween(before, after),
          ...(via ? { via } : {}),
        }),
      );
      return undo;
    },

    removeLine(repId, tipId) {
      const undo = undoFor(repId, tipId);
      if (!undo) return null;
      shrinkRep(
        repId,
        (rep) => pruneLine(rep, tipId),
        (before, after) => ({
          kind: 'remove-line',
          repertoireId: repId,
          color: before.color,
          line: lineAt(before, tipId),
          ...removedBetween(before, after),
        }),
      );
      return undo;
    },

    logEvent(event) {
      commit({ events: logged(event) });
    },

    tidyKeep(repId, nodeId) {
      const rep = get().repertoires[repId];
      const node = rep?.nodes[nodeId];
      if (!rep || !node) return;
      commit({
        repertoires: {
          ...get().repertoires,
          [repId]: { ...rep, nodes: { ...rep.nodes, [nodeId]: { ...node, keptAt: Date.now() } } },
        },
        events: logged({ kind: 'tidy-keep', repertoireId: repId, color: rep.color, line: lineAt(rep, nodeId) }),
      });
    },

    tidyRemove(repId, nodeId) {
      const before = get();
      const rep = before.repertoires[repId];
      if (!rep?.nodes[nodeId]) return null;
      const saved = { rep, cards: before.cards, log: before.log, mistakes: before.mistakes };
      shrinkRep(
        repId,
        (was) => removeSubtree(was, nodeId),
        (was, now) => ({
          kind: 'tidy-remove',
          repertoireId: repId,
          color: was.color,
          line: lineAt(was, nodeId),
          ...removedBetween(was, now),
        }),
      );
      return () => {
        commit({
          repertoires: { ...get().repertoires, [repId]: saved.rep },
          cards: saved.cards,
          log: saved.log,
          mistakes: saved.mistakes,
          events: logged({
            kind: 'tidy-remove-undo',
            repertoireId: repId,
            color: saved.rep.color,
            line: lineAt(saved.rep, nodeId),
          }),
        });
      };
    },

    tidySwitch(repId, nodeId, san) {
      const before = get();
      const rep = before.repertoires[repId];
      const node = rep?.nodes[nodeId];
      const next = rep ? switchMove(rep, nodeId, san) : null;
      if (!rep || !node || !next) return null;
      const saved = {
        rep,
        cards: before.cards,
        log: before.log,
        mistakes: before.mistakes,
      };
      shrinkRep(
        repId,
        () => next,
        (was, now) => ({
          kind: 'tidy-switch',
          repertoireId: repId,
          color: was.color,
          line: lineAt(was, nodeId),
          to: san,
          ...removedBetween(was, now),
        }),
      );
      // The answer here changed, so what the old answer earned does not
      // carry: the card starts over and the misses logged against it go.
      const after = get();
      const id = cardId(repId, node.key);
      const { [id]: _reset, ...cards } = after.cards;
      commit({
        cards,
        mistakes: after.mistakes.filter((m) => !(m.repertoireId === repId && m.key === node.key)),
      });
      return () => {
        commit({
          repertoires: { ...get().repertoires, [repId]: saved.rep },
          cards: saved.cards,
          log: saved.log,
          mistakes: saved.mistakes,
          events: logged({
            kind: 'tidy-undo',
            repertoireId: repId,
            color: saved.rep.color,
            line: lineAt(saved.rep, nodeId),
            to: san,
          }),
        });
      };
    },

    removeOpening(repId, rootId, tips) {
      shrinkRep(
        repId,
        (rep) => (tips ? tips.reduce((next, tip) => pruneLine(next, tip), rep) : pruneLine(rep, rootId)),
        (before, after) => ({
          kind: 'remove-opening',
          repertoireId: repId,
          color: before.color,
          line: lineAt(before, rootId),
          ...removedBetween(before, after),
        }),
      );
    },

    preferMove(repId, nodeId) {
      updateRep(
        repId,
        (rep) => setPreferred(rep, nodeId),
        (before) => ({ kind: 'prefer', repertoireId: repId, color: before.color, line: lineAt(before, nodeId) }),
      );
    },

    annotate(repId, nodeId, note) {
      updateRep(
        repId,
        (rep) => setNote(rep, nodeId, note),
        (before) => ({ kind: 'note', repertoireId: repId, color: before.color, line: lineAt(before, nodeId) }),
      );
    },

    reorder(repId, nodeId, delta) {
      updateRep(
        repId,
        (rep) => moveSibling(rep, nodeId, delta),
        (before) => ({ kind: 'reorder', repertoireId: repId, color: before.color, line: lineAt(before, nodeId), delta }),
      );
    },

    addRepertoire(name, color) {
      const rep = createRepertoire(name, color);
      commit({
        repertoires: { ...get().repertoires, [rep.id]: rep },
        repertoireOrder: [...get().repertoireOrder, rep.id],
      });
      return rep.id;
    },

    /**
     * One tree per colour, so everything that saves a line asks for the side and
     * gets the same tree back. Naming it after the opening that happened to
     * create it was the old behaviour, and it went stale the moment a second
     * opening moved in.
     */
    ensureRepertoire(color) {
      const existing = repertoireList(get()).find((rep) => rep.color === color);
      if (existing) return existing.id;
      return get().addRepertoire(repertoireName(color), color);
    },

    /**
     * Deleting a repertoire takes its schedule and its logged mistakes with it.
     * Those are keyed by repertoire and mean nothing without it — left behind
     * they would count toward "positions ready" for lines that no longer exist.
     */
    removeRepertoire(repId) {
      const state = get();
      if (!state.repertoires[repId]) return;
      const repertoires = { ...state.repertoires };
      const gone = repertoires[repId];
      delete repertoires[repId];
      commit({
        events: logged({
          kind: 'remove-repertoire',
          repertoireId: repId,
          color: gone.color,
          count: Object.keys(gone.nodes).length,
        }),
        repertoires,
        repertoireOrder: state.repertoireOrder.filter((id) => id !== repId),
        cards: Object.fromEntries(
          Object.entries(state.cards).filter(([, card]) => card.repertoireId !== repId),
        ),
        lineCards: Object.fromEntries(
          Object.entries(state.lineCards).filter(([, card]) => card.repertoireId !== repId),
        ),
        log: state.log.filter((entry) => !entry.cardId.startsWith(`${repId}#`)),
        mistakes: state.mistakes.filter((m) => m.repertoireId !== repId),
      });
    },

    ensureCard(item) {
      const existing = get().cards[item.cardId];
      if (existing) return existing;
      const card = createCard(item.cardId, item.repertoireId, item.key, item.fen);
      commit({ cards: { ...get().cards, [item.cardId]: card } });
      return card;
    },

    grade(item, gradeValue, playedSan, correct) {
      const state = get();
      const card =
        state.cards[item.cardId] ?? createCard(item.cardId, item.repertoireId, item.key, item.fen);
      const expectedSan = item.expected.find((e) => e.preferred)?.san ?? item.expected[0]?.san ?? '';
      commit({
        ...reviewed(state, card, gradeValue, { correct, playedSan, expectedSan }),
        mistakes: correct ? settled(state.mistakes, item.repertoireId, item.key) : state.mistakes,
      });
    },

    regrade(item, before, gradeValue, playedSan) {
      const state = get();
      const expectedSan = item.expected.find((e) => e.preferred)?.san ?? item.expected[0]?.san ?? '';
      const last = [...state.log].reverse().findIndex((entry) => entry.cardId === item.cardId);
      const log = last < 0 ? state.log : state.log.filter((_, i) => i !== state.log.length - 1 - last);
      const again = reviewed({ ...state, log }, before, gradeValue, { correct: true, playedSan, expectedSan });
      commit(again);
    },

    gradeLine(repertoireId, tipId, gradeValue, before) {
      const state = get();
      const id = lineCardId(repertoireId, tipId);
      const from = before ?? state.lineCards[id] ?? createLineCard(repertoireId, tipId);
      const { card } = review(from, gradeValue);
      commit({ lineCards: { ...state.lineCards, [id]: card } });
      return from;
    },

    setSettings(patch) {
      commit({ settings: { ...get().settings, ...patch } });
    },

    setSelection(patch) {
      const settings = get().settings;
      commit({ settings: { ...settings, selection: { ...settings.selection, ...patch } } });
    },

    toggleStar(openingId) {
      const settings = get().settings;
      const starred = settings.favoriteOpenings.includes(openingId)
        ? settings.favoriteOpenings.filter((id) => id !== openingId)
        : [...settings.favoriteOpenings, openingId];
      // "Any favorite" with none left is Any opening.
      const selection =
        settings.selection.opening === ANY_FAVORITE && starred.length === 0 ? { ...settings.selection, opening: '' } : settings.selection;
      commit({ settings: { ...settings, favoriteOpenings: starred, selection } });
    },

    /**
     * One commit for the whole answer: a half-built profile (trees created but
     * the flag unset, say) would ask the question again on the next launch
     * with the lines already in.
     */
    finishOnboarding(openings, lines = []) {
      commit(onboarded(get(), openings, lines));
    },

    setSurvivalPrefs(patch) {
      const settings = get().settings;
      commit({ settings: { ...settings, survival: { ...settings.survival, ...patch } } });
    },

    setModePrefs(mode, patch) {
      const settings = get().settings;
      commit({ settings: { ...settings, [mode]: { ...settings[mode], ...patch } } });
    },

    setImportedGames(games) {
      commit({ importedGames: [...playGames(get().importedGames), ...importedOnly(games)] });
    },

    recordPlayGame(game) {
      commit({ importedGames: withPlayGame(get().importedGames, game) });
    },

    endSurvival(line, moves, points) {
      commit({ survival: recordSurvival(get().survival, openingTree(referenceIndex()), line, moves, points) });
    },

    endSurvivalEarly(line) {
      commit({ survival: recordEndedSurvival(get().survival, openingTree(referenceIndex()), line) });
    },

    settleRun(earlier, line) {
      const { state: score, moves } = settleRun(get().score, openingTree(referenceIndex()), earlier, line);
      if (moves.length) commit({ score });
      return moves;
    },

    recordMove(result, earlier) {
      const state = get();
      const tree = openingTree(referenceIndex());
      const { state: score, moves } = applyResult(
        state.score,
        tree,
        { ...result, at: result.at ?? Date.now() },
        earlier,
      );
      commit({ score });
      return moves;
    },

    endRound(round) {
      commit({ score: recordRound(get().score, openingTree(referenceIndex()), { ...round, at: Date.now() }) });
    },

    noteStart(kind) {
      commit({ score: recordStart(get().score, kind) });
    },

    logMistake(mistake) {
      commit({ mistakes: addMistake(get().mistakes, mistake) });
    },

    clearMistake(id) {
      commit({ mistakes: get().mistakes.filter((m) => m.id !== id) });
    },

    answeredInOpeningRun(repertoireId, fen, played, gradeValue) {
      const key = positionKey(fen);
      const id = cardId(repertoireId, key);
      const state = get();
      const existing = state.cards[id];
      const card = existing ?? createCard(id, repertoireId, key, fen);
      commit({
        ...testedInRun(
          state,
          reviewed(state, card, existing ? gradeValue : 'good', {
            correct: true,
            playedSan: played,
            expectedSan: played,
          }),
          id,
        ),
        mistakes: settled(state.mistakes, repertoireId, key),
      });
    },

    missedInOpeningRun(repertoireId, fen, played, expected) {
      const key = positionKey(fen);
      const id = cardId(repertoireId, key);
      const state = get();
      const card = state.cards[id] ?? createCard(id, repertoireId, key, fen);
      commit({
        ...testedInRun(state, reviewed(state, card, 'again', { correct: false, playedSan: played, expectedSan: expected }), id),
        mistakes: addMistake(state.mistakes, {
          source: 'openingRun',
          repertoireId,
          key,
          fen,
          played,
          expected,
        }),
      });
    },

  };
});

/* ───────────────────────────── selectors ───────────────────────────── */

export function repertoireList(state: Pick<StoreState, 'repertoires' | 'repertoireOrder'>): Repertoire[] {
  return state.repertoireOrder.map((id) => state.repertoires[id]).filter(Boolean);
}

/**
 * A profile nothing has happened in yet: a new install, or one that has just
 * been reset. Read rather than flagged, so a state synced down from another
 * device is never mistaken for a new player.
 */
export function freshProfile(state: StoreState): boolean {
  return (
    state.repertoireOrder.length === 0 &&
    Object.keys(state.cards).length === 0 &&
    state.importedGames.length === 0 &&
    state.score.global.answered === 0
  );
}

/** Ask the opening question once, of a profile with nothing in it. */
export function needsOnboarding(state: StoreState): boolean {
  return state.ready && !state.settings.onboarded && freshProfile(state);
}

/** allItems() walks the whole tree, so memoise on repertoire identity. */
const itemCache = new WeakMap<Repertoire, TrainingItem[]>();

export function itemsFor(rep: Repertoire): TrainingItem[] {
  const cached = itemCache.get(rep);
  if (cached) return cached;
  const items = allItems([rep]);
  itemCache.set(rep, items);
  return items;
}


/** "rep_x#key" → ["rep_x", "key"]. A position key has no "#" in it. */
function splitCardId(id: string): [string, string] {
  const at = id.indexOf('#');
  return at < 0 ? [id, ''] : [id.slice(0, at), id.slice(at + 1)];
}
