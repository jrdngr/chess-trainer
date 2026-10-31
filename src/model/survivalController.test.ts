import { describe, expect, it } from 'vitest';
import { applySan, type LegalMove } from '../chess/core';
import { openingTree } from './openingTree';
import { addLine, createRepertoire } from './repertoire';
import { referenceIndex } from './referenceIndex';
import { DEFAULT_SURVIVAL, playTheirs, startSurvival } from './survival';
import {
  beginSession,
  bookRanOut,
  endRun,
  engineMove,
  judgedMove,
  noteFor,
  playPrepared,
  prepLabel,
  prepMoves,
  prepRanOut,
  type Effect,
  type Judgement,
  type RunContext,
  type RunSession,
} from './survivalController';
import type { Repertoire } from './types';

const index = referenceIndex();
const tree = openingTree(index);
const NOW = Date.parse('2026-10-01T09:00:00Z');

function whiteRep(): Repertoire {
  let rep = createRepertoire('White', 'w', 'rep_w');
  rep = addLine(rep, ['d4', 'd5', 'c4', 'e6', 'Nc3', 'Nf6', 'cxd5', 'exd5', 'Bg5'], 'seed').rep;
  return rep;
}

const ctx = (over: Partial<RunContext> = {}): RunContext => ({
  index,
  prefs: DEFAULT_SURVIVAL,
  autopilot: false,
  kindOf: () => 'book',
  lossOf: () => undefined,
  ...over,
});

function begin(): RunSession {
  const begun = startSurvival({ steer: 'lines', tree, reps: [whiteRep()], node: tree.root, color: 'w', seed: 3 })!;
  return beginSession(begun);
}

const move = (session: RunSession, san: string): LegalMove => applySan(session.state.run.fen, san)!;

/** The opponent replies `san`, as the book or the engine would. */
const theirs = (session: RunSession, san: string): RunSession => ({ ...session, state: playTheirs(session.state, san) });

const judgement = (san: string, over: Partial<Judgement> = {}): Judgement => ({
  san,
  ok: true,
  lost: 10,
  best: null,
  before: 20,
  after: 10,
  moment: false,
  found: false,
  reply: null,
  ...over,
});

const kinds = (effects: Effect[]) => effects.map((effect) => effect.kind);

