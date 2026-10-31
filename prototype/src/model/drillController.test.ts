import { describe, expect, it } from 'vitest';
import { applySan } from '../chess/core';
import {
  advance,
  answer,
  beginDrill,
  continueAfterWrong,
  current,
  drillRound,
  expectedSan,
  followUpFor,
  refill,
  regradeLast,
  REFILL_AT,
  REQUEUE_AFTER,
  type DrillOptions,
  type DrillState,
} from './drillController';
import * as lines from './lineDrillController';
import { drawLines } from './lineDrill';
import { openingTree } from './openingTree';
import { referenceIndex } from './referenceIndex';
import { addLine, createRepertoire } from './repertoire';
import { allItems, mulberry32 } from './session';
import type { Repertoire } from './types';

const NOW = Date.parse('2026-10-01T09:00:00Z');
const index = referenceIndex();
const tree = openingTree(index);

function rep(color: 'w' | 'b', ...sans: string[]): Repertoire {
  let out = createRepertoire('Test', color, `rep_${color}`);
  for (const line of sans) out = addLine(out, line.split(' '), 'seed').rep;
  return out;
}

const white = rep('w', 'e4 e5 Nf3 Nc6 Bc4 Bc5 O-O', 'e4 c5 Nf3 d6 d4');
const items = allItems([white]);
const opts: DrillOptions = { mode: 'repertoire', maxNew: 20, weakFirst: false };

const start = (): DrillState => beginDrill(items, {}, opts, NOW);
const play = (state: DrillState, san: string) => applySan(current(state)!.fen, san)!;
const wrongMove = (state: DrillState) => {
  const item = current(state)!;
  const right = item.expected.map((e) => e.san);
  const move = ['a3', 'h3', 'a6', 'h6'].find((san) => !right.includes(san) && applySan(item.fen, san))!;
  return play(state, move);
};

describe('Drill positions as state and events', () => {
  it('lines up a sitting, led by a position with a way in when there is one', () => {
    const state = start();
    expect(state.queue.length).toBeGreaterThan(0);
    expect(state.phase).toBe('ask');
    expect(state.stats).toEqual({ answered: 0, correct: 0 });
  });

  it('a right answer is graded by the clock, recorded unrated, and shown for a beat', () => {
    const state = start();
    const san = expectedSan(current(state)!)!;
    const step = answer(state, play(state, san), 1.5, undefined, null);
    expect(step.effects.map((effect) => effect.kind)).toEqual(['record', 'buzz', 'grade', 'flash']);
    expect(step.effects[2]).toMatchObject({ grade: 'easy', correct: true, played: san });
    expect(step.state.phase).toBe('flash');
    expect(step.state.stats).toEqual({ answered: 1, correct: 1 });
    expect(step.state.last?.grade).toBe('easy');
  });

  it('a wrong answer is a lapse, graded at once and logged as a mistake', () => {
    const state = start();
    const step = answer(state, wrongMove(state), 4, undefined, null);
    expect(step.effects.map((effect) => effect.kind)).toEqual(['record', 'buzz', 'grade', 'mistake']);
    expect(step.effects[2]).toMatchObject({ grade: 'again', correct: false });
    expect(step.effects[3]).toMatchObject({ mistake: { source: 'drill', expected: expectedSan(current(state)!) } });
    expect(step.state.phase).toBe('wrong');
    expect(answer(step.state, wrongMove(state), 1, undefined, null).effects).toEqual([]);
  });

  it('Continue after a miss sends the position back round', () => {
    const state = start();
    const asked = current(state)!;
    const next = continueAfterWrong(answer(state, wrongMove(state), 4, undefined, null).state);
    expect(next.index).toBe(1);
    expect(next.phase).toBe('ask');
    expect(next.queue[REQUEUE_AFTER]).toBe(asked);
  });

  it('following the line puts the next decision point next', () => {
    const state = start();
    const item = state.queue.find((candidate) => followUpFor(candidate, items, white))!;
    const follow = followUpFor(item, items, white)!;
    const next = advance({ ...state, queue: [item, ...state.queue.filter((i) => i !== item)] }, follow);
    expect(current(next)).toBe(follow);
    expect(next.queue.filter((i) => i.cardId === follow.cardId)).toHaveLength(1);
  });

  it('Guessed on the last answer changes its grade and brings it back soon', () => {
    const state = start();
    const asked = current(state)!;
    const flashed = advance(answer(state, play(state, expectedSan(asked)!), 1.5, undefined, null).state);
    const step = regradeLast(flashed, 'again');
    expect(step.effects).toMatchObject([{ kind: 'regrade', grade: 'again' }]);
    expect(step.state.last?.grade).toBe('again');
    expect(step.state.queue[flashed.index + REQUEUE_AFTER]).toBe(asked);
    expect(regradeLast(step.state, 'again').effects).toEqual([]);
  });

  it('keeps the queue stocked once it runs low', () => {
    const state = start();
    const low = { ...state, index: Math.max(0, state.queue.length - REFILL_AT) };
    expect(refill(low, items, {}, opts, mulberry32(1), NOW).queue.length).toBeGreaterThanOrEqual(low.queue.length);
    const full = { ...state, queue: [...state.queue, ...state.queue, ...state.queue, ...state.queue] };
    expect(refill(full, items, {}, opts, mulberry32(1), NOW)).toBe(full);
  });

  it('logs the sitting as one round, perfect from five right answers', () => {
    expect(drillRound(start(), 'e4')).toBeNull();
    const five = { ...start(), stats: { answered: 5, correct: 5 } };
    expect(drillRound(five, 'e4')).toMatchObject({ mode: 'drill', answered: 5, correct: 5, perfect: true, color: 'w' });
    expect(drillRound({ ...five, stats: { answered: 4, correct: 4 } }, 'e4')?.perfect).toBe(false);
  });
});

