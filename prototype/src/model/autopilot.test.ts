import { describe, expect, it } from 'vitest';
import {
  chooseStart,
  COLD_GAP,
  coldNeed,
  insideStart,
  prepDepth,
  roundSpan,
  runGap,
  runNeed,
  RUNS_PER_DAY,
  splitItems,
  startKind,
  survivalPlanFor,
  type StartKind,
} from './autopilot';
import { nodeById, openingTree } from './openingTree';
import { referenceIndex } from './referenceIndex';
import type { TrainingItem } from './session';
import { addLine, createRepertoire } from './repertoire';
import { createCard } from './srs';
import type { Card } from './types';

describe('a Survival round from a recommendation', () => {
  const tree = openingTree(referenceIndex());
  const sicilian = nodeById(tree, 'e4 c5');

  it('leans on popular lines for a test and weak ones for a review', () => {
    expect(survivalPlanFor({ focus: 'test', opening: sicilian, color: 'b', start: 'first' })).toEqual({
      color: 'b',
      toward: sicilian.id,
      enter: false,
      lean: 'popular',
      at: null,
    });
    expect(survivalPlanFor({ focus: 'review', opening: sicilian, color: 'b', start: 'inside' }).lean).toBe('weak');
    expect(survivalPlanFor({ focus: 'review', opening: sicilian, color: 'b', start: 'inside' }).enter).toBe(true);
  });
});

describe('where a run starts', () => {
  it('starts at the opening position when nothing needs another start', () => {
    expect(chooseStart({ recent: [], cold: 0.5, inside: null })).toBe('position');
    expect(chooseStart({ recent: ['position'], cold: 0, inside: 0.9 })).toBe('position');
  });

  it('starts from move one when the way in has gone unplayed, and deeper in when a position is due', () => {
    expect(chooseStart({ recent: [], cold: 1.5, inside: null })).toBe('cold');
    expect(chooseStart({ recent: [], cold: 0, inside: 1.2 })).toBe('inside');
  });

  it('gives the run to whichever start needs it more', () => {
    expect(chooseStart({ recent: [], cold: 1.2, inside: 3 })).toBe('inside');
    expect(chooseStart({ recent: [], cold: 4, inside: 3 })).toBe('cold');
  });

  it('never starts the same way twice running, other than at the opening position', () => {
    expect(chooseStart({ recent: ['cold'], cold: 9, inside: null })).toBe('position');
    expect(chooseStart({ recent: ['inside'], cold: 0, inside: 9 })).toBe('position');
    expect(chooseStart({ recent: ['inside'], cold: 2, inside: 9 })).toBe('cold');
  });

  it('starts from move one at least every third run, whatever the need', () => {
    expect(chooseStart({ recent: ['position', 'inside'], cold: 0, inside: 9 })).toBe('cold');
    expect(chooseStart({ recent: ['cold', 'position'], cold: 0, inside: null })).toBe('position');
    const recent: StartKind[] = [];
    for (let i = 0; i < 9; i++) recent.push(chooseStart({ recent, cold: 0, inside: null }));
    expect(recent.filter((kind) => kind === 'cold')).toHaveLength(3);
  });

  it('starts the first run of an opening at its position, whatever is owed', () => {
    expect(chooseStart({ recent: ['position', 'position'], cold: 9, inside: 9, firstTime: true })).toBe('position');
  });

  it('names the start a round was given', () => {
    const tree = openingTree(referenceIndex());
    const pick = { focus: 'review' as const, opening: nodeById(tree, 'd4 d5 c4'), color: 'w' as const, start: 'inside' as const };
    expect(startKind({ pick, at: null })).toBe('position');
    expect(startKind({ pick, at: ['d4', 'd5', 'c4', 'e6'] })).toBe('inside');
    expect(startKind({ pick: { ...pick, start: 'first' }, at: null })).toBe('cold');
  });
});

