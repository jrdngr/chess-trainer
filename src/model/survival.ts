import { applySan, piecesFromFen, positionKey, walkSan, type PieceType, type Square } from '../chess/core';
import { goalRoute } from './boardHints';
import { planFor, structureOf } from './structures';
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
  /** Past prep, a pause where one move is far better than the rest: find it for a bonus. */
  moments: boolean;
  /** Past prep, a goal sized to the eval, one after another. */
  missions: boolean;
  /** Moves close to the engine's best build a multiplier on the points each move earns. */
  combo: boolean;
  /** Before your move lands, what it leaves undefended flashes, with a moment to take it back. */
  undefendedFlash: boolean;
}

export const DEFAULT_SURVIVAL: SurvivalPrefs = {
  steer: 'lines',
  clock: 'off',
  moveScores: true,
  boardGlow: true,
  moments: true,
  missions: true,
  combo: true,
  undefendedFlash: false,
};

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

/* ── past the opening: points, moments, missions, combo ─────────────────── */

/**
 * What keeps a run interesting once the prep runs out. Each is a toggle;
 * Autopilot plays with all three on.
 *
 * Every move survived earns a point, times the combo's multiplier, and
 * moments found and missions completed pay bonuses on top. With all three off
 * a run's points are its moves survived. Moves survived stays the record it
 * always was; points are kept beside it.
 */

/** A move within this many centipawns of the engine's best extends the combo. */
export const COMBO_CLEAN = 20;
/** Past clean but within this, the combo holds; worse than this breaks it. */
export const COMBO_HOLD = 40;

/** The combo after a judged move that cost `lost` centipawns against the best. */
export function comboAfter(streak: number, lost: number): number {
  if (lost <= COMBO_CLEAN) return streak + 1;
  if (lost <= COMBO_HOLD) return streak;
  return 0;
}

/** What each move earns at this combo: ×1, then ×2 from 3 in a row, ×3 from 6, ×4 from 10. */
export function comboMultiplier(streak: number): number {
  if (streak >= 10) return 4;
  if (streak >= 6) return 3;
  if (streak >= 3) return 2;
  return 1;
}

/** How far ahead of the second-best move the best must be for a moment. */
export const MOMENT_GAP = 150;
/** Where the best move must leave you, at least, for a moment: a real gain, not an escape. */
export const MOMENT_FLOOR = 100;
/** A move this close to the best finds the moment. */
export const MOMENT_FOUND = 50;
/** A moment found pays this, and each found in a row after it this much more. */
export const MOMENT_BONUS = 10;
export const MOMENT_STREAK_BONUS = 5;

const MATE = 10_000;

/**
 * Whether a position is a moment: the engine's best move, in White's frame,
 * against its second best. A mate the second move does not also have always
 * counts. A position with only one legal move is not a moment.
 */
export function isMoment(color: 'w' | 'b', best: number, second: number | null): boolean {
  if (second === null) return false;
  const top = color === 'w' ? best : -best;
  const next = color === 'w' ? second : -second;
  if (top >= MATE) return next < MATE;
  return top >= MOMENT_FLOOR && top - next >= MOMENT_GAP;
}

/** The bonus for a moment found, with `streak` found in a row before it. */
export function momentBonus(streak: number): number {
  return MOMENT_BONUS + MOMENT_STREAK_BONUS * streak;
}

export type MissionKind = 'edge' | 'lead' | 'dig' | 'plan' | 'convert';

export interface Mission {
  kind: MissionKind;
  /** Your judged moves since it was set. */
  moves: number;
  /** Keep your edge: your moves at +1 or better so far. */
  held: number;
  /** Follow the plan: the piece and the square the structure's plan sends it to. */
  goal?: { piece: PieceType; to: Square };
  /** Follow the plan: where you stood when it was set, in centipawns from your side. */
  start?: number;
  /** Convert it: the pieces, pawns and kings aside, each side had when it was set. */
  pieces?: { mine: number; theirs: number };
}

