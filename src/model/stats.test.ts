import { describe, expect, it } from 'vitest';
import { openingTree } from './openingTree';
import { referenceIndex } from './referenceIndex';
import { applyResult, EMPTY_SCORE, rankOf, recordRound, type ScoreState } from './scoring';
import {
  dailyRounds,
  favouriteness,
  niceTicks,
  ratingOverTime,
  rollingAccuracy,
  starredOpenings,
} from './stats';

const tree = openingTree(referenceIndex());
const DAY = 86_400_000;
const noon = new Date(2026, 8, 13, 12).getTime();
const NAJDORF = 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6';
const DRAGON = 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6';

/** One rated answer on a line, `back` days ago. */
function answered(
  state: ScoreState,
  line: string,
  back: number,
  correct = true,
  starred: string[] = [NAJDORF],
): ScoreState {
  return applyResult(state, tree, starred, {
    mode: 'run', line: line.split(' '), color: 'w', correct, rated: true, at: noon - back * DAY,
  }).state;
}

function round(state: ScoreState, openingId: string, back: number): ScoreState {
  return recordRound(state, tree, {
    mode: 'run', openingId, color: 'w', answered: 1, correct: 1, perfect: false, at: noon - back * DAY,
  });
}

describe('series', () => {
  it('lists the window oldest first, zero where nothing happened', () => {
    let state = round(EMPTY_SCORE, NAJDORF, 1);
    state = round(state, NAJDORF, 0);
    state = round(state, NAJDORF, 0);
    const daily = dailyRounds(state.global, 3, noon);
    expect(daily.map((p) => p.value)).toEqual([0, 1, 2]);
    expect(daily[0].at).toBeLessThan(daily[1].at);
  });

  it('holds a rating through the days it did not move', () => {
    let state = answered(EMPTY_SCORE, NAJDORF, 1);
    const day1 = state.nodes[NAJDORF].rating;
    state = answered(state, NAJDORF, 0);
    const series = ratingOverTime(state.nodes[NAJDORF], 4, noon);
    expect(series.map((p) => p.value)).toEqual([0, 0, day1, state.nodes[NAJDORF].rating]);
  });

  it('starts the line from where the rating stood before the window', () => {
    let state = answered(EMPTY_SCORE, NAJDORF, 10);
    const before = state.nodes[NAJDORF].rating;
    state = answered(state, NAJDORF, 0);
    const series = ratingOverTime(state.nodes[NAJDORF], 3, noon);
    expect(series.map((p) => p.value)).toEqual([before, before, state.nodes[NAJDORF].rating]);
  });

  it('draws no line for an opening that has never been rated', () => {
    const state = round(EMPTY_SCORE, NAJDORF, 0);
    expect(ratingOverTime(state.nodes[NAJDORF], 30, noon)).toEqual([]);
  });

  it('smooths accuracy over a week and skips empty days', () => {
    let state = answered(EMPTY_SCORE, NAJDORF, 2, true);
    state = answered(state, NAJDORF, 2, false);
    state = answered(state, NAJDORF, 0, true);
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

describe('your openings', () => {
  it('lists the stars, best rated first, with where they sit', () => {
    const stars = [NAJDORF, DRAGON];
    let state = answered(EMPTY_SCORE, `${NAJDORF} Be3`, 0, true, stars);
    state = answered(state, `${NAJDORF} Be3`, 0, true, stars);
    const mine = starredOpenings(tree, state, stars);
    expect(mine.map((entry) => entry.node.id)).toEqual([NAJDORF, DRAGON]);
    expect(mine[0].trail).toContain('Sicilian Defence');
    // An untested star is still yours, and still Unrated.
    expect(rankOf(mine[1].stats.rating).heldLabel).toBe('Unrated');
  });

  it('leaves out the root and anything starred twice', () => {
    const mine = starredOpenings(tree, EMPTY_SCORE, ['', NAJDORF, NAJDORF]);
    expect(mine.map((entry) => entry.node.id)).toEqual([NAJDORF]);
  });

  it('draws round ticks', () => {
    expect(niceTicks(0)).toEqual([0]);
    expect(niceTicks(47)).toEqual([0, 20, 40, 60]);
    expect(niceTicks(1)).toEqual([0, 0.5, 1]);
  });
});
