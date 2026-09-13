import type { Color } from '../chess/core';
import type { OpeningRunPrefs } from './openingRun';
import type { DrillPrefs, GrowthPrefs, PlayPrefs, RepairPrefs } from './modes';
import type { Selection } from './selection';

export type MoveSource = 'seed' | 'manual' | 'reference' | 'pgn' | 'games';

/** A single move edge in the repertoire tree. */
export interface RepMove {
  id: string;
  parentId: string | null;
  repertoireId: string;
  /** FEN of the position this move is played from. */
  fenBefore: string;
  /** positionKey(fenBefore) — used to collapse transpositions. */
  key: string;
  san: string;
  uci: string;
  fenAfter: string;
  children: string[];
  /** The preferred continuation among siblings (used as "your move" in training). */
  preferred: boolean;
  note?: string;
  source: MoveSource;
  addedAt: number;
}

export interface Repertoire {
  id: string;
  name: string;
  /** The side the user plays in this repertoire. */
  color: Color;
  rootFen: string;
  rootChildren: string[];
  nodes: Record<string, RepMove>;
  createdAt: number;
}

export type CardStage = 'new' | 'learning' | 'review';

/** Spaced-repetition state for one repertoire decision point. */
export interface Card {
  id: string;
  repertoireId: string;
  /** positionKey of the position the user must answer from. */
  key: string;
  fen: string;
  stage: CardStage;
  /** Index into the learning steps ladder while stage === 'learning'. */
  step: number;
  /** Current interval in days (review stage only). */
  interval: number;
  ease: number;
  reps: number;
  lapses: number;
  correct: number;
  incorrect: number;
  due: number;
  lastReviewed: number | null;
  createdAt: number;
}

export type Grade = 'again' | 'hard' | 'good' | 'easy';

export interface ReviewLogEntry {
  cardId: string;
  at: number;
  grade: Grade;
  correct: boolean;
  playedSan: string | null;
  expectedSan: string;
  intervalBefore: number;
  intervalAfter: number;
}

/** One move row in the reference/opening explorer. */
export interface ExplorerMove {
  san: string;
  games: number;
  white: number;
  draw: number;
  black: number;
  /** Centipawn-ish evaluation hint from reference data, if known. */
  eval?: number;
}

export interface ExplorerEntry {
  key: string;
  opening?: string;
  eco?: string;
  moves: ExplorerMove[];
  topGames?: ReferenceGame[];
}

export interface ReferenceGame {
  white: string;
  black: string;
  result: string;
  year: number;
  event?: string;
  /** SAN moves from the standard start position. */
  moves: string[];
}

/** A named book line the user can inspect and import. */
export interface BookLine {
  id: string;
  name: string;
  eco?: string;
  /** Which side the line is "for" — helps sort into the right repertoire. */
  forColor: Color;
  /** SAN moves from the standard start position. */
  moves: string[];
  summary: string;
  /** Free-text ideas, shown when inspecting the line. */
  ideas?: string[];
  tags?: string[];
}

export interface ImportedGame {
  id: string;
  source: 'lichess' | 'chesscom' | 'pgn';
  white: string;
  black: string;
  result: string;
  /** The colour the importing user played, when known. */
  userColor: Color | null;
  timeControl?: string;
  date?: string;
  opening?: string;
  moves: string[];
  url?: string;
}

/**
 * App-wide settings: the board, the device, the account.
 *
 * Nothing here changes how a mode plays. Each mode keeps its own options under
 * its own key, edited on that mode's setup screen.
 */
export interface Settings {
  showCoordinates: boolean;
  engineEnabled: boolean;
  boardTheme: 'slate' | 'walnut' | 'ocean';
  hapticFeedback: boolean;
  lichessUsername: string;
  chesscomUsername: string;
  /** Opt in to copying state to your Claude account for other devices. */
  cloudSync: boolean;
  /** Which side, and which region of the opening tree, every mode works in. */
  selection: Selection;
  /** Starred opening tree nodes, by id — the move order that defines each. */
  favoriteOpenings: string[];
  openingRun: OpeningRunPrefs;
  drill: DrillPrefs;
  repair: RepairPrefs;
  play: PlayPrefs;
  growth: GrowthPrefs;
}