/** Keep your edge: stay at +1 or better for this many of your moves. */
export const EDGE_MOVES = 10;
/** Take the lead and Dig in: this many of your moves to get there. */
export const MISSION_WINDOW = 15;
/** Where you stand, in centipawns from your side, to keep or take the lead. */
export const MISSION_LEAD = 100;
/** Dig in: back to here or better. */
export const MISSION_DUG = -50;
/** Follow the plan: this many of your moves to get the piece there. */
export const PLAN_WINDOW = 8;
/** Follow the plan: how much of where you stood you may give up on the way. */
export const PLAN_SLACK = 100;
/** Convert it: set from this far ahead, and this far ahead it must stay once the trade is done. */
export const CONVERT_FROM = 200;
/** Convert it: this many of your moves to trade a piece. */
export const CONVERT_WINDOW = 6;
/** A mission completed pays this. */
export const MISSION_BONUS = 15;
/** Your moves between one mission ending and the next being set. */
export const MISSION_BREAK = 3;

/** Your side's view of a score in White's frame. */
function mine(color: 'w' | 'b', cp: number): number {
  return color === 'w' ? cp : -cp;
}

/** Each side's pieces on the board, pawns and kings aside. */
function pieceCount(fen: string, color: 'w' | 'b'): { mine: number; theirs: number } {
  const pieces = piecesFromFen(fen).filter((p) => p.type !== 'p' && p.type !== 'k');
  const own = pieces.filter((p) => p.color === color).length;
  return { mine: own, theirs: pieces.length - own };
}

/**
 * The mission the eval calls for, in White's frame. Well ahead with pieces
 * left to trade, that is Convert it; otherwise keep, take or dig back to a lead.
 */
export function missionFor(color: 'w' | 'b', cp: number, fen?: string): Mission {
  const at = mine(color, cp);
  if (fen && at >= CONVERT_FROM) {
    const pieces = pieceCount(fen, color);
    if (pieces.mine > 0 && pieces.theirs > 0) return { kind: 'convert', moves: 0, held: 0, pieces };
  }
  const kind: MissionKind = at >= MISSION_LEAD ? 'edge' : at <= -MISSION_LEAD ? 'dig' : 'lead';
  return { kind, moves: 0, held: 0 };
}

/**
 * The plan's first step that sends a piece somewhere it can go from here, as
 * a mission, when the pawns form a named structure.
 */
export function planMission(fen: string, color: 'w' | 'b', cp: number): Mission | null {
  const structure = structureOf(fen);
  if (!structure) return null;
  for (const step of planFor(structure, color)) {
    if (!step.goal) continue;
    const route = goalRoute(fen, color, step.goal);
    if (route.done || !route.arrows.length) continue;
    return { kind: 'plan', moves: 0, held: 0, goal: step.goal, start: mine(color, cp) };
  }
  return null;
}

export function missionTitle(kind: MissionKind): string {
  switch (kind) {
    case 'edge':
      return 'Keep your edge';
    case 'lead':
      return 'Take the lead';
    case 'dig':
      return 'Dig in';
    case 'plan':
      return 'Follow the plan';
    case 'convert':
      return 'Convert it';
  }
}

const PIECE_NAME: Record<PieceType, string> = { p: 'pawn', n: 'knight', b: 'bishop', r: 'rook', q: 'queen', k: 'king' };

/** The mission's line under "Your move": its name and where it stands. */
export function missionText(mission: Mission): string {
  const left = (window: number) => {
    const n = window - mission.moves;
    return `${n} move${n === 1 ? '' : 's'} left`;
  };
  switch (mission.kind) {
    case 'edge':
      return `${missionTitle(mission.kind)} · ${mission.held} of ${EDGE_MOVES}`;
    case 'plan':
      return mission.goal
        ? `${missionTitle(mission.kind)} · ${PIECE_NAME[mission.goal.piece]} to ${mission.goal.to} · ${left(PLAN_WINDOW)}`
        : `${missionTitle(mission.kind)} · ${left(PLAN_WINDOW)}`;
    case 'convert':
      return `${missionTitle(mission.kind)} · trade a piece · ${left(CONVERT_WINDOW)}`;
    default:
      return `${missionTitle(mission.kind)} · ${left(MISSION_WINDOW)}`;
  }
}

/**
 * One of your judged moves against a mission, with the eval after it in
 * White's frame and the position after it, which the plan and Convert it read.
 */
