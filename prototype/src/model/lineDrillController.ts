/**
 * Drill lines as a pure controller: `state + event → state + effects`, the
 * same shape as `drillController`. The screen owns the clock, the timers,
 * drawing lines (which reads the store) and the store itself.
 */
import type { Color, LegalMove } from '../chess/core';
import { continueLine, yoursAt, type DrillLine } from './lineDrill';
import type { Mistake } from './mistakes';
import { deepestNodeWithin, type OpeningNode, type OpeningTree } from './openingTree';
import type { RoundRecord } from './scoring';
import { checkAnswer, type TrainingItem } from './session';
import { gradeForLine } from './srs';
import type { Grade, LineCard, Repertoire } from './types';

/** Playing the line; a right move shown for a beat; a miss explained; or the line done and graded. */
export type LinePhase = 'play' | 'flash' | 'wrong' | 'done';

/** The line's grade, once given: its card as it was before, so it can be changed. */
export interface Graded {
  before: LineCard;
  grade: Grade;
}

export interface LineDrillState {
  /** The lines drawn for this group, and which one is being played. */
  batch: DrillLine[];
  at: number;
  /** Which group of similar lines this is, in a sitting with no end. */
  group: number;
  line: DrillLine | null;
  /** How far into the line the board stands. */
  ply: number;
  phase: LinePhase;
  played: LegalMove | null;
  misses: number;
  /** Seconds each correct move of yours took, this line. */
  times: number[];
  graded: Graded | null;
  /** Lines finished this sitting, for the counter. */
  finished: number;
}

export type LineEffect =
  | { kind: 'record'; line: string[]; correct: boolean }
  | { kind: 'buzz'; pattern: number | number[] }
  /** A mistake logged at this position has been put right. */
  | { kind: 'clearMistake'; id: string }
  | { kind: 'mistake'; mistake: Omit<Mistake, 'id' | 'at'> }
  /** Show the right move for a beat, then go on (`flashed`). */
  | { kind: 'flash' }
  | { kind: 'round'; round: Omit<RoundRecord, 'at'> }
  /** Grade the line's card; `before`, when given, is what to put it back to first. The screen answers with `graded`. */
  | { kind: 'gradeLine'; repertoireId: string; tipId: string; grade: Grade; before?: LineCard };

export type LineStep = { state: LineDrillState; effects: LineEffect[] };

export function beginLines(batch: DrillLine[]): LineDrillState {
  return {
    batch,
    at: 0,
    group: 1,
    line: batch[0] ?? null,
    ply: 0,
    phase: 'play',
    played: null,
    misses: 0,
    times: [],
    graded: null,
    finished: 0,
  };
}

/** Whether the board is waiting on one of your moves. */
export function yourMove(state: LineDrillState, color: Color): boolean {
  return !!state.line && state.ply < state.line.sans.length && yoursAt(color, state.ply);
}

/** The move your prep has here, when it is your move. */
export function expectedHere(state: LineDrillState, color: Color): string | null {
  return state.line && yourMove(state, color) ? state.line.sans[state.ply] : null;
}

/** The opponent's moves play themselves. */
export function theirMove(state: LineDrillState, color: Color): LineDrillState {
  if (!state.line || state.phase !== 'play' || yourMove(state, color) || state.ply >= state.line.sans.length) return state;
  return { ...state, ply: state.ply + 1 };
}

/**
 * You played `move`, `took` seconds after it was your turn. Another move your
 * prep has is right too, and the line follows it. `item` is Drill's item for
 * the position, when there is one; `mistakeIds` are the mistakes logged now.
 */
