import { create } from 'zustand';
import { positionKey, type Color } from '../chess/core';
import {
  addLine,
  createRepertoire,
  moveSibling,
  pruneLine,
  removeSubtree,
  repertoireName,
  setNote,
  setPreferred,
} from '../model/repertoire';
import { allItems, cardId, type TrainingItem } from '../model/session';
import { createCard, review } from '../model/srs';
import type {
  Card,
  Grade,
  ImportedGame,
  MoveSource,
  Repertoire,
  ReviewLogEntry,
  Settings,
} from '../model/types';
import {
  DEFAULT_DRILL,
  DEFAULT_GROWTH,
  DEFAULT_PLAY,
  DEFAULT_REPAIR,
  EMPTY_REPAIR_RECORD,
  normalizeRepairRecord,
  recordRepair,
  type RepairRecord,
} from '../model/modes';
import {
  DEFAULT_PREFS,
  EMPTY_RECORD,
  normalizeRecord,
  recordRun,
  type OpeningRunPrefs,
  type OpeningRunRecord,
  type RunOutcome,
} from '../model/openingRun';
import { addMistake, type Mistake } from '../model/mistakes';
import { DEFAULT_SELECTION, type Selection } from '../model/selection';
import {
  NO_ACTIVITY,
  normalizeActivity,
  noted,
  type Activity,
  type ActivityMode,
} from '../model/nextUp';
import { cloudAvailable, readCloud, writeCloud, type CloudStatus, type WriteResult } from './cloud';
import { clearState, debounce, loadState, probeStorage, saveState, type StorageSupport } from './db';

