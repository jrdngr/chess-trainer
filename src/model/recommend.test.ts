import { describe, expect, it } from 'vitest';
import { applySan, positionKey, START_FEN } from '../chess/core';
import { openingTree } from './openingTree';
import { referenceIndex } from './referenceIndex';
import { addLine, createRepertoire } from './repertoire';
import {
  BRAKE,
  candidates,
  cardStrength,
  FUN,
  GROWTH_FLOOR,
  growNeed,
  HELD_DAYS,
  MAX_NEW_MOVES,
  readiness,
  rank,
  recommend,
  reviewNeed,
  testNeed,
  recentCount,
  saturate,
  weighHoles,
  type Focus,
  type RecommendInput,
} from './recommend';
import type { RepairItem } from './repair';
import { EMPTY_SCORE, recordRound, type ScoreState } from './scoring';
import { allItems } from './session';
import { createCard } from './srs';
import type { Card, Repertoire } from './types';

const index = referenceIndex();
const tree = openingTree(index);
const T = 1_700_000_000_000;
const DAY = 86_400_000;

const NAJDORF = 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6';
const DRAGON = 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6';

function rep(color: 'w' | 'b', lines: string[], addedAt = T - 10 * DAY): Repertoire {
  let out = createRepertoire('Test', color, `r_${color}`);
  for (const line of lines) out = addLine(out, line.split(' '), 'reference').rep;
  for (const node of Object.values(out.nodes)) node.addedAt = addedAt;
  return out;
}

/** Every position in these repertoires as a card, due or not. */
function cardsFor(
  reps: Repertoire[],
  due: boolean,
  only?: (line: string[]) => boolean,
  interval = 3,
): Record<string, Card> {
  const out: Record<string, Card> = {};
  for (const item of allItems(reps)) {
    if (only && !only(item.pathSans)) continue;
    const card = createCard(item.cardId, item.repertoireId, item.key, item.fen, T - DAY);
    out[item.cardId] = { ...card, stage: 'review', interval, due: due ? T - 1 : T + 5 * DAY };
  }
  return out;
}

/** Every position as a card that has been held for weeks: prep ready to grow. */
function heldCards(reps: Repertoire[]): Record<string, Card> {
  return cardsFor(reps, false, undefined, 3 * HELD_DAYS);
}

/** Every other position held for weeks, the rest due: Review and Grow both have work. */
function halfHeldCards(reps: Repertoire[]): Record<string, Card> {
  const held = heldCards(reps);
  const due = cardsFor(reps, true);
  const out: Record<string, Card> = {};
  allItems(reps).forEach((item, i) => {
    out[item.cardId] = i % 2 === 0 ? held[item.cardId] : due[item.cardId];
  });
  return out;
}

function input(patch: Partial<RecommendInput> = {}): RecommendInput {
  return {
    tree,
    selection: { color: 'random', opening: '' },
    reps: [],
    cards: {},
    repairs: [],
    score: EMPTY_SCORE,
    starred: [],
    newPerSession: 8,
    growth: { minShare: 1, maxPly: 18 },
    recentFocuses: [],
    now: T,
    ...patch,
  };
}

/** A round played: every Autopilot round is a Run. */
function played(state: ScoreState, openingId: string, at: number): ScoreState {
  return recordRound(state, tree, {
    mode: 'run', openingId, color: 'w', score: 1, answered: 1, correct: 1, perfect: false, at,
  });
}

function repair(patch: Partial<RepairItem>): RepairItem {
  return {
    id: 'x', kind: 'offprep', source: 'games', repertoireId: 'r_w', color: 'w', key: '', fen: START_FEN,
    path: [], lineText: '', games: 2, results: { wins: 0, draws: 0, losses: 2 }, played: [], expected: [],
    weight: 1, ...patch,
  };
}

