import { applySan, positionKey, walkSan } from '../chess/core';
import { lookup, type ReferenceIndex } from './reference';
import { ancestorsOf, type OpeningNode, type OpeningTree } from './openingTree';
import {
  beginRun,
  opponentReply,
  regionSource,
  type ClockMode,
  type ColorChoice,
  type LineSource,
  type Run,
  type Weakness,
} from './openingRun';
import type { Hole } from './growth';
import type { Seen } from './freshness';
import type { Repertoire } from './types';

/**
 * Survival: how far you get before your first blunder.
 *
 * A run starts at move one, goes through your prep and keeps going as a real
 * game once the prep runs out. Nothing ends it but a blunder, mate or a draw.
 * Where your prep has an answer and you play something else that is still
 * sound, that is a miss: it is logged for Autopilot's review and shown in the
 * moment, and the run carries on with the move you played.
 *
 * Survival is its own mode. It borrows the way a Run draws its line and the
 * opponent's book replies, but it never rates an opening, never adds to the
 * repertoire, and never writes into Run's or Autopilot's record: what it keeps
 * is the number of moves you survived, per opening.
 */

/* ── options ────────────────────────────────────────────────────────────── */

/**
 * What the opponent steers toward.
 *
 *   lines — into your prep, tilted toward the lines you miss most.
 *   gaps  — to a reply you have no answer to, and on past it.
 *   book  — the book by popularity from move one, blind to your prep.
 */
export type SurvivalSteer = 'lines' | 'gaps' | 'book';

export const SURVIVAL_STEERS: SurvivalSteer[] = ['lines', 'gaps', 'book'];

export function survivalSteerLabel(steer: SurvivalSteer): string {
  switch (steer) {
    case 'gaps':
      return 'My gaps';
    case 'book':
      return 'Ignore my lines';
    default:
      return 'My lines';
  }
}

export interface SurvivalPrefs {
  steer: SurvivalSteer;
  clock: ClockMode;
  /** What each of your engine-judged moves cost, floated up from its square. */
  moveScores: boolean;
  /** A tint around the board for who is better, in place of an eval bar. */
  boardGlow: boolean;
}

export const DEFAULT_SURVIVAL: SurvivalPrefs = { steer: 'lines', clock: 'off', moveScores: true, boardGlow: true };

/* ── feedback ───────────────────────────────────────────────────────────── */

/** How a move's score reads: green for eval gained, yellow or red for eval lost. */
export type ScoreTone = 'up' | 'slight' | 'bad';

/** How much you can give back and still read yellow rather than red. */
export const SCORE_SLIGHT = 40;

/**
 * The popup for one of your moves, from the eval swing it closed on, in
 * centipawns from your side: the change since your last scored move, the
 * opponent's reply included. So the popups add up to where the game stands.
 * Null when there is nothing worth showing: a zero is noise.
 */
export function moveScore(swing: number): { cp: number; tone: ScoreTone } | null {
  const cp = Math.round(swing);
  if (cp === 0) return null;
  if (cp > 0) return { cp, tone: 'up' };
  return { cp, tone: -cp <= SCORE_SLIGHT ? 'slight' : 'bad' };
}

/** The swing between two engine scores in White's frame, from your side; null across a mate. */
export function evalSwing(color: 'w' | 'b', from: number, to: number): number | null {
  if (Math.abs(from) >= 10_000 || Math.abs(to) >= 10_000) return null;
  return color === 'w' ? to - from : from - to;
}

/**
 * Who is better, as the board's glow shows it: nothing while it is level,
 * green once you are a pawn up and brighter the further ahead, yellow once
 * you are a pawn down, red once you are a minor piece down and brighter the
 * further behind.
 */
export interface Glow {
  tone: 'green' | 'yellow' | 'red';
  /**
   * 0..1, how bright. Green grows from 0; yellow holds at half; red grows
   * from half, so it never starts dimmer than the yellow before it.
   */
  strength: number;
}

/** A pawn, where the glow first shows either way, in centipawns. */
export const GLOW_PAWN = 100;
/** A minor piece down, where yellow turns red. */
export const GLOW_MINOR = 300;
/** How far past where it starts green or red reaches full brightness. */
export const GLOW_SPAN = 400;

/** The glow for a position, from the engine's score in White's frame, or null when level. */
export function glowFor(color: 'w' | 'b', cp: number): Glow | null {
  const mine = color === 'w' ? cp : -cp;
  if (mine >= GLOW_PAWN) {
    return { tone: 'green', strength: Math.min(1, (mine - GLOW_PAWN) / GLOW_SPAN) };
  }
  if (mine <= -GLOW_MINOR) return { tone: 'red', strength: 0.5 + 0.5 * Math.min(1, (-mine - GLOW_MINOR) / GLOW_SPAN) };
  if (mine <= -GLOW_PAWN) return { tone: 'yellow', strength: 0.5 };
  return null;
}

