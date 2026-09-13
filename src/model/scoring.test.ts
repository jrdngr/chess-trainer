import { describe, expect, it } from 'vitest';
import { openingTree } from './openingTree';
import { referenceIndex } from './referenceIndex';
import {
  accuracy,
  applyEvent,
  comboBonus,
  creditedNodes,
  dayKey,
  EMPTY_SCORE,
  FIRST_MILESTONE,
  ladderMultiplier,
  MILESTONE_RATIO,
  MILESTONES,
  milestoneOf,
  milestoneThreshold,
  nodeStats,
  normalizeScore,
  POINTS,
  recordGame,
  speedBonus,
  streak,
  type ScoreEvent,
} from './scoring';

const tree = openingTree(referenceIndex());
const NAJDORF = 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6';

function event(over: Partial<ScoreEvent> = {}): ScoreEvent {
  return {
    mode: 'run',
    points: 3,
    line: [...NAJDORF.split(' '), 'Be3'],
    color: 'w',
    answered: true,
    correct: true,
    at: Date.UTC(2026, 8, 13, 12),
    ...over,
  };
}

describe('what a move pays', () => {
  it('pays the speed bonus by halves of the clock, and nothing once it runs out', () => {
    expect(speedBonus(0, 10)).toBe(POINTS.speed.fast);
    expect(speedBonus(4.9, 10)).toBe(POINTS.speed.fast);
    expect(speedBonus(5, 10)).toBe(POINTS.speed.quick);
    expect(speedBonus(9.9, 10)).toBe(POINTS.speed.quick);
    expect(speedBonus(10, 10)).toBe(0);
    expect(speedBonus(30, 10)).toBe(0);
  });

  it('pays no speed bonus without a clock', () => {
    expect(speedBonus(0, null)).toBe(0);
  });

  it('pays the combo from the third move in a row', () => {
    expect(comboBonus(1)).toBe(0);
    expect(comboBonus(2)).toBe(0);
    expect(comboBonus(3)).toBe(POINTS.combo.per);
    expect(comboBonus(9)).toBe(POINTS.combo.per);
  });

  it('never pays negative points anywhere', () => {
    const all = [
      ...Object.values(POINTS.run),
      ...Object.values(POINTS.drill),
      ...Object.values(POINTS.growth),
      ...Object.values(POINTS.repair),
    ];
    for (const n of all) expect(n).toBeGreaterThan(0);
  });
});

describe('milestones', () => {
  it('climbs infrared to ultraviolet and keeps going', () => {
    expect(MILESTONES.map((m) => m.name)).toEqual([
      'Infrared', 'Red', 'Orange', 'Yellow', 'Green', 'Blue', 'Indigo', 'Violet', 'Ultraviolet',
    ]);
    expect(milestoneOf(0)).toMatchObject({ reached: 0, held: null, floor: 0, ceiling: FIRST_MILESTONE });
    expect(milestoneOf(0).next.name).toBe('Infrared');
    expect(milestoneOf(FIRST_MILESTONE)).toMatchObject({ reached: 1, heldLabel: 'Infrared', nextLabel: 'Red' });
    const top = milestoneOf(milestoneThreshold(8));
    expect(top.heldLabel).toBe('Ultraviolet');
    expect(top.nextLabel).toBe('Ultraviolet II');
    expect(milestoneOf(milestoneThreshold(10)).heldLabel).toBe('Ultraviolet III');
    expect(milestoneOf(milestoneThreshold(10)).held?.color).toBe(MILESTONES[8].color);
  });

  it('grows geometrically', () => {
    expect(milestoneThreshold(1) / milestoneThreshold(0)).toBeCloseTo(MILESTONE_RATIO, 1);
    expect(milestoneThreshold(8)).toBeGreaterThan(4000);
  });

  it('measures progress between the last milestone and the next', () => {
    const half = FIRST_MILESTONE / 2;
    expect(milestoneOf(half).progress).toBeCloseTo(0.5, 5);
    expect(milestoneOf(FIRST_MILESTONE - 1).progress).toBeLessThan(1);
    expect(milestoneOf(FIRST_MILESTONE).progress).toBe(0);
  });

  it('asks more of a wider region', () => {
    expect(ladderMultiplier(1)).toBe(4);
    expect(ladderMultiplier(2)).toBe(2);
    expect(ladderMultiplier(3)).toBe(1);
    expect(ladderMultiplier(6)).toBe(1);
    expect(milestoneThreshold(0, 4)).toBe(FIRST_MILESTONE * 4);
  });
});

