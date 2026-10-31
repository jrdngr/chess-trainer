/**
 * A Growth run as a pure controller: `state + event → state + effects`, the
 * same shape as `survivalController`. The screen owns timing, the engine and
 * the store, and feeds each thing that happens in as an event. What a run
 * decides — walking your prep, stopping at a hole, taking an answer, sizing
 * the batch, Undo, another batch, the edge of the book — lives here.
 */
import { applySan, type LegalMove } from '../chess/core';
import type { NewEvent } from './events';
import {
  addsToFit,
  advance,
  answerHole,
  atHole,
  enterHole,
  firstEnd,
  firstHole,
  isUsersTurn,
  lineFor,
  startGrowth,
  startGrowthAt,
  startGrowthAtEnd,
  steer,
  type GrowthOptions,
  type GrowthRow,
  type GrowthRun,
  type Hole,
} from './growth';
import type { OpeningNode } from './openingTree';
import { deepestNodeWithin, type OpeningTree } from './openingTree';
import type { ReferenceIndex } from './reference';
import { nodeAtLine } from './repertoire';
import type { RoundRecord } from './scoring';
import type { Repertoire } from './types';

/**
 * Walking your prep toward a hole; standing at one, to answer it; having
 * answered, waiting on their reply; at rest, the batch over; or off your
 * prep while walking, which ends the run.
 */
export type GrowthPhase = 'walking' | 'hole' | 'answered' | 'done' | 'lost';

/**
 * The batch being added: where it began in `added`, and how many it may add.
 * Set when the run arrives at the hole the batch starts from, so the
 * allowance is measured from that depth.
 */
export interface Batch {
  base: number;
  allowance: number;
}

export interface GrowthSession {
  run: GrowthRun;
  phase: GrowthPhase;
  /** The move that left your prep while walking, which lost the run. */
  wrong: string | null;
  /** Which plies of the line you added, so the strip can mark them. */
  added: number[];
  batch: Batch | null;
  /** The answer just chosen, until they reply to it — the board shows it green. */
  answer: LegalMove | null;
  /**
   * Every answer added this sitting, oldest first, with the run and batch as
   * they stood at the reply it answered: what Undo steps back to. Only this
   * sitting's moves are here, so Undo can never reach older prep.
   */
  history: { run: GrowthRun; batch: Batch | null; san: string }[];
  /** The run stopped at the edge of the book. */
  edge: boolean;
}

/** Something for the screen to do, in order. */
export type GrowthEffect =
  | { kind: 'addLine'; line: string[] }
  | { kind: 'removeLine'; nodeId: string }
  | { kind: 'log'; event: NewEvent }
  | { kind: 'buzz'; pattern: number | number[] }
  | { kind: 'toast'; text: string }
  /** "End of the book", flashed over the board. */
  | { kind: 'edgeFlash' };

export type GrowthStep = { session: GrowthSession; effects: GrowthEffect[] };

const still = (session: GrowthSession): GrowthStep => ({ session, effects: [] });

/**
 * A run begins at the hole it was handed, or the one the row most wants
 * answered; a row whose line simply ends starts at its tip, for the book to
 * reply; otherwise it walks from move one.
 */
export function beginGrowth(tree: Repertoire, index: ReferenceIndex, row: GrowthRow, hole?: Hole | null): GrowthSession {
  const start = hole ?? firstHole(index, row);
  const end = start ? null : firstEnd(row);
  return {
    run: start ? startGrowthAt(tree, row, start) : end ? startGrowthAtEnd(tree, row, end) : startGrowth(tree, row),
    phase: start ? 'hole' : end ? 'answered' : 'walking',
    wrong: null,
    added: [],
    batch: null,
    answer: null,
    history: [],
    edge: false,
  };
}

/** Whether the opponent is to move on the walk, and not already standing at a hole. */
export function opponentToMove(session: GrowthSession, tree: Repertoire): boolean {
  return session.phase === 'walking' && !isUsersTurn(session.run) && !atHole(tree, session.run);
}

/**
 * The opponent's move on the walk, steered toward the hole most worth
 * answering. Where nothing is left to walk, or they step into a hole, the
 * run stands at it.
 */
export function opponentWalks(session: GrowthSession, tree: Repertoire, index: ReferenceIndex, find: GrowthOptions): GrowthSession {
  if (!opponentToMove(session, tree)) return session;
  const reply = steer(tree, index, session.run, find);
  if (!reply) return { ...session, phase: 'hole' };
  if (reply.hole) return { ...session, run: enterHole(session.run, reply.hole), phase: 'hole' };
  const next = advance(tree, session.run, reply.san);
  return next ? { ...session, run: next } : { ...session, phase: 'hole' };
}

/** A line that ends on the opponent's move leaves you to move with nothing: a hole. */
export function nothingPrepared(session: GrowthSession, prepared: number): GrowthSession {
  if (session.phase !== 'walking' || !isUsersTurn(session.run) || prepared > 0) return session;
  return { ...session, phase: 'hole' };
}

/**
 * Your move on the walk. Your own prep is the only thing that counts here, so
 * anything else ends the run rather than quietly becoming a new line.
 */
export function walk(session: GrowthSession, tree: Repertoire, san: string): GrowthStep {
  if (session.phase !== 'walking' || !isUsersTurn(session.run)) return still(session);
  const next = advance(tree, session.run, san);
  if (!next) return { session: { ...session, wrong: san, phase: 'lost' }, effects: [{ kind: 'buzz', pattern: [18, 50, 18] }] };
  return { session: { ...session, run: next }, effects: [{ kind: 'buzz', pattern: 10 }] };
}

