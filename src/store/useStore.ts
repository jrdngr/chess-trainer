import { create } from 'zustand';
import { positionKey, type Color } from '../chess/core';
import {
  addLine,
  createRepertoire,
  moveSibling,
  removeSubtree,
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
  DEFAULT_GAP,
  DEFAULT_PUNISH,
  EMPTY_PUNISH_RECORD,
  normalizePunishRecord,
  recordPunish,
  type PunishRecord,
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
import { cloudAvailable, readCloud, writeCloud, type CloudStatus, type WriteResult } from './cloud';
import { clearState, debounce, loadState, probeStorage, saveState, type StorageSupport } from './db';
import { buildSeedRepertoires } from './seed';

export const DEFAULT_SETTINGS: Settings = {
  showCoordinates: true,
  engineEnabled: true,
  boardTheme: 'slate',
  hapticFeedback: true,
  lichessUsername: '',
  chesscomUsername: '',
  cloudSync: true,
  favoriteOpenings: [],
  openingRun: { ...DEFAULT_PREFS },
  drill: { ...DEFAULT_DRILL },
  punish: { ...DEFAULT_PUNISH },
  gap: { ...DEFAULT_GAP },
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
    openingRun: { ...DEFAULT_PREFS, ...known.openingRun },
    drill: { ...DEFAULT_DRILL, ...known.drill },
    punish: { ...DEFAULT_PUNISH, ...known.punish },
    gap: { ...DEFAULT_GAP, ...known.gap },
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
 */
export const SCHEMA_VERSION = 5;

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
  punish: PunishRecord;
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

  grade: (item: TrainingItem, grade: Grade, playedSan: string | null, correct: boolean) => void;
  ensureCard: (item: TrainingItem) => Card;

  setSettings: (patch: Partial<Settings>) => void;
  setOpeningRunPrefs: (patch: Partial<OpeningRunPrefs>) => void;
  /** Patch one mode's own options, without touching the rest of settings. */
  setModePrefs: <K extends 'drill' | 'punish' | 'gap'>(
    mode: K,
    patch: Partial<Settings[K]>,
  ) => void;
  setImportedGames: (games: ImportedGame[]) => void;

  /** Log a finished openingRun run, globally and against its own opening. */
  endOpeningRun: (outcome: RunOutcome) => void;
  /** Log one Punish puzzle, solved or missed. */
  endPunish: (solved: boolean) => void;
  /**
   * The move that ended a run. Only the miss touches the schedule: correct
   * moves in a run are primed by the ones before them, so crediting them would
   * inflate intervals on evidence weaker than an isolated review.
   */
  missedInOpeningRun: (repertoireId: string, fen: string, played: string, expected: string) => void;
}

function emptyPersisted(): PersistedState {
  const reps = buildSeedRepertoires();
  return {
    version: SCHEMA_VERSION,
    updatedAt: Date.now(),
    repertoires: Object.fromEntries(reps.map((r) => [r.id, r])),
    repertoireOrder: reps.map((r) => r.id),
    cards: {},
    log: [],
    settings: { ...DEFAULT_SETTINGS },
    importedGames: [],
    openingRun: { ...EMPTY_RECORD },
    punish: { ...EMPTY_PUNISH_RECORD },
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
    punish: state.punish,
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
          punish: normalizePunishRecord(chosen.punish),
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
        // Nothing anywhere, or a save that predates the current seed data.
        set({
          ...emptyPersisted(),
          settings: mergeSettings(saved?.settings),
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
          punish: normalizePunishRecord(remote.state.punish),
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
      updateRep(repId, (rep) => removeSubtree(rep, nodeId));
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
      commit(reviewed(state, card, gradeValue, { correct, playedSan, expectedSan }));
    },

    setSettings(patch) {
      commit({ settings: { ...get().settings, ...patch } });
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

    endPunish(solved) {
      commit({ punish: recordPunish(get().punish, solved) });
    },

    missedInOpeningRun(repertoireId, fen, played, expected) {
      const key = positionKey(fen);
      const id = cardId(repertoireId, key);
      const state = get();
      const card = state.cards[id] ?? createCard(id, repertoireId, key, fen);
      commit(reviewed(state, card, 'again', { correct: false, playedSan: played, expectedSan: expected }));
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