describe('where points go', () => {
  it('credits the deepest opening on the line and every ancestor', () => {
    expect(creditedNodes(tree, [...NAJDORF.split(' '), 'Be3'])).toEqual([
      'e4',
      'e4 c5',
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3',
      NAJDORF,
      `${NAJDORF} Be3`,
    ]);
    expect(creditedNodes(tree, ['a3', 'h6'])).toEqual([]);
  });

  it('moves the global total and every credited opening', () => {
    const state = applyEvent(EMPTY_SCORE, tree, event());
    expect(state.total).toBe(3);
    expect(state.global.score).toBe(3);
    expect(nodeStats(state, 'e4').score).toBe(3);
    expect(nodeStats(state, 'e4 c5').score).toBe(3);
    expect(nodeStats(state, NAJDORF).score).toBe(3);
    expect(nodeStats(state, 'd4').score).toBe(0);
    expect(nodeStats(state, 'e4 c5').byMode.run.score).toBe(3);
    expect(nodeStats(state, 'e4 c5').byMode.drill.score).toBe(0);
  });

  it('counts the event as its own only on the deepest node', () => {
    const state = applyEvent(EMPTY_SCORE, tree, event());
    expect(nodeStats(state, `${NAJDORF} Be3`).own).toBe(1);
    expect(nodeStats(state, NAJDORF).own).toBe(0);
    expect(nodeStats(state, 'e4').own).toBe(0);
  });

  it('keeps accuracy from answers, not from bonuses', () => {
    let state = applyEvent(EMPTY_SCORE, tree, event({ points: 1 }));
    state = applyEvent(state, tree, event({ points: 0, correct: false }));
    state = applyEvent(state, tree, event({ points: 5, answered: false, correct: false }));
    const najdorf = nodeStats(state, NAJDORF);
    expect(najdorf.answered).toBe(2);
    expect(najdorf.correct).toBe(1);
    expect(accuracy(najdorf)).toBe(0.5);
    expect(accuracy(nodeStats(state, 'd4'))).toBeNull();
    expect(state.total).toBe(6);
  });

  it('files the day', () => {
    const at = new Date(2026, 8, 13, 9).getTime();
    const state = applyEvent(EMPTY_SCORE, tree, event({ at, points: 2 }));
    expect(state.global.days[dayKey(at)]).toEqual({ score: 2, answered: 1, correct: 1, games: 0 });
    expect(nodeStats(state, 'e4').days[dayKey(at)]?.score).toBe(2);
  });

  it('touches only the total when the book names nothing on the line', () => {
    const state = applyEvent(EMPTY_SCORE, tree, event({ line: ['a3', 'h6'], points: 4 }));
    expect(state.total).toBe(4);
    expect(Object.keys(state.nodes)).toEqual([]);
  });
});

describe('games', () => {
  const at = new Date(2026, 8, 13, 9).getTime();

  it('counts a game against its opening, the openings above it, and the total', () => {
    const state = recordGame(EMPTY_SCORE, tree, {
      mode: 'run', openingId: NAJDORF, color: 'w', score: 12, answered: 8, correct: 8, perfect: true, at,
    });
    expect(state.games).toHaveLength(1);
    expect(state.global.byMode.run.games).toBe(1);
    expect(nodeStats(state, NAJDORF).byMode.run.games).toBe(1);
    expect(nodeStats(state, 'e4 c5').byMode.run.games).toBe(1);
    expect(nodeStats(state, 'e4 c5').byMode.run.lastAt).toBe(at);
    expect(nodeStats(state, 'e4 c5').byMode.drill.games).toBe(0);
    expect(nodeStats(state, 'e4 c5').bestRun).toBe(8);
    expect(state.global.days[dayKey(at)]?.games).toBe(1);
  });

  it('counts the root game only on the total', () => {
    const state = recordGame(EMPTY_SCORE, tree, {
      mode: 'drill', openingId: '', color: 'b', score: 5, answered: 10, correct: 9, perfect: false, at,
    });
    expect(state.global.byMode.drill.games).toBe(1);
    expect(Object.keys(state.nodes)).toEqual([]);
  });
});

describe('streaks', () => {
  const DAY = 86_400_000;
  const noon = new Date(2026, 8, 13, 12).getTime();
  const played = (days: number[]) => {
    let state = EMPTY_SCORE;
    for (const back of days) {
      state = recordGame(state, tree, {
        mode: 'run', openingId: '', color: 'w', score: 1, answered: 1, correct: 1, perfect: false,
        at: noon - back * DAY,
      });
    }
    return state.global;
  };

  it('counts days in a row up to today', () => {
    expect(streak(played([0, 1, 2]), noon)).toBe(3);
    expect(streak(played([0, 2]), noon)).toBe(1);
    expect(streak(played([]), noon)).toBe(0);
  });

  it('survives not having played yet today', () => {
    expect(streak(played([1, 2, 3]), noon)).toBe(3);
    expect(streak(played([2, 3]), noon)).toBe(0);
  });
});

describe('a saved record', () => {
  it('fills in whatever an older save lacks', () => {
    const fixed = normalizeScore({ total: 9, nodes: { e4: { score: 9 } as never } });
    expect(fixed.total).toBe(9);
    expect(fixed.global.score).toBe(0);
    expect(fixed.nodes.e4.byMode.run.games).toBe(0);
    expect(fixed.games).toEqual([]);
  });
});