/* ── a run ──────────────────────────────────────────────────────────────── */

/** A prepared position answered with a different, sound move. */
export interface Miss {
  /** The ply the move was played at: `played[ply]` is your move. */
  ply: number;
  /** The position you were asked about. */
  fen: string;
  played: string;
  expected: string;
}

export interface SurvivalRun {
  /**
   * The board and the line being steered toward. Only the parts of a Run
   * that say where the game is are read: fen, played, colour, the drawn
   * target and the way in played for you.
   */
  run: Run;
  /** Your own moves so far, every one the referee passed. The score. */
  moves: number;
  misses: Miss[];
}

export interface SurvivalStart {
  source: LineSource;
  state: SurvivalRun;
  /** Draw a new line from where the run has got to, by the same steer. */
  redraw: (run: Run) => Run;
}

export interface StartOptions {
  steer: SurvivalSteer;
  tree: OpeningTree;
  reps: Repertoire[];
  node: OpeningNode;
  color: ColorChoice;
  weakness?: Weakness | null;
  growth?: { minShare?: number; maxPly?: number };
  holeWeight?: (hole: Hole) => number;
  seen?: Seen;
  seed?: number;
  /**
   * What My lines tilts toward: the lines you would meet most, or the ones
   * you answer worst. Autopilot chooses; a run from the setup screen leans
   * on your weak spots.
   */
  lean?: 'popular' | 'weak';
  /** An opening inside the region to walk toward — see `BeginOptions.toward`. */
  toward?: OpeningNode;
  /** Start inside `toward` rather than from move one — see `BeginOptions.enter`. */
  enter?: boolean;
}

/**
 * Open a run. My lines and My gaps draw the opponent's line the way a Run's
 * weak-spot and gap steers do. Ignore my lines draws on the book alone, with
 * your prep kept only to know where you missed.
 */
export function startSurvival(opts: StartOptions): SurvivalStart | null {
  const blind = opts.steer === 'book';
  const begun = beginRun({
    tree: opts.tree,
    reps: blind ? [] : opts.reps,
    node: opts.node,
    color: opts.color,
    steer: opts.steer === 'gaps' ? 'gaps' : (opts.lean ?? 'weak'),
    toward: opts.toward,
    enter: opts.enter,
    weakness: opts.weakness ?? null,
    growth: opts.growth,
    holeWeight: opts.holeWeight,
    seen: opts.seen,
    seed: opts.seed,
    newMoves: 0,
    hints: 0,
    clock: 'off',
  });
  if (!begun) return null;
  let source = begun.source;
  if (blind) {
    // The opponent knows nothing of your prep, but the referee still does.
    const side = begun.run.color;
    const rep = opts.reps.find((r) => r.color === side) ?? null;
    source = { ...begun.source, prepAt: regionSource(opts.tree, opts.node, rep, side).prepAt };
    begun.run.repertoireId = rep?.id;
  }
  return { source, state: { run: begun.run, moves: 0, misses: [] }, redraw: begun.redraw };
}

/** Your prep's answers here, best first; empty where it says nothing. */
export function prepHere(source: LineSource, state: SurvivalRun): string[] {
  return source.prepAt(state.run.fen);
}

/**
 * One of your moves, passed by your prep or by the engine. A miss is the
 * prepared move you did not play, logged on the run for the end screen.
 */
export function playYours(state: SurvivalRun, san: string, missed?: string): SurvivalRun {
  const { run } = state;
  const move = applySan(run.fen, san);
  if (!move) return state;
  const target = run.target[run.played.length] === san ? run.target : [];
  return {
    run: { ...run, fen: move.after, played: [...run.played, san], survived: run.survived + 1, target },
    moves: state.moves + 1,
    misses: missed
      ? [...state.misses, { ply: run.played.length, fen: run.fen, played: san, expected: missed }]
      : state.misses,
  };
}

/**
 * The opponent's reply from the book, when there is one: inside the opening,
 * the line being steered toward and then the region's moves by popularity;
 * outside it, the whole book by popularity. Null once the book has nothing,
 * which is where the engine takes over.
 */
export function bookReply(
  source: LineSource,
  index: ReferenceIndex,
  state: SurvivalRun,
  rand: () => number,
): string | null {
  const { run } = state;
  if (source.weightsAt(run.fen, run.played).length) {
    const next = opponentReply(source, run, rand);
    return next.played.length > run.played.length ? next.played[next.played.length - 1] : null;
  }
  const book = lookup(index, run.fen)?.moves ?? [];
  const total = book.reduce((sum, move) => sum + Math.max(0, move.games), 0);
  if (!book.length || total <= 0) return null;
  let roll = rand() * total;
  for (const move of book) {
    roll -= Math.max(0, move.games);
    if (roll <= 0) return move.san;
  }
  return book[book.length - 1].san;
}