export function stepMission(
  mission: Mission,
  color: 'w' | 'b',
  cp: number,
  fen?: string,
): { mission: Mission; result: 'done' | 'failed' | null } {
  const at = mine(color, cp);
  const next = { ...mission, moves: mission.moves + 1 };
  switch (mission.kind) {
    case 'edge':
      if (at < MISSION_LEAD) return { mission: next, result: 'failed' };
      next.held = mission.held + 1;
      return { mission: next, result: next.held >= EDGE_MOVES ? 'done' : null };
    case 'lead':
      if (at >= MISSION_LEAD) return { mission: next, result: 'done' };
      return { mission: next, result: next.moves >= MISSION_WINDOW ? 'failed' : null };
    case 'dig':
      if (at >= MISSION_DUG) return { mission: next, result: 'done' };
      return { mission: next, result: next.moves >= MISSION_WINDOW ? 'failed' : null };
    case 'plan': {
      const floor = (mission.start ?? 0) - PLAN_SLACK;
      if (at < floor) return { mission: next, result: 'failed' };
      if (fen && mission.goal && goalRoute(fen, color, mission.goal).done) return { mission: next, result: 'done' };
      return { mission: next, result: next.moves >= PLAN_WINDOW ? 'failed' : null };
    }
    case 'convert': {
      if (at < MISSION_LEAD) return { mission: next, result: 'failed' };
      // Traded: each side has a piece fewer than when it was set, and the lead held through it.
      const now = fen ? pieceCount(fen, color) : null;
      const was = mission.pieces;
      if (now && was && now.mine < was.mine && now.theirs < was.theirs && at >= CONVERT_FROM) {
        return { mission: next, result: 'done' };
      }
      return { mission: next, result: next.moves >= CONVERT_WINDOW ? 'failed' : null };
    }
  }
}

/** Where a run's extras stand. */
export interface Extras {
  points: number;
  combo: number;
  bestCombo: number;
  moments: { found: number; missed: number; streak: number };
  mission: Mission | null;
  /** Your judged moves still to go before the next mission is set. */
  missionBreak: number;
  missions: { done: number; failed: number };
}

export const NO_EXTRAS: Extras = {
  points: 0,
  combo: 0,
  bestCombo: 0,
  moments: { found: 0, missed: 0, streak: 0 },
  mission: null,
  missionBreak: 0,
  missions: { done: 0, failed: 0 },
};

/** What a judged move did, for the screen to show. */
export interface Earned {
  points: number;
  moment: { found: boolean; bonus: number } | null;
  mission: { kind: MissionKind; result: 'done' | 'failed'; bonus: number } | null;
  /** The combo went up a multiplier, or broke. */
  combo: 'up' | 'broke' | null;
}

/**
 * One of your moves the engine judged, past prep or off it: the combo moves,
 * the move earns its points, a moment is settled, a mission steps.
 */
export function judgedExtras(
  extras: Extras,
  prefs: Pick<SurvivalPrefs, 'moments' | 'missions' | 'combo'>,
  color: 'w' | 'b',
  move: { lost: number; after: number; moment: boolean; found: boolean; fen?: string },
): { extras: Extras; earned: Earned } {
  const was = extras.combo;
  let combo = prefs.combo ? comboAfter(was, move.lost) : 0;
  let moments = extras.moments;
  let momentEarned: Earned['moment'] = null;
  if (prefs.moments && move.moment) {
    if (move.found) {
      const bonus = momentBonus(moments.streak);
      moments = { ...moments, found: moments.found + 1, streak: moments.streak + 1 };
      momentEarned = { found: true, bonus };
    } else {
      moments = { ...moments, missed: moments.missed + 1, streak: 0 };
      momentEarned = { found: false, bonus: 0 };
      combo = 0;
    }
  }
  let points = extras.points + comboMultiplier(combo) + (momentEarned?.bonus ?? 0);
  let mission = extras.mission;
  let missionBreak = extras.missionBreak;
  let missions = extras.missions;
  let missionEarned: Earned['mission'] = null;
  if (prefs.missions) {
    if (mission) {
      const stepped = stepMission(mission, color, move.after, move.fen);
      if (stepped.result) {
        const bonus = stepped.result === 'done' ? MISSION_BONUS : 0;
        missionEarned = { kind: mission.kind, result: stepped.result, bonus };
        points += bonus;
        missions =
          stepped.result === 'done' ? { ...missions, done: missions.done + 1 } : { ...missions, failed: missions.failed + 1 };
        mission = null;
        missionBreak = MISSION_BREAK;
      } else mission = stepped.mission;
    } else if (missionBreak > 0) {
      missionBreak -= 1;
      if (missionBreak === 0) mission = missionFor(color, move.after, move.fen);
    }
  }
  const up = comboMultiplier(combo) > comboMultiplier(was);
  const broke = prefs.combo && was >= 3 && combo === 0;
  return {
    extras: {
      points,
      combo,
      bestCombo: Math.max(extras.bestCombo, combo),
      moments,
      mission,
      missionBreak,
      missions,
    },
    earned: { points: points - extras.points, moment: momentEarned, mission: missionEarned, combo: up ? 'up' : broke ? 'broke' : null },
  };
}