describe('need', () => {
  it('saturates', () => {
    expect(saturate(0, 10)).toBe(0);
    expect(saturate(10, 10)).toBe(0.5);
    expect(saturate(1000, 10)).toBeGreaterThan(0.98);
  });

  it('rises with due cards and never runs away', () => {
    expect(reviewNeed(0, 0, 8)).toBe(0);
    expect(reviewNeed(2, 0, 8)).toBeLessThan(reviewNeed(20, 0, 8));
    expect(reviewNeed(400, 0, 8)).toBeLessThanOrEqual(1);
    expect(reviewNeed(0, 30, 8)).toBeLessThan(reviewNeed(20, 0, 8));
  });

  it('costs a hole by how early and how often you fall into it', () => {
    const hole = (depth: number, share: number) => ({
      path: Array(depth).fill('x'), fen: '', san: 'e5', share, games: 1, after: '', nodeId: null, reach: 1,
    });
    expect(growNeed([])).toBe(0);
    expect(growNeed([hole(1, 30)])).toBeGreaterThan(growNeed([hole(9, 30)]));
    expect(growNeed([hole(3, 30)])).toBeGreaterThan(growNeed([hole(3, 2)]));
  });

  it('holds a position only once it has graduated, is not due, and has lasted', () => {
    const card = createCard('c', 'r', 'k', '', T - DAY);
    expect(cardStrength(undefined, T)).toBe(0);
    expect(cardStrength({ ...card, stage: 'new' }, T)).toBe(0);
    expect(cardStrength({ ...card, stage: 'learning', due: T + DAY }, T)).toBe(0);
    expect(cardStrength({ ...card, stage: 'review', interval: 30, due: T - 1 }, T)).toBe(0);
    const fresh = cardStrength({ ...card, stage: 'review', interval: 1, due: T + DAY }, T);
    const held = cardStrength({ ...card, stage: 'review', interval: HELD_DAYS, due: T + DAY }, T);
    expect(fresh).toBeGreaterThan(0);
    expect(fresh).toBeLessThan(held);
    expect(held).toBe(1);
    expect(cardStrength({ ...card, stage: 'review', interval: 90, due: T + DAY }, T)).toBe(1);
  });

  it('is ready to grow when its prep is held, and when there is none yet', () => {
    expect(readiness([])).toBe(1);
    expect(readiness([1, 1, 1])).toBe(1);
    expect(readiness([0, 0, 0])).toBe(0);
    expect(readiness([1, 0])).toBe(0.5);
  });

  it('quietens growth steeply while the prep is still being learned', () => {
    const holes = [{ path: ['x'], fen: '', san: 'e5', share: 30, games: 1, after: '', nodeId: null, reach: 1 }];
    const full = growNeed(holes, 1);
    const half = growNeed(holes, 0.5);
    const none = growNeed(holes, 0);
    expect(full).toBe(growNeed(holes));
    expect(half).toBeLessThan(full * 0.35);
    expect(half).toBeGreaterThan(none);
    // Never silent: a thin opening still gets grown now and then.
    expect(none).toBeGreaterThan(0);
    expect(none).toBeCloseTo(full * GROWTH_FLOOR, 5);
  });

  it('does not make an opening with nothing in it wait to be held', () => {
    const holes = [{ path: ['x'], fen: '', san: 'e5', share: 30, games: 1, after: '', nodeId: null, reach: 1 }];
    // Bare: the gate is gone, however little of the prep is held.
    expect(growNeed(holes, 0, 1)).toBeCloseTo(growNeed(holes, 1), 5);
    expect(growNeed(holes, 1, 1)).toBeCloseTo(growNeed(holes, 1), 5);
    // Half bare lifts the floor halfway, and unheld prep still asks less.
    expect(growNeed(holes, 0, 0.5)).toBeGreaterThan(growNeed(holes, 0));
    expect(growNeed(holes, 0, 0.5)).toBeLessThan(growNeed(holes, 1, 0.5));
    // A broad opening is gated exactly as it was.
    expect(growNeed(holes, 0.5, 0)).toBe(growNeed(holes, 0.5));
  });

  it('always asks for a test, and harder for untested prep or a first run', () => {
    expect(testNeed(0, true)).toBe(0.4);
    expect(testNeed(0, false)).toBe(0.55);
    expect(testNeed(20, true)).toBeGreaterThan(testNeed(2, true));
  });

  it('weighs a hole up by the games you reached it with nothing', () => {
    const after = applySan(applySan(START_FEN, 'e4')!.after, 'c5')!.after;
    const hole = { path: ['e4'], fen: '', san: 'c5', share: 10, games: 1, after, nodeId: null, reach: 1 };
    expect(weighHoles([hole], [])[0].share).toBe(10);
    const weighed = weighHoles([hole], [repair({ kind: 'unprepared', fen: after, games: 3 })]);
    expect(weighed[0].share).toBe(40);
    // A slip somewhere you had a move is not evidence for a hole.
    expect(weighHoles([hole], [repair({ kind: 'offprep', fen: after, games: 3 })])[0].share).toBe(10);
  });
});

