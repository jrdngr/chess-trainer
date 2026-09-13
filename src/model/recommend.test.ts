import { describe, expect, it } from 'vitest';
import { openingTree } from './openingTree';
import { referenceIndex } from './referenceIndex';
import { addLine, createRepertoire } from './repertoire';
import {
  BRAKE,
  candidates,
  cardStrength,
  drillNeed,
  FUN,
  GROWTH_FLOOR,
  growthNeed,
  HELD_DAYS,
  readiness,
  rank,
  recommend,
  repairNeed,
  runNeed,
  recentCount,
  saturate,
  type RecommendInput,
} from './recommend';
import { applyEvent, EMPTY_SCORE, recordGame, type ScoreMode, type ScoreState } from './scoring';
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

/** Every other position held for weeks, the rest due: Drill and Growth both have work. */
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
    recentModes: [],
    now: T,
    ...patch,
  };
}

function played(state: ScoreState, mode: ScoreMode, openingId: string, at: number): ScoreState {
  return recordGame(state, tree, {
    mode, openingId, color: 'w', score: 1, answered: 1, correct: 1, perfect: false, at,
  });
}

describe('need', () => {
  it('saturates', () => {
    expect(saturate(0, 10)).toBe(0);
    expect(saturate(10, 10)).toBe(0.5);
    expect(saturate(1000, 10)).toBeGreaterThan(0.98);
  });

  it('rises with due cards and never runs away', () => {
    expect(drillNeed(0, 0, 8)).toBe(0);
    expect(drillNeed(2, 0, 8)).toBeLessThan(drillNeed(20, 0, 8));
    expect(drillNeed(400, 0, 8)).toBeLessThanOrEqual(1);
    expect(drillNeed(0, 30, 8)).toBeLessThan(drillNeed(20, 0, 8));
  });

  it('costs a hole by how early and how often you fall into it', () => {
    const hole = (depth: number, share: number) => ({
      path: Array(depth).fill('x'), fen: '', san: 'e5', share, games: 1, after: '', nodeId: null,
    });
    expect(growthNeed([])).toBe(0);
    expect(growthNeed([hole(1, 30)])).toBeGreaterThan(growthNeed([hole(9, 30)]));
    expect(growthNeed([hole(3, 30)])).toBeGreaterThan(growthNeed([hole(3, 2)]));
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
    const holes = [{ path: ['x'], fen: '', san: 'e5', share: 30, games: 1, after: '', nodeId: null }];
    const full = growthNeed(holes, 1);
    const half = growthNeed(holes, 0.5);
    const none = growthNeed(holes, 0);
    expect(full).toBe(growthNeed(holes));
    expect(half).toBeLessThan(full * 0.35);
    expect(half).toBeGreaterThan(none);
    // Never silent: a thin opening still gets grown now and then.
    expect(none).toBeGreaterThan(0);
    expect(none).toBeCloseTo(full * GROWTH_FLOOR, 5);
  });

  it('weighs repairs by the worst and by how many', () => {
    const item = (weight: number) => ({
      id: `x${weight}`, kind: 'offprep' as const, source: 'games' as const, repertoireId: 'r', color: 'w' as const,
      key: '', fen: '', path: [], lineText: '', games: 2, results: { wins: 0, draws: 0, losses: 2 },
      played: [], expected: [], weight,
    });
    expect(repairNeed([])).toBe(0);
    expect(repairNeed([item(1)])).toBeLessThan(repairNeed([item(6)]));
    expect(repairNeed([item(1)])).toBeLessThan(repairNeed([item(1), item(1), item(1)]));
  });

  it('always asks for a run, and harder for untested prep or a first run', () => {
    expect(runNeed(0, true)).toBe(0.4);
    expect(runNeed(0, false)).toBe(0.55);
    expect(runNeed(20, true)).toBeGreaterThan(runNeed(2, true));
  });
});