/** A move your prep answered: a point, at ×1. */
export function prepExtras(extras: Extras): Extras {
  return { ...extras, points: extras.points + 1 };
}

/**
 * The first mission, set where the prep runs out: a step of the structure's
 * plan when the pawns form one, else from the eval in front of you.
 */
export function firstMission(
  extras: Extras,
  prefs: Pick<SurvivalPrefs, 'missions'>,
  color: 'w' | 'b',
  cp: number,
  fen?: string,
): Extras {
  if (!prefs.missions || extras.mission || extras.missionBreak > 0 || extras.missions.done + extras.missions.failed > 0) {
    return extras;
  }
  return { ...extras, mission: (fen ? planMission(fen, color, cp) : null) ?? missionFor(color, cp, fen) };
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
  /** Points, combo, moments and missions — see `judgedExtras`. */
  extras: Extras;
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
  return { source, state: { run: begun.run, moves: 0, misses: [], extras: NO_EXTRAS }, redraw: begun.redraw };
}

/** Your prep's answers here, best first; empty where it says nothing. */
export function prepHere(source: LineSource, state: SurvivalRun): string[] {
  return source.prepAt(state.run.fen);
}

/**
 * One of your moves, passed by your prep or by the engine. A miss is the
 * prepared move you did not play, logged on the run for the end screen.
 */
export function playYours(state: SurvivalRun, san: string, missed?: string, extras?: Extras): SurvivalRun {
  const { run } = state;
  const move = applySan(run.fen, san);
  if (!move) return state;
  const target = run.target[run.played.length] === san ? run.target : [];
  return {
    run: { ...run, fen: move.after, played: [...run.played, san], survived: run.survived + 1, target },
    moves: state.moves + 1,
    extras: extras ?? prepExtras(state.extras),
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
  /** The most points a run has scored. Only ever goes up. */
  bestPoints: number;
}

export interface SurvivalRecord {
  /** Every run, whatever it went through: the global max. */
  global: SurvivalScore;
  /** Opening tree node id → the runs that went through it. */
  openings: Record<string, SurvivalScore>;
}

export const EMPTY_SURVIVAL_SCORE: SurvivalScore = { best: 0, recent: [], history: [], runs: 0, ended: 0, bestPoints: 0 };

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
    bestPoints: score?.bestPoints ?? 0,
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

function scored(score: SurvivalScore | undefined, moves: number, points: number): SurvivalScore {
  const base = score ?? EMPTY_SURVIVAL_SCORE;
  return {
    best: Math.max(base.best, moves),
    recent: [...base.recent, moves].slice(-RECENT_RUNS),
    history: [...base.history, moves].slice(-HISTORY_RUNS),
    runs: base.runs + 1,
    ended: base.ended,
    bestPoints: Math.max(base.bestPoints ?? 0, points),
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
  /** The run's points; its moves when it scored none apart. */
  points = moves,
): SurvivalRecord {
  const openings = { ...record.openings };
  for (const id of openingsAlong(tree, line)) openings[id] = scored(openings[id], moves, points);
  return { global: scored(record.global, moves, points), openings };
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