describe('ranking', () => {
  const cand = (focus: Focus, need: number, lastAt: number | null = null, openingId = '') => ({
    focus, openingId, color: 'w' as const, need, work: 1, lastAt, starred: false, newMoves: 0,
  });

  it('tilts away from Grow and never lets that override a real need', () => {
    expect(FUN.test).toBeGreaterThan(FUN.grow);
    expect(FUN.review).toBeGreaterThan(FUN.grow);
    const ranked = rank([cand('test', 0.4), cand('grow', 0.4)], []);
    expect(ranked[0].focus).toBe('test');
    const loud = rank([cand('test', 0.4), cand('grow', 1)], []);
    expect(loud[0].focus).toBe('grow');
  });

  it('brakes a focus by how much of the recent play it has been', () => {
    expect(recentCount(['test', 'test', 'review'], 'review')).toBe(1);
    expect(recentCount(['review', 'test', 'test'], 'test')).toBe(2);
    expect(recentCount(['test', 'test', 'test', 'test', 'test', 'test', 'review'], 'test')).toBe(4);
    expect(recentCount([], 'test')).toBe(0);
    const fresh = rank([cand('test', 0.5), cand('review', 0.5)], []);
    expect(fresh[0].focus).toBe('test');
    const braked = rank([cand('test', 0.5), cand('review', 0.5)], ['test', 'review', 'test']);
    expect(braked[0].focus).toBe('review');
    // Taking turns is not an escape: a third focus still comes round.
    const turns = rank([cand('test', 0.5), cand('grow', 0.5), cand('review', 0.4)], ['test', 'grow', 'test', 'grow']);
    expect(turns[0].focus).toBe('review');
    expect(BRAKE).toBeLessThan(1);
  });

  it('lifts what has been left longest', () => {
    const ranked = rank([cand('review', 0.5, T, 'a'), cand('review', 0.5, T - 9 * DAY, 'b')], []);
    expect(ranked[0].openingId).toBe('b');
  });

  it('lifts a starred opening', () => {
    const ranked = rank(
      [{ ...cand('review', 0.5, null, 'a') }, { ...cand('review', 0.5, null, 'b'), starred: true }],
      [],
    );
    expect(ranked[0].openingId).toBe('b');
  });
});

