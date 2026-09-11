import { create } from 'zustand';
import type { Color } from '../chess/core';
import {
  addLine,
  createRepertoire,
  moveSibling,
  removeSubtree,
  setNote,
  setPreferred,
} from '../model/repertoire';
import { allItems, branchItems, cardId, type TrainingItem } from '../model/session';
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
import { cloudAvailable, readCloud, writeCloud, type CloudStatus } from './cloud';
import { clearState, debounce, loadState, saveState } from './db';
import { buildSeedRepertoires } from './seed';

export const DEFAULT_SETTINGS: Settings = {
  boardOrientationFollowsRepertoire: true,
  showCoordinates: true,
  engineEnabled: true,
  showEvalInTraining: false,
  newCardsPerSession: 8,
  maxSessionLength: 25,
  playOpponentReplies: true,
  confirmMoves: false,
  pieceSet: 'classic',
  boardTheme: 'slate',
  hapticFeedback: true,
  lichessUsername: '',
  chesscomUsername: '',
};

/**
 * Bump when the seeded repertoires change shape or content. A saved state from
 * an older schema is discarded rather than migrated — this is a prototype, and
 * the seed data is the thing most likely to change.
 */
export const SCHEMA_VERSION = 3;

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
}

interface StoreState extends PersistedState {
  ready: boolean;
  cloud: CloudStatus;
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
  renameRepertoire: (repId: string, name: string) => void;
  deleteRepertoire: (repId: string) => void;

  grade: (item: TrainingItem, grade: Grade, playedSan: string | null, correct: boolean) => void;
  ensureCard: (item: TrainingItem) => Card;
  forgetCards: (keys: string[]) => void;

  setSettings: (patch: Partial<Settings>) => void;
  setImportedGames: (games: ImportedGame[]) => void;
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

export const useStore = create<StoreState>((set, get) => {
  /** Push to the cloud well after the user stops interacting. */
  const pushCloud = debounce(() => {
    const state = get();
    if (state.cloud.kind === 'unavailable') return;
    set({ cloud: { kind: 'syncing' } });
    void writeCloud(syncableFrom(state), state.updatedAt).then((result) => {
      if (result.ok) set({ cloud: { kind: 'synced', lastSyncedAt: Date.now() } });
      else if (result.reason === 'unavailable') set({ cloud: { kind: 'unavailable' } });
      else if (result.reason === 'too-large') set({ cloud: { kind: 'too-large', bytes: result.bytes ?? 0 } });
      else set({ cloud: { kind: 'error', message: result.message ?? 'Sync failed' } });
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

    async init() {
      const saved = await loadState<PersistedState>();
      if (saved?.repertoires && saved.version === SCHEMA_VERSION) {
        set({
          ...saved,
          updatedAt: saved.updatedAt ?? Date.now(),
          settings: { ...DEFAULT_SETTINGS, ...saved.settings },
          ready: true,
        });
      } else {
        // No saved state, or it predates the current seed data: start fresh
        // but keep whatever settings the user had chosen.
        set({
          ...emptyPersisted(),
          settings: { ...DEFAULT_SETTINGS, ...(saved?.settings ?? {}) },
          ready: true,
        });
        persist(get());
      }
      // Then catch up with another device, if there is one. The page is already
      // interactive by this point; sync never blocks the first paint.
      await get().syncNow();
    },

    async syncNow() {
      if (!cloudAvailable()) {
        set({ cloud: { kind: 'unavailable' } });
        return;
      }
      set({ cloud: { kind: 'syncing' } });
      const remote = await readCloud<PersistedState>();
      const local = get();

      if (remote && remote.state.version === SCHEMA_VERSION && remote.updatedAt > local.updatedAt) {
        // Another device is ahead. Whole-state last-write-wins: right for one
        // person on two devices, and honest about not merging concurrent edits.
        set({
          ...remote.state,
          importedGames: local.importedGames,
          settings: { ...DEFAULT_SETTINGS, ...remote.state.settings },
          updatedAt: remote.updatedAt,
          ready: true,
          cloud: { kind: 'synced', lastSyncedAt: Date.now() },
        });
        persist(get());
        return;
      }

      const result = await writeCloud(syncableFrom(get()), get().updatedAt);
      if (result.ok) set({ cloud: { kind: 'synced', lastSyncedAt: Date.now() } });
      else if (result.reason === 'unavailable') set({ cloud: { kind: 'unavailable' } });
      else if (result.reason === 'too-large') set({ cloud: { kind: 'too-large', bytes: result.bytes ?? 0 } });
      else set({ cloud: { kind: 'error', message: result.message ?? 'Sync failed' } });
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

    renameRepertoire(repId, name) {
      updateRep(repId, (rep) => ({ ...rep, name }));
    },

    deleteRepertoire(repId) {
      const { [repId]: _removed, ...rest } = get().repertoires;
      const cards = Object.fromEntries(
        Object.entries(get().cards).filter(([, c]) => c.repertoireId !== repId),
      );
      commit({
        repertoires: rest,
        repertoireOrder: get().repertoireOrder.filter((id) => id !== repId),
        cards,
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
      const card = state.cards[item.cardId] ?? createCard(item.cardId, item.repertoireId, item.key, item.fen);
      const now = Date.now();
      const { card: next } = review(card, gradeValue, now);
      const entry: ReviewLogEntry = {
        cardId: item.cardId,
        at: now,
        grade: gradeValue,
        correct,
        playedSan,
        expectedSan: item.expected.find((e) => e.preferred)?.san ?? item.expected[0]?.san ?? '',
        intervalBefore: card.interval,
        intervalAfter: next.interval,
      };
      commit({
        cards: { ...state.cards, [item.cardId]: next },
        log: [...state.log.slice(-499), entry],
      });
    },

    forgetCards(keys) {
      const cards = { ...get().cards };
      for (const key of keys) delete cards[key];
      commit({ cards });
    },

    setSettings(patch) {
      commit({ settings: { ...get().settings, ...patch } });
    },

    setImportedGames(games) {
      commit({ importedGames: games });
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

export function allTrainingItems(state: StoreState): TrainingItem[] {
  return repertoireList(state).flatMap(itemsFor);
}

export function itemsForBranch(rep: Repertoire, nodeId: string): TrainingItem[] {
  return branchItems(rep, nodeId);
}

export function cardFor(state: StoreState, item: TrainingItem): Card | undefined {
  return state.cards[item.cardId];
}

export { cardId };