describe('Drill lines as state and events', () => {
  const drawn = drawLines({ rep: white, tree, region: tree.root, index, lean: 'popular', count: 2, rand: mulberry32(3) });

  /** Play the line through, every move right. */
  function playThrough(state: lines.LineDrillState) {
    let s = state;
    let effects: lines.LineEffect[] = [];
    for (let guard = 0; guard < 40 && s.phase !== 'done'; guard += 1) {
      if (lines.yourMove(s, 'w')) {
        const san = lines.expectedHere(s, 'w')!;
        const fen = s.line!.sans.slice(0, s.ply).reduce((f, m) => applySan(f, m)!.after, 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
        s = lines.carryOn(lines.answer(s, 'w', applySan(fen, san)!, 2, white, null, []).state);
      } else if (s.ply < s.line!.sans.length) {
        s = lines.theirMove(s, 'w');
      } else {
        const step = lines.lineDone(s, 'w', tree, tree.root);
        s = step.state;
        effects = step.effects;
      }
    }
    return { state: s, effects };
  }

  it('plays a line through and grades it once at the end', () => {
    const { state, effects } = playThrough(lines.beginLines(drawn));
    expect(state.phase).toBe('done');
    expect(state.finished).toBe(1);
    expect(effects.map((effect) => effect.kind)).toEqual(['round', 'gradeLine']);
    expect(effects[0]).toMatchObject({ round: { mode: 'drill', perfect: true } });
    expect(effects[1]).toMatchObject({ grade: 'easy' });
  });

  it('a miss counts against the line, and Continue plays your prep and goes on', () => {
    let state = lines.beginLines(drawn);
    const first = applySan('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 'a3')!;
    const step = lines.answer(state, 'w', first, 3, white, null, []);
    expect(step.state.phase).toBe('wrong');
    expect(step.state.misses).toBe(1);
    state = lines.carryOn(step.state);
    expect(state.ply).toBe(1);
    expect(state.phase).toBe('play');
  });

  it('the next line is the next of the group, then a fresh group', () => {
    const state = lines.beginLines(drawn);
    expect(lines.needsDraw(state)).toBe(drawn.length < 2);
    const second = lines.nextLine(state);
    expect(second.at).toBe(1);
    expect(lines.needsDraw(second)).toBe(true);
    const fresh = lines.nextLine(second, drawn);
    expect(fresh.group).toBe(2);
    expect(fresh.at).toBe(0);
    expect(fresh.line).toBe(drawn[0]);
  });

  it('changing the grade puts the card back first', () => {
    const done = lines.graded(playThrough(lines.beginLines(drawn)).state, { tipId: 'x' } as never, 'easy');
    const step = lines.regrade(done, 'hard');
    expect(step.effects).toEqual([
      { kind: 'gradeLine', repertoireId: drawn[0].repertoireId, tipId: drawn[0].tipId, grade: 'hard', before: { tipId: 'x' } },
    ]);
    expect(step.state.graded?.grade).toBe('hard');
  });
});