/** A batch is measured from the first hole it is offered at. */
export function measureBatch(session: GrowthSession, maxPly: number): GrowthSession {
  if (session.phase !== 'hole' || session.batch) return session;
  return { ...session, batch: { base: session.added.length, allowance: addsToFit(session.run.path.length, maxPly) } };
}

/**
 * How many this batch may add, from how deep the hole it starts at is. Read
 * straight from the position until the batch is recorded, so the count under
 * the board is right on the frame the hole appears.
 */
export function allowanceOf(session: GrowthSession, maxPly: number): number {
  return session.batch?.allowance ?? addsToFit(session.run.path.length, maxPly);
}

/** How many answers this batch has added so far. */
export function inBatch(session: GrowthSession): number {
  return session.added.length - (session.batch?.base ?? session.added.length);
}

/**
 * Take an answer at a hole. The run walks on rather than ending: the answer
 * is saved and played, and unless this was the last one the batch allows,
 * their reply to it becomes the next thing to answer. `offered` is the list
 * as ranked on screen, for the event log.
 */
export function choose(session: GrowthSession, san: string, allowance: number, offered: string[]): GrowthStep {
  const { run } = session;
  if (session.phase !== 'hole') return still(session);
  const move = applySan(run.fen, san);
  const next = move ? answerHole(run, san) : null;
  if (!move || !next) return still(session);
  return {
    session: {
      ...session,
      history: [...session.history, { run, batch: session.batch, san }],
      added: [...session.added, run.path.length],
      answer: move,
      run: next,
      phase: inBatch(session) + 1 >= allowance ? 'done' : 'answered',
    },
    effects: [
      { kind: 'addLine', line: lineFor(run, san) },
      { kind: 'log', event: { kind: 'growth-pick', via: 'growth', color: run.color, line: run.path.join(' '), picked: san, offered } },
      { kind: 'buzz', pattern: 10 },
      { kind: 'toast', text: `${san} added` },
    ],
  };
}

/**
 * Their reply to the move you just added, once it is known: `undefined`
 * while the engine is still deciding past the book, null when there is no
 * move at all, which ends the batch.
 */
export function theyReply(session: GrowthSession, hole: Hole | null): GrowthSession {
  if (session.phase !== 'answered') return session;
  if (!hole) return { ...session, phase: 'done' };
  return { ...session, answer: null, run: enterHole(session.run, hole), phase: 'hole' };
}

/**
 * Take back answers added this sitting: the last one, or all of them. The
 * move leaves the repertoire, and the run stands again on the reply it
 * answered, with the batch as it was — so the slot it took is free again.
 * Every answer is on one line, so taking back the oldest takes the rest with
 * it. `live` is the repertoire as it stands now.
 */
export function undo(session: GrowthSession, live: Repertoire | undefined, all = false): GrowthStep {
  const { history } = session;
  if (!history.length) return still(session);
  const to = all ? 0 : history.length - 1;
  const step = history[to];
  // Standing in a hole, the reply being answered had no node either: adding
  // the answer wrote it too, so it goes with it. A line that simply ended on
  // their move had its reply already, and only the answer goes. A reply you
  // had kept stays: only the answer to it was added.
  const line = step.run.hole && !step.run.hole.kept ? step.run.path : lineFor(step.run, step.san);
  const node = live ? nodeAtLine(live, line) : null;
  const effects: GrowthEffect[] = [];
  if (node) effects.push({ kind: 'removeLine', nodeId: node.id });
  effects.push(
    { kind: 'log', event: { kind: 'growth-undo', via: 'growth', color: session.run.color, line: lineFor(step.run, step.san).join(' '), all } },
    { kind: 'buzz', pattern: 10 },
    { kind: 'toast', text: all ? 'Line undone' : `${step.san} undone` },
  );
  return {
    session: {
      ...session,
      history: history.slice(0, to),
      added: session.added.slice(0, to),
      answer: null,
      batch: step.batch,
      run: step.run,
      phase: 'hole',
    },
    effects,
  };
}

/**
 * Take the reveal up on another batch, from where `resumeAdding` says it
 * starts. Standing where they are to reply, past the book, the engine
 * replies first.
 */
export function anotherBatch(session: GrowthSession, tree: Repertoire, more: GrowthRun): GrowthStep {
  return {
    session: { ...session, answer: null, batch: null, run: more, phase: atHole(tree, more) ? 'hole' : 'answered' },
    effects: [{ kind: 'buzz', pattern: 10 }],
  };
}

/**
 * Growth stops where the book does: standing past it with Past the book off,
 * the run comes to rest and says so.
 */
export function reachedEdge(session: GrowthSession): GrowthStep {
  if (session.phase !== 'hole' && session.phase !== 'answered') return still(session);
  return { session: { ...session, answer: null, edge: true, phase: 'done' }, effects: [{ kind: 'edgeFlash' }] };
}

/**
 * A hole the book cannot answer ends the batch rather than sitting there, and
 * Done ends it by hand.
 */
export function stop(session: GrowthSession): GrowthSession {
  return session.phase === 'done' ? session : { ...session, phase: 'done' };
}

/**
 * One sitting is one round, whatever it takes: drawn up at rest, and logged
 * on the way out, since another batch can follow the reveal. Null while the
 * run is still going.
 */
export function growthRound(
  session: GrowthSession,
  catalogue: OpeningTree,
  within: OpeningNode,
  allowance: number,
): Omit<RoundRecord, 'at'> | null {
  if (session.phase !== 'done' && session.phase !== 'lost') return null;
  return {
    mode: 'growth',
    openingId: deepestNodeWithin(catalogue, within, session.run.path).id,
    color: session.run.color,
    answered: 0,
    correct: 0,
    perfect: inBatch(session) >= allowance,
  };
}