describe('ranking', () => {
  const cand = (mode: ScoreMode, need: number, lastAt: number | null = null, openingId = '') => ({
    mode, openingId, color: 'w' as const, need, work: 1, lastAt, starred: false,
  });

  it('weights fun and never lets it override a real need', () => {
    expect(FUN.run).toBeGreaterThan(FUN.drill);
    expect(FUN.drill).toBeGreaterThan(FUN.repair);
    expect(FUN.repair).toBeGreaterThan(FUN.growth);
    const ranked = rank([cand('run', 0.4), cand('growth', 0.4)], []);
    expect(ranked[0].mode).toBe('run');
    const loud = rank([cand('run', 0.4), cand('growth', 1)], []);
    expect(loud[0].mode).toBe('growth');
  });

  it('brakes a mode by how much of the recent play it has been', () => {
    expect(recentCount(['run', 'run', 'drill'], 'drill')).toBe(1);
    expect(recentCount(['drill', 'run', 'run'], 'run')).toBe(2);
    expect(recentCount(['run', 'run', 'run', 'run', 'run', 'run', 'drill'], 'run')).toBe(4);
    expect(recentCount([], 'run')).toBe(0);
    const fresh = rank([cand('run', 0.5), cand('drill', 0.5)], []);
    expect(fresh[0].mode).toBe('run');
    const braked = rank([cand('run', 0.5), cand('drill', 0.5)], ['run', 'drill', 'run']);
    expect(braked[0].mode).toBe('drill');
    // Taking turns is not an escape: a third mode still comes round.
    const turns = rank([cand('run', 0.5), cand('growth', 0.5), cand('drill', 0.4)], ['run', 'growth', 'run', 'growth']);
    expect(turns[0].mode).toBe('drill');
    expect(BRAKE).toBeLessThan(1);
  });

  it('lifts what has been left longest', () => {
    const ranked = rank([cand('drill', 0.5, T, 'a'), cand('drill', 0.5, T - 9 * DAY, 'b')], []);
    expect(ranked[0].openingId).toBe('b');
  });

  it('lifts a starred opening', () => {
    const ranked = rank(
      [{ ...cand('drill', 0.5, null, 'a') }, { ...cand('drill', 0.5, null, 'b'), starred: true }],
      [],
    );
    expect(ranked[0].openingId).toBe('b');
  });
});