/** The opponent's move, whoever chose it. */
export function playTheirs(state: SurvivalRun, san: string): SurvivalRun {
  const move = applySan(state.run.fen, san);
  if (!move) return state;
  return { ...state, run: { ...state.run, fen: move.after, played: [...state.run.played, san] } };
}

/** The move number a ply is played on, as a score sheet writes it. */
export function moveNumber(ply: number): number {
  return Math.floor(ply / 2) + 1;
}

/* ── the record ─────────────────────────────────────────────────────────── */

/** How many runs recent form is read over. */
export const RECENT_RUNS = 5;
/** How many runs' lengths are kept for Home's chart. */
export const HISTORY_RUNS = 16;

export interface SurvivalScore {
  /** The most moves survived. Only ever goes up. */
  best: number;
  /** The last few runs' moves survived, oldest first. */
  recent: number[];
  /** The last runs' moves survived, oldest first, for Home's chart. Ended runs are not in it. */
  history: number[];
  runs: number;
  /** Runs you ended yourself: counted here and nowhere else. */
  ended: number;
}

export interface SurvivalRecord {
  /** Every run, whatever it went through: the global max. */
  global: SurvivalScore;
  /** Opening tree node id → the runs that went through it. */
  openings: Record<string, SurvivalScore>;
}

export const EMPTY_SURVIVAL_SCORE: SurvivalScore = { best: 0, recent: [], history: [], runs: 0, ended: 0 };

export const EMPTY_SURVIVAL_RECORD: SurvivalRecord = { global: { ...EMPTY_SURVIVAL_SCORE }, openings: {} };

/** A saved record missing a field is still a record. */
export function normalizeSurvival(saved: Partial<SurvivalRecord> | undefined): SurvivalRecord {
  const fix = (score: Partial<SurvivalScore> | undefined): SurvivalScore => ({
    best: score?.best ?? 0,
    recent: (score?.recent ?? []).slice(-RECENT_RUNS),
    // Saves from before the history was kept start it from recent form's runs.
    history: (score?.history ?? score?.recent ?? []).slice(-HISTORY_RUNS),
    runs: score?.runs ?? 0,
    ended: score?.ended ?? 0,
  });
  return {
    global: fix(saved?.global),
    openings: Object.fromEntries(Object.entries(saved?.openings ?? {}).map(([id, score]) => [id, fix(score)])),
  };
}

/**
 * Every opening a line went through: each named position it reached, and
 * every opening above those. A King's Indian run that reaches the Classical
 * counts for both, and for the Indian Defence above them.
 */
export function openingsAlong(tree: OpeningTree, line: string[]): string[] {
  const out = new Set<string>();
  for (const fen of walkSan(line).fens) {
    const node = tree.byKey.get(positionKey(fen));
    if (!node || node.depth === 0) continue;
    for (const above of ancestorsOf(tree, node.id)) out.add(above.id);
  }
  return [...out];
}

function scored(score: SurvivalScore | undefined, moves: number): SurvivalScore {
  const base = score ?? EMPTY_SURVIVAL_SCORE;
  return {
    best: Math.max(base.best, moves),
    recent: [...base.recent, moves].slice(-RECENT_RUNS),
    history: [...base.history, moves].slice(-HISTORY_RUNS),
    runs: base.runs + 1,
    ended: base.ended,
  };
}

function ended(score: SurvivalScore | undefined): SurvivalScore {
  const base = score ?? EMPTY_SURVIVAL_SCORE;
  return { ...base, ended: base.ended + 1 };
}

/** Log a finished run against the global record and every opening it went through. */
export function recordSurvival(
  record: SurvivalRecord,
  tree: OpeningTree,
  line: string[],
  moves: number,
): SurvivalRecord {
  const openings = { ...record.openings };
  for (const id of openingsAlong(tree, line)) openings[id] = scored(openings[id], moves);
  return { global: scored(record.global, moves), openings };
}

/**
 * Log a run you ended yourself: a count against the global record and every
 * opening it went through, and nothing toward best or recent form.
 */
export function recordEndedSurvival(record: SurvivalRecord, tree: OpeningTree, line: string[]): SurvivalRecord {
  const openings = { ...record.openings };
  for (const id of openingsAlong(tree, line)) openings[id] = ended(openings[id]);
  return { global: ended(record.global), openings };
}

/** Recent form: the median of the last few runs, or null before any. */
export function recentForm(score: SurvivalScore | undefined): number | null {
  const recent = score?.recent ?? [];
  if (!recent.length) return null;
  const sorted = [...recent].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : Math.round((sorted[mid - 1] + sorted[mid]) / 2);
}

/** The score for an opening, or the global one for the root. */
export function survivalFor(record: SurvivalRecord, id: string): SurvivalScore {
  return id === '' ? record.global : (record.openings[id] ?? EMPTY_SURVIVAL_SCORE);
}