describe('a run as state and events', () => {
  it('starts on prep, with nothing answered', () => {
    const session = begin();
    expect(session.prepStatus).toBe('on');
    expect(session.answers).toEqual([]);
    expect(session.ending).toBeNull();
    expect(prepMoves(session)).toEqual(['d4']);
    expect(prepLabel(session)).toBe('on');
  });

  it('a prepared move reviews its card by time, rates it and plays it', () => {
    const session = begin();
    const step = playPrepared(session, ctx(), move(session, 'd4'), 5, NOW);
    expect(kinds(step.effects)).toEqual(['buzz', 'answered', 'rate']);
    expect(step.effects[1]).toMatchObject({ kind: 'answered', repertoireId: 'rep_w', san: 'd4', grade: 'good' });
    expect(step.effects[2]).toMatchObject({ kind: 'rate', result: { correct: true, line: [], at: NOW }, earlier: [] });
    expect(step.session.state.run.played).toEqual(['d4']);
    expect(step.session.prepSeen).toBe(true);
    expect(step.session.prepTimes).toEqual([5]);
  });

  it("in Autopilot a prepared move pops its tick and time", () => {
    const session = begin();
    const step = playPrepared(session, ctx({ autopilot: true }), move(session, 'd4'), 2.4, NOW);
    expect(step.effects.find((effect) => effect.kind === 'pop')).toMatchObject({
      pop: { square: 'd4', text: '2.4s', found: true },
    });
  });

  it('a sound move off your prep is a miss: logged, rated down, flashed, and the game goes on', () => {
    let session = playPrepared(begin(), ctx(), move(begin(), 'd4'), 1, NOW).session;
    session = theirs(session, 'd5');
    const step = judgedMove(session, ctx(), judgement('Nf3'), 3, NOW);
    expect(kinds(step.effects)).toEqual(['rate', 'missed', 'buzz', 'pop', 'miss', 'note', 'missedBest']);
    expect(step.effects[1]).toMatchObject({ played: 'Nf3', expected: 'c4' });
    expect(step.effects[4]).toMatchObject({ miss: { expected: 'c4', from: 'c2', to: 'c4' } });
    expect(step.session.prepStatus).toBe('off');
    expect(step.session.state.misses).toHaveLength(1);
    expect(step.session.ending).toBeNull();
    expect(prepLabel(step.session)).toBe('off');
  });

  it('a blunder ends the run with the move left off the board', () => {
    let session = playPrepared(begin(), ctx(), move(begin(), 'd4'), 1, NOW).session;
    session = theirs(session, 'd5');
    const step = judgedMove(session, ctx(), judgement('g4', { ok: false, lost: 300, best: 'c4', reply: 'c8g4' }), 3, NOW);
    const done = step.effects.find((effect) => effect.kind === 'finish');
    expect(done).toMatchObject({ finish: { how: { kind: 'blunder', played: 'g4', best: 'c4' } } });
    expect(step.session.ending?.kind).toBe('blunder');
    expect(step.session.state.run.played).toEqual(['d4', 'd5']);
  });

  it('after the run ends, nothing lands', () => {
    const ended = endRun(begin()).session;
    expect(ended.ending).toEqual({ kind: 'ended' });
    expect(endRun(ended).effects).toEqual([]);
    expect(playPrepared(ended, ctx(), move(ended, 'd4'), 1, NOW).effects).toEqual([]);
    expect(engineMove(ended, 'd4').session).toBe(ended);
  });

  it('when prep runs out cleanly, the book phase starts and the line is where growing begins', () => {
    let session = begin();
    for (const [mine, reply] of [['d4', 'd5'], ['c4', 'e6'], ['Nc3', 'Nf6'], ['cxd5', 'exd5'], ['Bg5', 'c6']]) {
      session = playPrepared(session, ctx(), move(session, mine), 1, NOW).session;
      session = theirs(session, reply);
    }
    expect(prepMoves(session)).toEqual([]);
    const done = prepRanOut(session, index);
    expect(done.prepStatus).toBe('complete');
    expect(done.bookTo).toBe(10);
    expect(done.prepEnd).toEqual(['d4', 'd5', 'c4', 'e6', 'Nc3', 'Nf6', 'cxd5', 'exd5', 'Bg5', 'c6']);
    expect(prepLabel(done)).toBe('book');
    expect(prepRanOut(done, index)).toBe(done);
    // Ending now is a clean finish of the line.
    expect(endRun(done).effects[0]).toMatchObject({ finish: { clean: done.prepEnd, stub: false } });
  });

  it('the book phase ends where the book has nothing', () => {
    const session: RunSession = { ...begin(), prepStatus: 'complete', bookTo: 2 };
    expect(bookRanOut(session, index)).toBe(false);
    const nowhere = ['a4', 'h5', 'Ra3', 'Rh6', 'Rb3', 'Rg6', 'Rc3', 'Rf6'].reduce<RunSession>((s, san) => theirs(s, san), session);
    expect(bookRanOut(nowhere, index)).toBe(true);
  });
});

describe('what a judged move earned', () => {
  it('names a moment found or missed, a mission, and a broken combo', () => {
    expect(noteFor({ moment: { found: true, bonus: 5 } } as never, null)).toEqual({ text: 'Found it · +5', tone: 'good' });
    expect(noteFor({ moment: { found: false, bonus: 0 } } as never, 'Nxe5')).toEqual({
      text: 'Missed it · Nxe5 was there',
      tone: 'bad',
    });
    expect(noteFor({ combo: 'broke' } as never, null)).toEqual({ text: 'Combo broken', tone: 'bad' });
    expect(noteFor({} as never, null)).toBeNull();
  });
});
