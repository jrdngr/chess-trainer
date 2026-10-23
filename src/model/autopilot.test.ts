import { describe, expect, it } from 'vitest';
import { COLD_EVERY, coldStart, positionStart, prepDepth, roundSpan, survivalPlanFor } from './autopilot';
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

describe('Cold Start', () => {
  const tree = openingTree(referenceIndex());
  const qg = nodeById(tree, 'd4 d5 c4');
  const inside = { focus: 'review' as const, opening: qg, color: 'w' as const, start: 'inside' as const };
  const insides = Array.from({ length: COLD_EVERY - 1 }, () => 'inside' as const);

  it('starts from move one once the last runs all started inside', () => {
    const cold = coldStart(inside, insides);
    expect(cold).toEqual({ ...inside, start: 'first' });
    expect(survivalPlanFor(cold)).toMatchObject({ toward: qg.id, enter: false });
  });

  it('leaves the run inside until then', () => {
    expect(coldStart(inside, [])).toBe(inside);
    expect(coldStart(inside, insides.slice(1))).toBe(inside);
  });

  it('counts any run from move one, so a selection that mostly starts there is never pushed', () => {
    expect(coldStart(inside, ['first', ...insides.slice(1)])).toBe(inside);
    expect(coldStart(inside, [...insides.slice(1), 'first'])).toBe(inside);
  });

  it('comes round every fourth run when every run would start inside', () => {
    const starts: ('first' | 'inside')[] = [];
    for (let i = 0; i < 12; i++) starts.push(coldStart(inside, starts).start);
    expect(starts.filter((s) => s === 'first')).toHaveLength(12 / COLD_EVERY);
    expect(starts.slice(0, COLD_EVERY)).toEqual([...insides, 'first']);
  });
});

describe('a run that starts at a position', () => {
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
  const card = (id: string, due: number, extra: Partial<Card> = {}): Card => ({ ...createCard(id, 'rep', id, ''), stage: 'review', due, ...extra });
  const items = [item('start', []), item('a', ['e4', 'e5']), item('b', ['e4', 'c5']), item('c', ['d4', 'd5'])];
  const opts = { accuracy: 1, lastWasPosition: false, now: NOW };

  it('starts at the position most overdue', () => {
    const cards = { a: card('a', NOW - 10), b: card('b', NOW - 500), c: card('c', NOW + 10) };
    expect(positionStart(items, cards, opts)?.cardId).toBe('b');
  });

  it('never starts at move one, which is a Cold Start', () => {
    expect(positionStart(items, { start: card('start', NOW - 999) }, opts)).toBeNull();
  });

  it('starts inside with nothing due while your prep is holding', () => {
    expect(positionStart(items, { a: card('a', NOW + 10) }, opts)).toBeNull();
  });

  it('takes the position you answer worst while your prep keeps missing', () => {
    const cards = { a: card('a', NOW + 10), c: card('c', NOW + 10, { lapses: 4, incorrect: 5, correct: 1 }) };
    expect(positionStart(items, cards, { ...opts, accuracy: 0.8 })?.cardId).toBe('c');
  });

  it('never starts two runs running at a position', () => {
    expect(positionStart(items, { a: card('a', NOW - 10) }, { ...opts, lastWasPosition: true })).toBeNull();
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
