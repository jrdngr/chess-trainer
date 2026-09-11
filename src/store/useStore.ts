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
  repertoires: Record<string, Repertoire>;
  repertoireOrder: string[];
  cards: Record<string, Card>;
  log: ReviewLogEntry[];
  settings: Settings;
  importedGames: ImportedGame[];
}

interface StoreState extends PersistedState {
  ready: boolean;
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
    repertoires: state.repertoires,
    repertoireOrder: state.repertoireOrder,
    cards: state.cards,
    log: state.log,
    settings: state.settings,
    importedGames: state.importedGames,
  };
}

const persist = debounce((state: StoreState) => {
  void saveState(persistedFrom(state));
}, 250);

export const useStore = create<StoreState>((set, get) => {
  const commit = (patch: Partial<StoreState>) => {
    set(patch);
    persist(get());
  };

  const updateRep = (repId: string, fn: (rep: Repertoire) => Repertoire) => {
    const rep = get().repertoires[repId];
    if (!rep) return;
    commit({ repertoires: { ...get().repertoires, [repId]: fn(rep) } });
  };

  return {
    ...emptyPersisted(),
    ready: false,

    async init() {
      const saved = await loadState<PersistedState>();
      if (saved?.repertoires && saved.version === SCHEMA_VERSION) {
        set({
          ...saved,
          settings: { ...DEFAULT_SETTINGS, ...saved.settings },
          ready: true,
        });
        return;
      }
      // No saved state, or it predates the current seed data: start fresh but
      // keep whatever settings the user had chosen.
      set({
        ...emptyPersisted(),
        settings: { ...DEFAULT_SETTINGS, ...(saved?.settings ?? {}) },
        ready: true,
      });
      persist(get());
    },

    async resetAll() {
      await clearState();
      set({ ...emptyPersisted(), ready: true });
      persist(get());
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