export function answer(
  state: LineDrillState,
  color: Color,
  move: LegalMove,
  took: number,
  rep: Repertoire,
  item: TrainingItem | null,
  mistakeIds: string[],
): LineStep {
  const { line, ply } = state;
  if (!line || state.phase !== 'play' || !yourMove(state, color)) return { state, effects: [] };
  const expected = line.sans[ply];
  const right = item ? checkAnswer(item, move.san).correct : move.san === expected;
  const asked = line.sans.slice(0, ply);
  const effects: LineEffect[] = [{ kind: 'record', line: right ? [...asked, move.san] : asked, correct: right }];
  if (right) {
    effects.push({ kind: 'buzz', pattern: 12 });
    // Answered right: a mistake logged here has been put right.
    const logged = item && `${item.repertoireId}#${item.key}`;
    if (logged && mistakeIds.includes(logged)) effects.push({ kind: 'clearMistake', id: logged });
    const along = move.san !== expected ? continueLine(rep, [...asked, move.san]) : null;
    effects.push({ kind: 'flash' });
    return {
      state: { ...state, played: move, times: [...state.times, took], line: along ?? line, phase: 'flash' },
      effects,
    };
  }
  effects.push({ kind: 'buzz', pattern: [18, 50, 18] });
  if (item) {
    effects.push({
      kind: 'mistake',
      mistake: {
        source: 'drill',
        repertoireId: item.repertoireId,
        key: item.key,
        fen: item.fen,
        path: asked,
        played: move.san,
        expected,
      },
    });
  }
  return { state: { ...state, played: move, misses: state.misses + 1, phase: 'wrong' }, effects };
}

/** After the beat on a right move, or Continue after a miss: your prep's move stands, and the line goes on. */
export function carryOn(state: LineDrillState): LineDrillState {
  if (state.phase !== 'flash' && state.phase !== 'wrong') return state;
  return { ...state, played: null, ply: state.ply + 1, phase: 'play' };
}

/**
 * The end of the line: counted once, as a round of its own, and graded for
 * you from the clock — Guessed after any miss, otherwise the average time of
 * your right moves.
 */
export function lineDone(state: LineDrillState, color: Color, tree: OpeningTree, region: OpeningNode): LineStep {
  const { line } = state;
  if (!line || state.phase !== 'play' || state.ply < line.sans.length) return { state, effects: [] };
  const asked = state.times.length + state.misses;
  const effects: LineEffect[] = [
    {
      kind: 'round',
      round: {
        mode: 'drill',
        openingId: deepestNodeWithin(tree, region, line.sans).id,
        color,
        answered: asked,
        correct: state.times.length,
        perfect: state.misses === 0 && asked > 0,
        line: line.sans,
      },
    },
  ];
  if (asked > 0) {
    effects.push({ kind: 'gradeLine', repertoireId: line.repertoireId, tipId: line.tipId, grade: gradeForLine(state.times, state.misses) });
  }
  return { state: { ...state, finished: state.finished + 1, phase: 'done' }, effects };
}

/** The store graded the line: keep its card as it was, so the grade can be changed. */
export function graded(state: LineDrillState, before: LineCard, grade: Grade): LineDrillState {
  return { ...state, graded: { before, grade } };
}

/** Change the line's grade: its card goes back to before and takes the new one. */
export function regrade(state: LineDrillState, value: Grade): LineStep {
  const { line, graded: was } = state;
  if (!line || !was || was.grade === value) return { state, effects: [] };
  return {
    state: { ...state, graded: { ...was, grade: value } },
    effects: [{ kind: 'gradeLine', repertoireId: line.repertoireId, tipId: line.tipId, grade: value, before: was.before }],
  };
}

/** Whether the next line needs a fresh draw: this group is played out. */
export function needsDraw(state: LineDrillState): boolean {
  return state.at + 1 >= state.batch.length;
}

/** On to the next line: the next of this group, or the first of `fresh`, a new group, when this one is done. */
export function nextLine(state: LineDrillState, fresh?: DrillLine[]): LineDrillState {
  const drawn = needsDraw(state);
  const lines = drawn ? (fresh ?? []) : state.batch;
  const at = drawn ? 0 : state.at + 1;
  return {
    ...state,
    batch: lines,
    group: drawn ? state.group + 1 : state.group,
    at,
    line: lines[at] ?? null,
    ply: 0,
    phase: 'play',
    played: null,
    misses: 0,
    times: [],
    graded: null,
  };
}
