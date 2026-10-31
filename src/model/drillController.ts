/**
 * Drill positions as a pure controller: `state + event → state + effects`,
 * the same shape as `survivalController`. The screen owns the clock, the
 * flash's timer and the store. What a sitting decides — the queue and how it
 * is kept stocked, judging an answer, grading it, following the line, sending
 * a miss back round, and changing a grade — lives here.
 */
import { applySan, type LegalMove } from '../chess/core';
import type { Mistake } from './mistakes';
import type { RoundRecord } from './scoring';
import {
  buildSession,
  checkAnswer,
  extraPractice,
  leadWithAWayIn,
  weakestFirst,
  type SessionMode,
  type TrainingItem,
} from './session';
import { createCard, gradeForTime } from './srs';
import type { Card, Grade, Repertoire } from './types';

/** How many positions to line up at a time, and when to line up more. */
export const BATCH = 20;
export const REFILL_AT = 6;

/** How far back round a position comes when it is sent back. */
export const REQUEUE_AFTER = 4;

/** Asking; a correct move, shown for a beat before the next position; or a wrong one, explained. */
export type DrillPhase = 'ask' | 'flash' | 'wrong';

/**
 * The last correct answer, graded off the clock and already on the schedule.
 * The grade buttons stay on screen for the next position and re-grade it,
 * so the flow is move, move, move — with a way to say "I guessed that".
 */
export interface LastAnswer {
  item: TrainingItem;
  before: Card;
  grade: Grade;
  played: string;
}

export interface DrillState {
  queue: TrainingItem[];
  /** The position being asked: `queue[index]`. */
  index: number;
  phase: DrillPhase;
  played: LegalMove | null;
  stats: { answered: number; correct: number };
  last: LastAnswer | null;
}

export interface DrillOptions {
  mode: SessionMode;
  /** How many new positions a batch may bring in. */
  maxNew: number;
  /** Ask what you keep getting wrong before what is merely due. */
  weakFirst: boolean;
}

/** Something for the screen to do, in order. */
export type DrillEffect =
  /** Record the answer: Drill is recorded, never rated. */
  | { kind: 'record'; line: string[]; color: 'w' | 'b'; correct: boolean }
  | { kind: 'buzz'; pattern: number | number[] }
  | { kind: 'grade'; item: TrainingItem; grade: Grade; played: string; correct: boolean }
  | { kind: 'regrade'; item: TrainingItem; before: Card; grade: Grade; played: string }
  | { kind: 'mistake'; mistake: Omit<Mistake, 'id' | 'at'> }
  /** Show the correct move for a beat, then go on — to `next`, when following the line. */
  | { kind: 'flash'; next: TrainingItem | null };

export type DrillStep = { state: DrillState; effects: DrillEffect[] };

/** The queue, in the order the mode asks for. */
function order(batch: TrainingItem[], cards: Record<string, Card>, weakFirst: boolean): TrainingItem[] {
  return weakFirst ? weakestFirst(batch, cards) : batch;
}

/** A sitting, lined up: scheduled work first, led by a position with a way in. */
export function beginDrill(items: TrainingItem[], cards: Record<string, Card>, opts: DrillOptions, now: number): DrillState {
  const queue = leadWithAWayIn(
    order(
      buildSession(items, cards, { mode: opts.mode, now, maxItems: BATCH, maxNew: opts.maxNew, seed: Math.floor(now / 60000) }),
      cards,
      opts.weakFirst,
    ),
  );
  return { queue, index: 0, phase: 'ask', played: null, stats: { answered: 0, correct: 0 }, last: null };
}

/**
 * Keep the queue stocked. Scheduled work first; when the schedule is clear,
 * the stalest positions, so the session only ends when you end it.
 */
export function refill(
  state: DrillState,
  items: TrainingItem[],
  cards: Record<string, Card>,
  opts: DrillOptions,
  rand: () => number,
  now: number,
): DrillState {
  if (!items.length || state.queue.length - state.index > REFILL_AT) return state;
  const ahead = new Set(state.queue.slice(state.index).map((i) => i.cardId));
  const scheduled = buildSession(items, cards, { mode: opts.mode, now, maxItems: BATCH, maxNew: opts.maxNew, seed: now }).filter(
    (i) => !ahead.has(i.cardId),
  );
  const taken = new Set(scheduled.map((i) => i.cardId));
  const filler =
    scheduled.length >= BATCH
      ? []
      : extraPractice(items, cards, BATCH - scheduled.length, rand, (id) => ahead.has(id) || taken.has(id));
  const batch = order([...scheduled, ...filler], cards, opts.weakFirst);
  return batch.length ? { ...state, queue: [...state.queue, ...batch] } : state;
}

/** The position being asked, if any. */
export function current(state: DrillState): TrainingItem | undefined {
  return state.queue[state.index];
}