describe('what gets recommended', () => {
  it('sends a brand new install to Run in the selection', () => {
    const pick = recommend(input());
    expect(pick.mode).toBe('run');
    expect(pick.opening.depth).toBe(0);
    expect(['w', 'b']).toContain(pick.color);
    const narrowed = recommend(input({ selection: { color: 'b', opening: NAJDORF } }));
    expect(narrowed).toMatchObject({ mode: 'run', color: 'b' });
    expect(narrowed.opening.id).toBe(NAJDORF);
  });

  it('offers only openings the player has prep in, besides the selection itself', () => {
    const reps = [rep('w', [`${NAJDORF} Be3 e5`])];
    const ids = new Set(candidates(input({ reps })).map((c) => c.openingId));
    expect(ids.has('')).toBe(true);
    expect(ids.has('e4')).toBe(true);
    expect(ids.has(NAJDORF)).toBe(true);
    expect(ids.has('d4')).toBe(false);
    expect(ids.has('e4 e5')).toBe(false);
  });

  it('drills the variation whose cards are due, once Run has had its turn', () => {
    const reps = [rep('w', [`${NAJDORF} Be3 e5 Nb3 Be6`, `${DRAGON} Be3 Bg7 f3 O-O`])];
    const cards = cardsFor(reps, true, (line) => line.includes('a6'));
    const quiet = cardsFor(reps, false, (line) => !line.includes('a6'));
    let score = EMPTY_SCORE;
    // Run has just been played twice; every opening has had a run.
    score = played(score, 'run', NAJDORF, T - 3);
    score = played(score, 'run', DRAGON, T - 2);
    // No holes worth filling, so the decision is Run against Drill.
    const pick = recommend(
      input({
        reps, cards: { ...cards, ...quiet }, score, selection: { color: 'w', opening: 'e4' },
        recentModes: ['run', 'run', 'run', 'run', 'run'], growth: { minShare: 60, maxPly: 18 },
      }),
    );
    expect(pick.mode).toBe('drill');
    expect(pick.color).toBe('w');
    // The Najdorf holds the due cards; nothing deeper holds most of them.
    expect(pick.opening.id).toBe(NAJDORF);
  });

  it('stays at the family when the need is spread across its variations', () => {
    const reps = [rep('w', [`${NAJDORF} Be3 e5 Nb3 Be6`, `${DRAGON} Be3 Bg7 f3 O-O`, 'e4 c5 Nf3 e6 d4 cxd4 Nxd4 a6 Bd3 Bc5'])];
    const cards = cardsFor(reps, true);
    const pick = recommend(
      input({
        reps, cards, selection: { color: 'w', opening: 'e4' }, recentModes: ['run', 'run', 'run'],
        growth: { minShare: 60, maxPly: 18 },
      }),
    );
    expect(pick.mode).toBe('drill');
    // Three variations each hold a third: the family keeps the game.
    expect(pick.opening.id).toBe('e4 c5');
  });

  it('never offers a mode with nothing in it', () => {
    const modes = new Set(candidates(input({ reps: [rep('w', ['e4 e5 Nf3 Nc6 Bb5'])] })).map((c) => c.mode));
    expect(modes.has('repair')).toBe(false);
    expect(modes.has('drill')).toBe(true);
    expect(modes.has('run')).toBe(true);
  });

  it('respects a fixed colour', () => {
    const reps = [rep('w', [`${NAJDORF} Be3`]), rep('b', ['d4 Nf6 c4 g6 Nc3 Bg7 e4 d6'])];
    for (const c of candidates(input({ reps, selection: { color: 'b', opening: '' } }))) expect(c.color).toBe('b');
  });

  it('rotates: every mode with work comes round given a few games', () => {
    const reps = [rep('w', [`${NAJDORF} Be3 e5 Nb3 Be6`, `${DRAGON} Be3 Bg7 f3 O-O`])];
    const cards = halfHeldCards(reps);
    let score = EMPTY_SCORE;
    const seen = new Set<ScoreMode>();
    const recent: ScoreMode[] = [];
    for (let i = 0; i < 12; i += 1) {
      const pick = recommend(input({ reps, cards, score, recentModes: recent, selection: { color: 'w', opening: '' } }));
      seen.add(pick.mode);
      recent.push(pick.mode);
      score = played(score, pick.mode, pick.opening.id, T + i);
      score = applyEvent(score, tree, { mode: pick.mode, points: 1, line: pick.opening.sans, color: 'w', answered: true, correct: true, at: T + i });
    }
    expect(seen.has('run')).toBe(true);
    expect(seen.has('drill')).toBe(true);
    expect(seen.has('growth')).toBe(true);
    expect(seen.size).toBe(3);
  });

  it('waits to grow an opening until its prep is held', () => {
    const reps = [rep('w', [`${NAJDORF} Be3 e5 Nb3 Be6`, `${DRAGON} Be3 Bg7 f3 O-O`])];
    const play = (cards: Record<string, Card>) => {
      let score = EMPTY_SCORE;
      const recent: ScoreMode[] = [];
      let growths = 0;
      for (let i = 0; i < 20; i += 1) {
        const pick = recommend(input({ reps, cards, score, recentModes: recent, selection: { color: 'w', opening: '' } }));
        if (pick.mode === 'growth') growths += 1;
        recent.push(pick.mode);
        score = played(score, pick.mode, pick.opening.id, T + i);
      }
      return growths;
    };
    // Everything due: the same holes, but the prep is not ready to get wider.
    const learning = play(cardsFor(reps, true));
    // Nothing seen yet is no better: unseen positions still need drilling.
    const unseen = play({});
    // Held for weeks: the holes ask at full voice.
    const held = play(heldCards(reps));
    expect(held).toBeGreaterThan(learning);
    expect(held).toBeGreaterThan(unseen);
    expect(learning).toBeLessThanOrEqual(2);
    expect(unseen).toBeLessThanOrEqual(2);
  });

  it('is stable: the same state always gives the same answer', () => {
    const reps = [rep('w', [`${NAJDORF} Be3 e5`])];
    const a = recommend(input({ reps }));
    const b = recommend(input({ reps }));
    expect(a).toEqual(b);
  });
});
