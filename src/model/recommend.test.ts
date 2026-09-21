import { describe, expect, it } from 'vitest';
import { applySan, positionKey, START_FEN } from '../chess/core';
import { openingTree } from './openingTree';
import { referenceIndex } from './referenceIndex';
import { addLine, createRepertoire } from './repertoire';
import {
  BRAKE,
  candidates,
  DEPTH,
  effectiveLevel,
  isSteered,
  narrowingBar,
  rank,
  recommend,
  reviewNeed,
  testNeed,
  TEST_FLOOR,
  recentCount,
  saturate,
  STEER_GAP,
  steeredRecently,
  type Focus,
  type RecommendInput,
  type Recommendation,
} from './recommend';
import { markSeen } from './freshness';
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

/** Every position as a card that has been held for weeks: nothing due. */
function heldCards(reps: Repertoire[]): Record<string, Card> {
  return cardsFor(reps, false, undefined, 60);
}

/** Every other position held for weeks, the rest due: Test and Review both have work. */
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
    recentFocuses: [],
    now: T,
    ...patch,
  };
}

/** A recommendation the test expects to exist. */
function must(pick: Recommendation | null): Recommendation {
  if (!pick) throw new Error('nothing recommended');
  return pick;
}

/** A round played: every Autopilot round is a Run. */
function played(state: ScoreState, openingId: string, at: number): ScoreState {
  return recordRound(state, tree, {
    mode: 'run', openingId, color: 'w', answered: 1, correct: 1, perfect: false, at,
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

  it('always asks for a test, and harder for untested prep or a first run', () => {
    expect(testNeed(0, true)).toBe(0.4);
    expect(testNeed(0, false)).toBe(0.55);
    expect(testNeed(20, true)).toBeGreaterThan(testNeed(2, true));
  });

  it('asks for a test mostly as loudly as a line has been left, and never falls silent', () => {
    expect(testNeed(0, true, 1)).toBe(testNeed(0, true));
    expect(testNeed(0, true, 0.5)).toBeCloseTo(testNeed(0, true) * (TEST_FLOOR + (1 - TEST_FLOOR) / 2), 5);
    // Every line just run: little to test yet, but a round all the same.
    expect(testNeed(20, false, 0)).toBeGreaterThan(0);
    expect(testNeed(20, false, 0)).toBeLessThan(testNeed(20, false, 1) / 2);
    expect(TEST_FLOOR).toBeLessThan(0.5);
  });

  it('runs a line once after building it, then asks for it more quietly', () => {
    const line = 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5';
    const reps = [rep('b', [line])];
    // Cards on every position, none due, so Review has nothing to say here.
    const cards = cardsFor(reps, false);
    const base = input({ reps, cards, selection: { color: 'b', opening: 'd4 Nf6 c4 g6 Nc3 Bg7 e4' } });
    // Just built, never run: the round is a Test at full voice.
    const built = candidates({ ...base, seen: { at: {}, round: 1 } }).find((c) => c.focus === 'test');
    expect(built?.need).toBe(testNeed(0, false));
    // Just run: still a Test, since there is nothing else, but a quieter one.
    const ran = candidates({ ...base, seen: { at: markSeen({}, line.split(' '), 2), round: 2 } }).find((c) => c.focus === 'test');
    expect(ran?.need).toBeLessThan(testNeed(0, false));
    expect(ran?.need).toBeGreaterThan(0);
  });

  it('still has a round when every line was just run and nothing is due', () => {
    const line = 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5';
    const reps = [rep('b', [line])];
    const seen = { at: markSeen({}, line.split(' '), 2), round: 2 };
    const pick = recommend(input({ reps, cards: cardsFor(reps, false), seen, selection: { color: 'b', opening: '' } }));
    expect(pick).toMatchObject({ focus: 'test', color: 'b' });
  });
});

describe('ranking', () => {
  const cand = (focus: Focus, need: number, lastAt: number | null = null, openingId = '') => ({
    focus, openingId, color: 'w' as const, need, work: 1, lastAt, starred: false, level: 0,
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
    // A quieter focus still comes round once the louder one has had a run of rounds.
    const turns = rank([cand('test', 0.5), cand('review', 0.3)], ['test', 'test', 'test', 'test']);
    expect(turns[0].focus).toBe('review');
    expect(BRAKE).toBeLessThan(1);
  });

  it('lifts what has been left longest', () => {
    const ranked = rank([cand('review', 0.5, T, 'a'), cand('review', 0.5, T - 9 * DAY, 'b')], []);
    expect(ranked[0].openingId).toBe('b');
  });

  it('spends less on every level below the selection', () => {
    expect(DEPTH).toBeLessThan(1);
    const ranked = rank(
      [{ ...cand('review', 0.5, null, 'family'), level: 2 }, { ...cand('review', 0.5, null, 'first'), level: 1 }, cand('review', 0.5, null, 'top')],
      [],
    );
    expect(ranked.map((c) => c.openingId)).toEqual(['top', 'first', 'family']);
    // A stale deep opening still comes round; a fresh one does not.
    const stale = rank([{ ...cand('review', 0.5, T, 'top') }, { ...cand('review', 0.5, T - 9 * DAY, 'family'), level: 2 }], []);
    expect(stale[0].openingId).toBe('family');
    const fresh = rank([{ ...cand('review', 0.5, T - 9 * DAY, 'top') }, { ...cand('review', 0.5, T, 'family'), level: 2 }], []);
    expect(fresh[0].openingId).toBe('top');
  });

  it('lifts a starred opening one level', () => {
    const ranked = rank(
      [{ ...cand('review', 0.5, null, 'a'), level: 1 }, { ...cand('review', 0.5, null, 'b'), level: 1, starred: true }],
      [],
    );
    expect(ranked[0].openingId).toBe('b');
    expect(effectiveLevel(2, true)).toBe(1);
    expect(effectiveLevel(0, true)).toBe(0);
    // A starred family ranks like a first move, no higher.
    const tie = rank([{ ...cand('review', 0.5, null, 'a'), level: 1 }, { ...cand('review', 0.5, null, 'b'), level: 2, starred: true }], []);
    expect(tie[0].score).toBeCloseTo(tie[1].score);
  });

  it('asks more of a variation the deeper it is before steering there', () => {
    expect(narrowingBar(1)).toBeCloseTo(1 / 2);
    expect(narrowingBar(2)).toBeCloseTo(2 / 3);
    expect(narrowingBar(3)).toBeCloseTo(3 / 4);
    expect(narrowingBar(0)).toBe(narrowingBar(1));
  });
});

describe('what gets recommended', () => {
  it('has nothing for a brand new install: building is Growth, not Autopilot', () => {
    expect(recommend(input())).toBeNull();
    expect(recommend(input({ selection: { color: 'b', opening: NAJDORF } }))).toBeNull();
    expect(candidates(input())).toHaveLength(0);
  });

  it('drills only the sides with prep, and says so when the selection has none', () => {
    const white = rep('w', [`${NAJDORF} Be3`]);
    expect(must(recommend(input({ reps: [white] }))).color).toBe('w');
    expect(recommend(input({ reps: [white], selection: { color: 'b', opening: '' } }))).toBeNull();
    expect(candidates(input({ reps: [white], selection: { color: 'b', opening: '' } }))).toHaveLength(0);
  });

  it('has nothing for an opening chosen with nothing in it', () => {
    // A King's Indian player chooses the Najdorf: nothing there, however
    // many King's Indian cards are due on the way in.
    const kid = rep('b', ['d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5']);
    const due = cardsFor([kid], true);
    expect(recommend(input({ reps: [kid], cards: due, selection: { color: 'b', opening: NAJDORF } }))).toBeNull();
    // With a line in it, there is a round, and it is inside the Najdorf.
    const both = rep('b', ['d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5', `${NAJDORF} Be3 e5`]);
    const pick = must(recommend(input({ reps: [both], cards: due, selection: { color: 'b', opening: NAJDORF } })));
    expect(pick.color).toBe('b');
    expect(pick.opening.id.startsWith(NAJDORF)).toBe(true);
    // A variation of an opening the prep is in is still empty until a line reaches it.
    const samisch = 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f3';
    expect(recommend(input({ reps: [kid], selection: { color: 'b', opening: samisch } }))).toBeNull();
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
    const pick = must(
      recommend(
        input({
          reps, cards: { ...cards, ...quiet }, score, selection: { color: 'w', opening: 'e4' },
          recentFocuses: ['test', 'test', 'test', 'test', 'test'],
        }),
      ),
    );
    expect(pick.focus).toBe('review');
    expect(pick.color).toBe('w');
    // The Najdorf holds the due cards; nothing deeper holds most of them.
    expect(pick.opening.id).toBe(NAJDORF);
  });

  it('stays at the family when the need is spread across its variations', () => {
    const reps = [rep('w', [`${NAJDORF} Be3 e5 Nb3 Be6`, `${DRAGON} Be3 Bg7 f3 O-O`, 'e4 c5 Nf3 e6 d4 cxd4 Nxd4 a6 Bd3 Bc5'])];
    const cards = cardsFor(reps, true);
    const pick = must(
      recommend(input({ reps, cards, selection: { color: 'w', opening: 'e4' }, recentFocuses: ['test', 'test', 'test'] })),
    );
    expect(pick.focus).toBe('review');
    // Three variations each hold a third, so the round is given to something
    // above them rather than to whichever one happens to be largest. Which
    // ancestor that is depends on how deep the book names the Sicilian, so the
    // test asks that the pick contains the variations rather than naming it.
    expect([NAJDORF, DRAGON]).not.toContain(pick.opening.id);
    expect(NAJDORF.startsWith(pick.opening.id)).toBe(true);
    expect(pick.opening.id.startsWith('e4 c5')).toBe(true);
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

  it('rotates: both focuses come round given a few rounds', () => {
    const reps = [rep('w', [`${NAJDORF} Be3 e5 Nb3 Be6`, `${DRAGON} Be3 Bg7 f3 O-O`])];
    const cards = halfHeldCards(reps);
    let score = EMPTY_SCORE;
    const seen = new Set<Focus>();
    const recent: Focus[] = [];
    for (let i = 0; i < 12; i += 1) {
      const pick = must(recommend(input({ reps, cards, score, recentFocuses: recent, selection: { color: 'w', opening: '' } })));
      seen.add(pick.focus);
      recent.push(pick.focus);
      score = played(score, pick.opening.id, T + i);
    }
    expect(seen.has('test')).toBe(true);
    expect(seen.has('review')).toBe(true);
  });

  it('is stable: the same state always gives the same answer', () => {
    const reps = [rep('w', [`${NAJDORF} Be3 e5`])];
    const a = recommend(input({ reps }));
    const b = recommend(input({ reps }));
    expect(a).not.toBeNull();
    expect(a).toEqual(b);
  });
});

describe('where a round starts', () => {
  it('offers a Test only at the selection, and never narrows it', () => {
    const reps = [rep('w', [`${NAJDORF} Be3 e5 Nb3 Be6`, `${DRAGON} Be3 Bg7 f3 O-O`])];
    const tests = candidates(input({ reps, selection: { color: 'w', opening: '' } })).filter((c) => c.focus === 'test');
    expect(tests).toHaveLength(1);
    expect(tests[0].openingId).toBe('');
    // Every card held and nothing due: Test wins, and it is the whole selection from move one.
    const pick = must(recommend(input({ reps, cards: heldCards(reps), selection: { color: 'w', opening: '' } })));
    expect(pick.focus).toBe('test');
    expect(pick.opening.id).toBe('');
    expect(pick.start).toBe('first');
    // With a first move selected, the Test is that first move, still from move one.
    const first = must(recommend(input({ reps, cards: heldCards(reps), selection: { color: 'w', opening: 'e4' } })));
    expect(first.opening.id).toBe('e4');
    expect(first.start).toBe('first');
  });

  it('starts a family or deeper inside it, and a first move from move one', () => {
    const reps = [rep('w', [`${NAJDORF} Be3 e5 Nb3 Be6`, `${DRAGON} Be3 Bg7 f3 O-O`])];
    const cards = { ...cardsFor(reps, true, (line) => line.includes('a6')), ...cardsFor(reps, false, (line) => !line.includes('a6')) };
    const review = must(
      recommend(
        input({ reps, cards, selection: { color: 'w', opening: 'e4' }, recentFocuses: ['test', 'test', 'test', 'test', 'test'] }),
      ),
    );
    expect(review.focus).toBe('review');
    expect(review.opening.id).toBe(NAJDORF);
    expect(review.start).toBe('inside');
    // An opening chosen empty is nothing to drill, from anywhere.
    expect(recommend(input({ reps, selection: { color: 'w', opening: 'd4 d5 c4 c6' } }))).toBeNull();
    expect(recommend(input({ reps, selection: { color: 'w', opening: 'd4' } }))).toBeNull();
  });

  it('spends most rounds from move one, and steers only where the work is concentrated', () => {
    // One Caro-Kann line, learned: what happened on the home page.
    const reps = [rep('b', ['e4 c6 d4 d5 e5 Bf5 Nf3 e6 Be2 c5', 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5'])];
    const cards = halfHeldCards(reps);
    let score = EMPTY_SCORE;
    const recent: Focus[] = [];
    const steered: boolean[] = [];
    let inside = 0;
    for (let i = 0; i < 20; i += 1) {
      const selection = { color: 'b' as const, opening: '' };
      const pick = must(recommend(input({ reps, cards, score, recentFocuses: recent, recentSteered: steered, selection })));
      if (pick.start === 'inside') {
        inside += 1;
        // Never two steered rounds within the gap.
        expect(steeredRecently(steered)).toBe(false);
      } else {
        expect(pick.opening.depth).toBeLessThan(2);
      }
      recent.push(pick.focus);
      steered.push(isSteered(pick, selection));
      score = played(score, pick.opening.id, T + i);
    }
    // Rare, but not never: a one-line opening still gets drilled inside now and then.
    expect(inside).toBeGreaterThan(0);
    expect(inside).toBeLessThanOrEqual(20 / (STEER_GAP + 1));
    // A selection that is itself a family starts every round inside it, and that is not steering.
    const family = must(recommend(input({ reps, cards, recentSteered: [true, true, true], selection: { color: 'b', opening: 'e4 c6' } })));
    expect(family.start).toBe('inside');
    expect(isSteered(family, { color: 'b', opening: 'e4 c6' })).toBe(family.opening.id !== 'e4 c6');
  });
});
