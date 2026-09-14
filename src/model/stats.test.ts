import { describe, expect, it } from 'vitest';
import { openingTree } from './openingTree';
import { referenceIndex } from './referenceIndex';
import { applyEvent, EMPTY_SCORE, recordRound, type ScoreState } from './scoring';
import { cumulativeScore, dailyScore, favouriteness, niceTicks, rollingAccuracy, topOpenings } from './stats';

const tree = openingTree(referenceIndex());
const DAY = 86_400_000;
const noon = new Date(2026, 8, 13, 12).getTime();
const NAJDORF = 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6';
const DRAGON = 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6';

function earned(state: ScoreState, line: string, points: number, back: number, correct = true): ScoreState {
  return applyEvent(state, tree, {
    mode: 'run', points, line: line.split(' '), color: 'w', answered: true, correct, at: noon - back * DAY,
  });
}

function round(state: ScoreState, openingId: string, back: number): ScoreState {
  return recordRound(state, tree, {
    mode: 'run', openingId, color: 'w', score: 1, answered: 1, correct: 1, perfect: false, at: noon - back * DAY,
  });
}

describe('series', () => {
  it('lists the window oldest first, zero where nothing happened', () => {
    let state = earned(EMPTY_SCORE, NAJDORF, 5, 1);
    state = earned(state, NAJDORF, 2, 0);
    const daily = dailyScore(state.global, 3, noon);
    expect(daily.map((p) => p.value)).toEqual([0, 5, 2]);
    expect(daily[0].at).toBeLessThan(daily[1].at);
  });

  it('starts the climb from what was earned before the window', () => {
    let state = earned(EMPTY_SCORE, NAJDORF, 40, 10);
    state = earned(state, NAJDORF, 5, 1);
    state = earned(state, NAJDORF, 2, 0);
    expect(cumulativeScore(state.global, 3, noon).map((p) => p.value)).toEqual([40, 45, 47]);
  });

  it('smooths accuracy over a week and skips empty days', () => {
    let state = earned(EMPTY_SCORE, NAJDORF, 1, 2, true);
    state = earned(state, NAJDORF, 0, 2, false);
    state = earned(state, NAJDORF, 1, 0, true);
    const series = rollingAccuracy(state.global, 5, noon);
    // Days 4 and 3 back have nothing in their week; from day 2 the week holds answers.
    expect(series.length).toBe(3);
    expect(series[0].value).toBe(0.5);
    expect(series[2].value).toBeCloseTo(2 / 3, 5);
  });
});

describe('favouriteness', () => {
  it('ranks an opening among the siblings actually played', () => {
    let state = EMPTY_SCORE;
    state = round(state, NAJDORF, 0);
    state = round(state, NAJDORF, 1);
    state = round(state, DRAGON, 0);
    const najdorf = favouriteness(tree, state, NAJDORF, 30, noon)!;
    expect(najdorf.rank).toBe(1);
    expect(najdorf.of).toBe(2);
    expect(najdorf.siblings.map((s) => s.node.id)).toEqual([NAJDORF, DRAGON]);
    expect(najdorf.siblings[0].share).toBeCloseTo(2 / 3, 5);
    expect(najdorf.parent?.name).toBe('Sicilian Defence: Modern Variations, Main Line');
    expect(favouriteness(tree, state, DRAGON, 30, noon)?.rank).toBe(2);
  });

  it('is nothing for an opening never played, and for the root', () => {
    expect(favouriteness(tree, EMPTY_SCORE, NAJDORF, 30, noon)).toBeNull();
    expect(favouriteness(tree, EMPTY_SCORE, '', 30, noon)).toBeNull();
  });
});

describe('the openings that matter', () => {
  it('lists scored openings, best first, with where they sit', () => {
    let state = earned(EMPTY_SCORE, `${NAJDORF} Be3`, 7, 0);
    state = earned(state, 'd4 d5 c4 e6', 3, 0);
    const top = topOpenings(tree, state);
    expect(top[0].node.name).toBe("King's Pawn Game");
    expect(top.some((entry) => entry.node.id === NAJDORF)).toBe(true);
    const najdorf = top.find((entry) => entry.node.id === NAJDORF)!;
    expect(najdorf.trail).toContain('Sicilian Defence');
    expect(top.every((entry) => entry.node.depth > 0)).toBe(true);
  });

  it('draws round ticks', () => {
    expect(niceTicks(0)).toEqual([0]);
    expect(niceTicks(47)).toEqual([0, 20, 40, 60]);
    expect(niceTicks(1)).toEqual([0, 0.5, 1]);
  });
});