describe('need, counted in runs', () => {
  const NOW = 1_000_000;
  const item = (id: string, pathSans: string[]): TrainingItem => ({
    cardId: id,
    repertoireId: 'rep',
    repertoireName: 'White',
    key: id,
    fen: '',
    orientation: 'white',
    expected: [],
    pathSans,
    continuation: [],
    depth: pathSans.length,
  });
  const card = (id: string, extra: Partial<Card> = {}): Card => ({
    ...createCard(id, 'rep', id, ''),
    stage: 'review',
    interval: 1,
    due: NOW + 1e9,
    ...extra,
  });

  it('comes due by runs since a run last asked it, against its interval', () => {
    expect(runGap(card('a', { interval: 1 }))).toBe(RUNS_PER_DAY);
    expect(runGap(card('a', { stage: 'learning' }))).toBe(2);
    expect(runNeed(card('a', { testedRound: 10 }), 13, NOW)).toBe(1);
    expect(runNeed(card('a', { testedRound: 10 }), 11, NOW)).toBeCloseTo(1 / 3);
  });

  it('keeps to its date until a run has asked it', () => {
    expect(runNeed(card('a', { due: NOW - 1 }), 50, NOW)).toBe(1);
    expect(runNeed(card('a'), 50, NOW)).toBe(0);
  });

  it('splits the way in from the positions inside the opening', () => {
    const items = [item('w1', []), item('w2', ['d4', 'd5']), item('at', ['d4', 'd5', 'c4']), item('in', ['d4', 'd5', 'c4', 'e6', 'Nc3'])];
    const { wayIn, inside } = splitItems(items, 3);
    expect(wayIn.map((i) => i.cardId)).toEqual(['w1', 'w2']);
    expect(inside.map((i) => i.cardId)).toEqual(['in']);
  });

  it('wants the way in by how long its stalest move has gone unplayed', () => {
    const wayIn = [item('w1', []), item('w2', ['d4', 'd5'])];
    expect(coldNeed(wayIn, { w1: card('w1', { testedRound: 8 }), w2: card('w2', { testedRound: 4 }) }, 10)).toBe(6 / COLD_GAP);
    expect(coldNeed(wayIn, { w1: card('w1', { testedRound: 8 }) }, 10)).toBe(Infinity);
    expect(coldNeed([], {}, 10)).toBe(0);
  });

  it('starts deeper in at the position most overdue', () => {
    const inside = [item('a', ['e4', 'e5', 'Nf3']), item('b', ['e4', 'e5', 'Bc4'])];
    const cards = { a: card('a', { testedRound: 5 }), b: card('b', { testedRound: 1 }) };
    expect(insideStart(inside, cards, { accuracy: 1, round: 10, now: NOW })?.item.cardId).toBe('b');
  });

  it('has no inside start with nothing due while your prep is holding', () => {
    const inside = [item('a', ['e4', 'e5', 'Nf3'])];
    expect(insideStart(inside, { a: card('a', { testedRound: 9 }) }, { accuracy: 1, round: 10, now: NOW })).toBeNull();
  });

  it('takes the position you answer worst while your prep keeps missing', () => {
    const inside = [item('a', ['e4', 'e5', 'Nf3']), item('c', ['e4', 'e5', 'Bc4'])];
    const cards = { a: card('a', { testedRound: 9 }), c: card('c', { testedRound: 9, lapses: 4, incorrect: 5, correct: 1 }) };
    expect(insideStart(inside, cards, { accuracy: 0.8, round: 10, now: NOW })).toMatchObject({ need: 1, item: { cardId: 'c' } });
  });
});

describe('how far into your prep a run starts', () => {
  const tree = openingTree(referenceIndex());
  const ruy = nodeById(tree, 'e4 e5 Nf3 Nc6 Bb5');
  const line = 'e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O'.split(' ');
  const rep = addLine(createRepertoire('White', 'w'), line).rep;

  it('counts up to your last prepared move, and stops at the first one you lack', () => {
    const prepAt = (fen: string) => (fen.includes(' w ') ? ['e4', 'Nf3', 'Bb5', 'Ba4', 'O-O'] : []);
    expect(prepDepth(line, 'w', prepAt)).toBe(9);
    expect(prepDepth(['e4', 'e5', 'Nc3'], 'w', prepAt)).toBe(1);
  });

  it('counts the moves played for you whatever they were', () => {
    expect(prepDepth(['d4', 'd5', 'c4'], 'w', () => [], 2)).toBe(2);
  });

  it('starts a run inside the opening that far along the prep', () => {
    expect(roundSpan(rep, { focus: 'test', opening: ruy, color: 'w', start: 'inside' }, null)).toEqual({ played: 5, total: 9 });
  });

  it('starts from move one with nothing played', () => {
    expect(roundSpan(rep, { focus: 'test', opening: ruy, color: 'w', start: 'first' }, null)).toEqual({ played: 0, total: 9 });
  });

  it('starts at a position that far along', () => {
    expect(roundSpan(rep, { focus: 'test', opening: ruy, color: 'w', start: 'inside' }, line.slice(0, 7))).toEqual({ played: 7, total: 9 });
  });

  it('has nothing to show without a repertoire', () => {
    expect(roundSpan(null, { focus: 'test', opening: ruy, color: 'w', start: 'inside' }, null)).toEqual({ played: 0, total: 0 });
  });
});