export const DEFAULT_SETTINGS: Settings = {
  showCoordinates: true,
  engineEnabled: true,
  boardTheme: 'slate',
  hapticFeedback: true,
  lichessUsername: '',
  chesscomUsername: '',
  cloudSync: true,
  selection: { ...DEFAULT_SELECTION },
  favoriteOpenings: [],
  openingRun: { ...DEFAULT_PREFS },
  drill: { ...DEFAULT_DRILL },
  repair: { ...DEFAULT_REPAIR },
  play: { ...DEFAULT_PLAY },
  growth: { ...DEFAULT_GROWTH },
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
    openingRun: { ...DEFAULT_PREFS, ...known.openingRun },
    drill: { ...DEFAULT_DRILL, ...known.drill },
    repair: { ...DEFAULT_REPAIR, ...known.repair },
    play: { ...DEFAULT_PLAY, ...known.play },
    growth: { ...DEFAULT_GROWTH, ...known.growth },
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

interface PersistedState {
  version: number;
  /** When this state was last changed, used to resolve device conflicts. */
  updatedAt: number;
  repertoires: Record<string, Repertoire>;
  repertoireOrder: string[];
  cards: Record<string, Card>;
  log: ReviewLogEntry[];
  settings: Settings;
  importedGames: ImportedGame[];
  openingRun: OpeningRunRecord;
  repair: RepairRecord;
  /** Mistakes made inside the app, for Repair to ask about later. */
  mistakes: Mistake[];
  /** When each mode last did something, for Next Up to rotate on. */
  activity: Activity;
}

interface StoreState extends PersistedState {
  ready: boolean;
  cloud: CloudStatus;
  /** Which persistence backends actually work on this page. */
  storage: StorageSupport;
  syncNow: () => Promise<void>;
  init: () => Promise<void>;
  resetAll: () => Promise<void>;
  resetProgress: () => void;

  addLine: (repId: string, sans: string[], source: MoveSource) => { added: number };
  removeNode: (repId: string, nodeId: string) => void;
  preferMove: (repId: string, nodeId: string) => void;
  annotate: (repId: string, nodeId: string, note: string) => void;
  reorder: (repId: string, nodeId: string, delta: number) => void;
  addRepertoire: (name: string, color: Color) => string;
  /** The tree for one side, created if this is the first line for it. */
  ensureRepertoire: (color: Color) => string;
  /**
   * Delete a derived opening: the region, and the move order that only led to
   * it. `rootId` is the opening's own root node.
   */
  removeOpening: (repId: string, rootId: string) => void;
  /** Delete one side's tree outright, with everything that only existed for it. */
  removeRepertoire: (repId: string) => void;

  grade: (item: TrainingItem, grade: Grade, playedSan: string | null, correct: boolean) => void;
  ensureCard: (item: TrainingItem) => Card;

  setSettings: (patch: Partial<Settings>) => void;
  setSelection: (patch: Partial<Selection>) => void;
  toggleStar: (openingId: string) => void;
  setOpeningRunPrefs: (patch: Partial<OpeningRunPrefs>) => void;
  /** Patch one mode's own options, without touching the rest of settings. */
  setModePrefs: <K extends 'drill' | 'repair' | 'growth' | 'play'>(
    mode: K,
    patch: Partial<Settings[K]>,
  ) => void;
  setImportedGames: (games: ImportedGame[]) => void;

  /** Log a finished openingRun run, globally and against its own opening. */
  endOpeningRun: (outcome: RunOutcome) => void;
  /** Log one Repair item: answered correctly, or given a move. */
  endRepair: (outcome: { relearned?: boolean; added?: boolean }) => void;
  /**
   * Remember that a mode was just used, for Next Up's rotation.
   *
   * Drill and Repair stamp themselves from the actions that already record
   * their work, so only Growth — which has no record of its own — calls this.
   */
  noteActivity: (mode: ActivityMode) => void;
  /** Remember a move the user got wrong somewhere in the app. */
  logMistake: (mistake: Omit<Mistake, 'id' | 'at'>) => void;
  /** Forget one, once it has been repaired. */
  clearMistake: (id: string) => void;
  /**
   * The move that ended a run. Only the miss touches the schedule: correct
   * moves in a run are primed by the ones before them, so crediting them would
   * inflate intervals on evidence weaker than an isolated review.
   */
  missedInOpeningRun: (repertoireId: string, fen: string, played: string, expected: string) => void;
  /**
   * An answer given in Repair. Unlike a run, this is one isolated position with
   * nothing priming it, so it is worth the same as a review: right earns a
   * normal pass, wrong is a lapse.
   */
  repairedPosition: (
    repertoireId: string,
    fen: string,
    played: string,
    expected: string,
    correct: boolean,
  ) => void;
}

/**
 * A new install has no repertoires at all.
 *
 * Seeded lines made the first screen look busy, but they were somebody else's
 * openings: Drill asked about a Queen's Gambit nobody had chosen, and Repair
 * compared real games against prep the player had never agreed to. You now
 * build the repertoire by playing — Play saves the openings from your games,
 * Opening Run adds the lines you survive, and Growth fills what they leave out.
 */
function emptyPersisted(): PersistedState {
  return {
    version: SCHEMA_VERSION,
    updatedAt: Date.now(),
    repertoires: {},
    repertoireOrder: [],
    cards: {},
    log: [],
    settings: { ...DEFAULT_SETTINGS },
    importedGames: [],
    openingRun: { ...EMPTY_RECORD },
    repair: { ...EMPTY_REPAIR_RECORD },
    mistakes: [],
    activity: { ...NO_ACTIVITY },
  };
}

function persistedFrom(state: StoreState): PersistedState {
  return {
    version: SCHEMA_VERSION,
    updatedAt: state.updatedAt,
    repertoires: state.repertoires,
    repertoireOrder: state.repertoireOrder,
    cards: state.cards,
    log: state.log,
    settings: state.settings,
    importedGames: state.importedGames,
    openingRun: state.openingRun,
    repair: state.repair,
    mistakes: state.mistakes,
    activity: state.activity,
  };
}

/**
 * What goes to the cloud. Imported games are left out deliberately: they are
 * bulky, re-importable, and the payload has to stay under a 256 KiB document.
 */
function syncableFrom(state: StoreState): PersistedState {
  return { ...persistedFrom(state), importedGames: [] };
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

  const updateRep = (repId: string, fn: (rep: Repertoire) => Repertoire) => {
    const rep = get().repertoires[repId];
    if (!rep) return;
    commit({ repertoires: { ...get().repertoires, [repId]: fn(rep) } });
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
  const shrinkRep = (repId: string, fn: (rep: Repertoire) => Repertoire) => {
    const state = get();
    const rep = state.repertoires[repId];
    if (!rep) return;
    const next = fn(rep);
    const alive = new Set(Object.values(next.nodes).map((node) => node.key));
    const orphaned = (id: string, key: string) => id === repId && !alive.has(key);
    commit({
      repertoires: { ...state.repertoires, [repId]: next },
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

  return {
    ...emptyPersisted(),
    ready: false,
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
          openingRun: normalizeRecord(chosen.openingRun),
          repair: normalizeRepairRecord(chosen.repair),
          mistakes: chosen.mistakes ?? [],
          activity: normalizeActivity(chosen.activity),
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
          openingRun: normalizeRecord(remote.state.openingRun),
          repair: normalizeRepairRecord(remote.state.repair),
          mistakes: remote.state.mistakes ?? [],
          activity: normalizeActivity(remote.state.activity),
          importedGames: local.importedGames,
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
      commit({ cards: {}, log: [] });
    },

    addLine(repId, sans, source) {
      const rep = get().repertoires[repId];
      if (!rep) return { added: 0 };
      const res = addLine(rep, sans, source);
      commit({ repertoires: { ...get().repertoires, [repId]: res.rep } });
      return { added: res.added };
    },

    removeNode(repId, nodeId) {
      shrinkRep(repId, (rep) => removeSubtree(rep, nodeId));
    },

    removeOpening(repId, rootId) {
      shrinkRep(repId, (rep) => pruneLine(rep, rootId));
    },

    preferMove(repId, nodeId) {
      updateRep(repId, (rep) => setPreferred(rep, nodeId));
    },

    annotate(repId, nodeId, note) {
      updateRep(repId, (rep) => setNote(rep, nodeId, note));
    },

    reorder(repId, nodeId, delta) {
      updateRep(repId, (rep) => moveSibling(rep, nodeId, delta));
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
      delete repertoires[repId];
      commit({
        repertoires,
        repertoireOrder: state.repertoireOrder.filter((id) => id !== repId),
        cards: Object.fromEntries(
          Object.entries(state.cards).filter(([, card]) => card.repertoireId !== repId),
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
        activity: noted(state.activity, 'drill'),
      });
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
      commit({ settings: { ...settings, favoriteOpenings: starred } });
    },

    setOpeningRunPrefs(patch) {
      const settings = get().settings;
      commit({ settings: { ...settings, openingRun: { ...settings.openingRun, ...patch } } });
    },

    setModePrefs(mode, patch) {
      const settings = get().settings;
      commit({ settings: { ...settings, [mode]: { ...settings[mode], ...patch } } });
    },

    setImportedGames(games) {
      commit({ importedGames: games });
    },

    endOpeningRun(outcome) {
      commit({ openingRun: recordRun(get().openingRun, outcome) });
    },

    endRepair(outcome) {
      commit({
        repair: recordRepair(get().repair, outcome),
        activity: noted(get().activity, 'repair'),
      });
    },

    noteActivity(mode) {
      commit({ activity: noted(get().activity, mode) });
    },

    logMistake(mistake) {
      commit({ mistakes: addMistake(get().mistakes, mistake) });
    },

    clearMistake(id) {
      commit({ mistakes: get().mistakes.filter((m) => m.id !== id) });
    },

    missedInOpeningRun(repertoireId, fen, played, expected) {
      const key = positionKey(fen);
      const id = cardId(repertoireId, key);
      const state = get();
      const card = state.cards[id] ?? createCard(id, repertoireId, key, fen);
      commit({
        ...reviewed(state, card, 'again', { correct: false, playedSan: played, expectedSan: expected }),
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

    repairedPosition(repertoireId, fen, played, expected, correct) {
      const key = positionKey(fen);
      const id = cardId(repertoireId, key);
      const state = get();
      const card = state.cards[id] ?? createCard(id, repertoireId, key, fen);
      commit({
        ...reviewed(state, card, correct ? 'good' : 'again', {
          correct,
          playedSan: played,
          expectedSan: expected,
        }),
        // Getting it right retires the logged mistake; getting it wrong leaves
        // it standing so Repair offers it again.
        mistakes: correct ? state.mistakes.filter((m) => m.key !== key) : state.mistakes,
      });
    },
  };
});

/* ───────────────────────────── selectors ───────────────────────────── */

export function repertoireList(state: StoreState): Repertoire[] {
  return state.repertoireOrder.map((id) => state.repertoires[id]).filter(Boolean);
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