/** The move the position wants: the preferred answer, or the first. */
export function expectedSan(item: TrainingItem): string | undefined {
  return item.expected.find((e) => e.preferred)?.san ?? item.expected[0]?.san;
}

/**
 * The next decision point down this line, when following the line through:
 * your answer, their reply, and the position you would be asked next.
 */
export function followUpFor(item: TrainingItem, items: TrainingItem[], rep: Repertoire | undefined): TrainingItem | null {
  if (!rep) return null;
  const [mine, reply] = item.continuation;
  if (!mine || !reply) return null;
  const afterMine = applySan(item.fen, mine);
  if (!afterMine) return null;
  const afterReply = applySan(afterMine.after, reply);
  if (!afterReply) return null;
  return items.find((candidate) => candidate.fen === afterReply.after && candidate.cardId !== item.cardId) ?? null;
}

/**
 * You played `move`, `took` seconds after the position was asked. Right, and
 * it is graded by the clock and the board moves on after a beat (down the
 * line, with `followUp`). Wrong, and it is a lapse, graded at once, and
 * logged as a mistake so practice steers back to it.
 */
export function answer(
  state: DrillState,
  move: LegalMove,
  took: number,
  card: Card | undefined,
  followUp: TrainingItem | null,
): DrillStep {
  const item = current(state);
  if (!item || state.phase !== 'ask') return { state, effects: [] };
  const result = checkAnswer(item, move.san);
  const effects: DrillEffect[] = [
    {
      kind: 'record',
      // Right, and the line is where the answer took you; wrong, and it is the
      // position you were asked about, since the move played leads elsewhere.
      line: result.correct ? [...item.pathSans, move.san] : item.pathSans,
      color: item.orientation === 'black' ? 'b' : 'w',
      correct: result.correct,
    },
    { kind: 'buzz', pattern: result.correct ? 12 : [18, 50, 18] },
  ];
  const stats = { answered: state.stats.answered + 1, correct: state.stats.correct + (result.correct ? 1 : 0) };
  if (result.correct) {
    // The card is kept as it was, so the grade can still be changed from the next screen.
    const auto = gradeForTime(took);
    const before = card ?? createCard(item.cardId, item.repertoireId, item.key, item.fen);
    effects.push({ kind: 'grade', item, grade: auto, played: move.san, correct: true }, { kind: 'flash', next: followUp });
    return {
      state: { ...state, played: move, phase: 'flash', stats, last: { item, before, grade: auto, played: move.san } },
      effects,
    };
  }
  effects.push(
    { kind: 'grade', item, grade: 'again', played: move.san, correct: false },
    {
      kind: 'mistake',
      mistake: {
        source: 'drill',
        repertoireId: item.repertoireId,
        key: item.key,
        fen: item.fen,
        path: item.pathSans,
        played: move.san,
        expected: expectedSan(item) ?? '',
      },
    },
  );
  return { state: { ...state, played: move, phase: 'wrong', stats }, effects };
}

/**
 * On to the next position. Following the line, `extra` is put next, taken
 * out of wherever it was further on.
 */
export function advance(state: DrillState, extra?: TrainingItem | null): DrillState {
  let queue = state.queue;
  if (extra) {
    const without = queue.filter((i, idx) => idx <= state.index || i.cardId !== extra.cardId);
    queue = [...without];
    queue.splice(state.index + 1, 0, extra);
  }
  return { ...state, queue, index: state.index + 1, phase: 'ask', played: null };
}

/** Send this position back round, a few positions on. */
function sendBack(state: DrillState, item: TrainingItem): DrillState {
  const queue = [...state.queue];
  queue.splice(Math.min(queue.length, state.index + REQUEUE_AFTER), 0, item);
  return { ...state, queue };
}

/** After a wrong answer, Continue: the position comes back round, and on to the next. */
export function continueAfterWrong(state: DrillState): DrillState {
  const item = current(state);
  return advance(item ? sendBack(state, item) : state);
}

/** Change the grade of the last correct answer. Guessed also brings it back soon. */
export function regradeLast(state: DrillState, value: Grade): DrillStep {
  const { last } = state;
  if (!last || value === last.grade) return { state, effects: [] };
  const sent = value === 'again' ? sendBack(state, last.item) : state;
  return {
    state: { ...sent, last: { ...last, grade: value } },
    effects: [{ kind: 'regrade', item: last.item, before: last.before, grade: value, played: last.played }],
  };
}

/** The sitting as one round, against the opening it was played in; null with nothing answered. */
export function drillRound(state: DrillState, openingId: string): Omit<RoundRecord, 'at'> | null {
  const { answered, correct } = state.stats;
  if (answered === 0) return null;
  return {
    mode: 'drill',
    openingId,
    color: current(state)?.orientation === 'black' ? 'b' : 'w',
    answered,
    correct,
    perfect: correct === answered && answered >= 5,
  };
}