describe('what gets recommended', () => {
  it('sends a brand new install to grow a first line in the selection', () => {
    const pick = recommend(input());
    expect(pick.focus).toBe('grow');
    expect(pick.newMoves).toBe(MAX_NEW_MOVES);
    expect(pick.opening.depth).toBe(0);
    expect(['w', 'b']).toContain(pick.color);
    const narrowed = recommend(input({ selection: { color: 'b', opening: NAJDORF } }));
    expect(narrowed).toMatchObject({ focus: 'grow', color: 'b' });
    expect(narrowed.opening.id).toBe(NAJDORF);
  });

  it('offers a side with no prep nothing but a Grow round', () => {
    const reps = [rep('w', [`${NAJDORF} Be3 e5`])];
    const black = candidates(input({ reps, selection: { color: 'b', opening: '' } }));
    expect(black).toHaveLength(1);
    expect(black[0]).toMatchObject({ focus: 'grow', openingId: '', color: 'b', newMoves: MAX_NEW_MOVES });
  });

  it('offers only openings the player has prep in, besides the selection itself', () => {
    const reps = [rep('w', [`${NAJDORF} Be3 e5`])];
    const ids = new Set(candidates(input({ reps, selection: { color: 'w', opening: '' } })).map((c) => c.openingId));
    expect(ids.has('')).toBe(true);
    expect(ids.has('e4')).toBe(true);
    expect(ids.has(NAJDORF)).toBe(true);
    expect(ids.has('d4')).toBe(false);
    expect(ids.has('e4 e5')).toBe(false);
  });

  it('never tests an opening with nothing prepared in it', () => {
    const reps = [rep('w', [`${NAJDORF} Be3 e5`])];
    const tests = candidates(input({ reps, selection: { color: 'w', opening: '' } })).filter((c) => c.focus === 'test');
    expect(tests.length).toBeGreaterThan(0);
    for (const c of tests) expect(['', 'e4', 'e4 c5', NAJDORF].includes(c.openingId) || c.openingId.startsWith('e4 c5')).toBe(true);
    const empty = candidates(input({ reps, selection: { color: 'w', opening: 'd4' } }));
    expect(empty.some((c) => c.focus === 'test')).toBe(false);
  });

  it('reviews the variation whose cards are due, once Test has had its turn', () => {
    const reps = [rep('w', [`${NAJDORF} Be3 e5 Nb3 Be6`, `${DRAGON} Be3 Bg7 f3 O-O`])];
    const cards = cardsFor(reps, true, (line) => line.includes('a6'));
    const quiet = cardsFor(reps, false, (line) => !line.includes('a6'));
    let score = EMPTY_SCORE;
    // Rounds went through both lines, so nothing in them is staler than the rest.
    score = played(score, `${NAJDORF} Be3`, T - 3);
    score = played(score, `${DRAGON} Be3 Bg7 f3`, T - 2);
    // No holes worth filling, so the decision is Test against Review.
    const pick = recommend(
      input({
        reps, cards: { ...cards, ...quiet }, score, selection: { color: 'w', opening: 'e4' },
        recentFocuses: ['test', 'test', 'test', 'test', 'test'], growth: { minShare: 60, maxPly: 18 },
      }),
    );
    expect(pick.focus).toBe('review');
    expect(pick.newMoves).toBe(0);
    expect(pick.color).toBe('w');
    // The Najdorf holds the due cards; nothing deeper holds most of them.
    expect(pick.opening.id).toBe(NAJDORF);
  });

  it('stays at the family when the need is spread across its variations', () => {
    const reps = [rep('w', [`${NAJDORF} Be3 e5 Nb3 Be6`, `${DRAGON} Be3 Bg7 f3 O-O`, 'e4 c5 Nf3 e6 d4 cxd4 Nxd4 a6 Bd3 Bc5'])];
    const cards = cardsFor(reps, true);
    const pick = recommend(
      input({
        reps, cards, selection: { color: 'w', opening: 'e4' }, recentFocuses: ['test', 'test', 'test'],
        growth: { minShare: 60, maxPly: 18 },
      }),
    );
    expect(pick.focus).toBe('review');
    // Three variations each hold a third: the family keeps the round.
    expect(pick.opening.id).toBe('e4 c5');
  });

  it('counts a position your games got wrong as due', () => {
    const reps = [rep('w', ['e4 e5 Nf3 Nc6 Bb5 a6 Ba4'])];
    const cards = cardsFor(reps, false);
    const before = candidates(input({ reps, cards, selection: { color: 'w', opening: '' } }));
    const fen = applySan(applySan(START_FEN, 'e4')!.after, 'e5')!.after;
    const slip = repair({ kind: 'offprep', fen, key: positionKey(fen), path: ['e4', 'e5'], games: 4 });
    const after = candidates(input({ reps, cards, repairs: [slip], selection: { color: 'w', opening: '' } }));
    const review = (list: typeof before) => list.find((c) => c.focus === 'review' && c.openingId === '');
    expect(review(before)).toBeUndefined();
    expect(review(after)?.need).toBeGreaterThan(0);
  });

  it('respects a fixed colour', () => {
    const reps = [rep('w', [`${NAJDORF} Be3`]), rep('b', ['d4 Nf6 c4 g6 Nc3 Bg7 e4 d6'])];
    for (const c of candidates(input({ reps, selection: { color: 'b', opening: '' } }))) expect(c.color).toBe('b');
  });

  it('rotates: every focus with work comes round given a few rounds', () => {
    const reps = [rep('w', [`${NAJDORF} Be3 e5 Nb3 Be6`, `${DRAGON} Be3 Bg7 f3 O-O`])];
    const cards = halfHeldCards(reps);
    let score = EMPTY_SCORE;
    const seen = new Set<Focus>();
    const recent: Focus[] = [];
    for (let i = 0; i < 12; i += 1) {
      const pick = recommend(input({ reps, cards, score, recentFocuses: recent, selection: { color: 'w', opening: '' } }));
      seen.add(pick.focus);
      recent.push(pick.focus);
      score = played(score, pick.opening.id, T + i);
    }
    expect(seen.has('test')).toBe(true);
    expect(seen.has('review')).toBe(true);
    expect(seen.has('grow')).toBe(true);
  });

  it('grows a bare opening while it is still being learned, and harder once it is held', () => {
    // Two Sicilian lines and nothing else: everything else Black plays is
    // unanswered, so this repertoire is bare however well it is known.
    const reps = [rep('w', [`${NAJDORF} Be3 e5 Nb3 Be6`, `${DRAGON} Be3 Bg7 f3 O-O`])];
    const play = (cards: Record<string, Card>) => {
      let score = EMPTY_SCORE;
      const recent: Focus[] = [];
      let grows = 0;
      for (let i = 0; i < 20; i += 1) {
        const pick = recommend(input({ reps, cards, score, recentFocuses: recent, selection: { color: 'w', opening: '' } }));
        if (pick.focus === 'grow') {
          grows += 1;
          // The allowance is always the whole of it; the line spends what it needs.
          expect(pick.newMoves).toBe(MAX_NEW_MOVES);
        }
        recent.push(pick.focus);
        score = played(score, pick.opening.id, T + i);
      }
      return { grows };
    };
    // Everything due, and nothing seen yet: the prep is not held.
    const learning = play(cardsFor(reps, true));
    const unseen = play({});
    // Held for weeks: the holes ask at full voice.
    const held = play(heldCards(reps));
    expect(held.grows).toBeGreaterThanOrEqual(learning.grows);
    expect(held.grows).toBeGreaterThanOrEqual(unseen.grows);
    // A repertoire this bare is not made to wait for its cards to mature:
    // what it cannot meet will be played against it whatever they say.
    expect(learning.grows).toBeGreaterThan(0);
    expect(unseen.grows).toBeGreaterThan(0);
  });

  it('is stable: the same state always gives the same answer', () => {
    const reps = [rep('w', [`${NAJDORF} Be3 e5`])];
    const a = recommend(input({ reps }));
    const b = recommend(input({ reps }));
    expect(a).toEqual(b);
  });
});
