import { describe, expect, it } from 'vitest';
import { openingTree } from './openingTree';
import { referenceIndex } from './referenceIndex';
import {
  accuracy,
  applyResult,
  creditedNodes,
  dayKey,
  EMPTY_SCORE,
  expectedAccuracy,
  nodeStats,
  normalizeScore,
  RATING,
  rankOf,
  ratedNodes,
  ratingAfter,
  ratingSwing,
  recordRound,
  streak,
  TIERS,
  type MoveResult,
  type ScoreState,
} from './scoring';

const tree = openingTree(referenceIndex());
const NAJDORF = 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6';
const DRAGON = 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6';
const SICILIAN = 'e4 c5';

function result(over: Partial<MoveResult> = {}): MoveResult {
  return {
    mode: 'run',
    line: [...NAJDORF.split(' '), 'Be3'],
    color: 'w',
    correct: true,
    rated: true,
    at: Date.UTC(2026, 8, 13, 12),
    ...over,
  };
}

/** Answer the same line `n` times over, right or wrong. */
function answered(starred: string[], n: number, correct: boolean, from = EMPTY_SCORE): ScoreState {
  let state = from;
  for (let i = 0; i < n; i += 1) {
    state = applyResult(state, tree, starred, result({ correct })).state;
  }
  return state;
}

describe('what a result does to a rating', () => {
  it('splits the step by the accuracy the rating already expects', () => {
    expect(expectedAccuracy(0)).toBeCloseTo(0.5, 6);
    expect(expectedAccuracy(RATING.scale)).toBeCloseTo(10 / 11, 6);
    // Whatever the rating, the two outcomes are one step apart; where the step
    // falls between them is what pins the number to your real accuracy rather
    // than to how much you play. Low down a find is worth most of it, high up
    // a miss costs most of it.
    for (const rating of [200, 400, 700]) {
      const swing = ratingSwing(rating);
      expect(swing.up - swing.down).toBeCloseTo(RATING.step, 4);
    }
    expect(ratingSwing(200).up).toBeGreaterThan(10);
    const high = ratingSwing(700);
    expect(high.up).toBeLessThan(2);
    expect(high.down).toBeLessThan(-35);
  });

  it('never falls below the floor', () => {
    expect(ratingAfter(0, false)).toBe(RATING.floor);
    expect(ratingAfter(5, false)).toBe(RATING.floor);
  });

  it('still climbs at the top of the ladder, so King is reachable', () => {
    expect(ratingSwing(TIERS[TIERS.length - 1].at).up).toBeGreaterThan(0);
  });

  it('settles at the accuracy actually held', () => {
    // Nine right, one wrong, over and over: the rating stops climbing near the
    // rating whose expected accuracy is 90%.
    let rating = 0;
    for (let i = 0; i < 4000; i += 1) rating = ratingAfter(rating, i % 10 !== 0);
    expect(expectedAccuracy(rating)).toBeCloseTo(0.9, 1);
  });
});

describe('the ladder', () => {
  it('climbs pawn to king', () => {
    expect(TIERS.map((tier) => tier.name)).toEqual(['Pawn', 'Knight', 'Bishop', 'Rook', 'Queen', 'King']);
    expect(rankOf(0)).toMatchObject({ reached: 0, held: null, heldLabel: 'Unrated', nextLabel: 'Pawn' });
    expect(rankOf(100)).toMatchObject({ reached: 1, heldLabel: 'Pawn', nextLabel: 'Knight' });
    expect(rankOf(99).heldLabel).toBe('Unrated');
    expect(rankOf(700).heldLabel).toBe('Queen');
  });

  it('holds the top piece with nothing left to work toward', () => {
    const top = rankOf(900);
    expect(top.heldLabel).toBe('King');
    expect(top.next).toBeNull();
    expect(top.nextLabel).toBeNull();
    expect(top.progress).toBe(1);
  });

  it('measures progress between the piece held and the next', () => {
    expect(rankOf(175).progress).toBeCloseTo(0.5, 5);
    expect(rankOf(100).progress).toBe(0);
    expect(rankOf(249).progress).toBeLessThan(1);
  });

  it('spaces the pieces by the accuracy each one asks for', () => {
    const asks = TIERS.map((tier) => Math.round(expectedAccuracy(tier.at) * 100));
    expect(asks).toEqual([63, 78, 89, 94, 97, 99]);
  });
});

describe('which openings a result touches', () => {
  it('credits the deepest opening on the line and every ancestor', () => {
    expect(creditedNodes(tree, [...NAJDORF.split(' '), 'Be3'])).toEqual([
      'e4',
      SICILIAN,
      'e4 c5 Nf3 d6',
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6',
      NAJDORF,
      `${NAJDORF} Be3`,
    ]);
    // 1.Nh3 is one of the two first moves the book does not hold at all.
    expect(creditedNodes(tree, ['Nh3', 'h6'])).toEqual([]);
  });

  it('rates every starred opening the line is inside, widest first', () => {
    const line = [...NAJDORF.split(' '), 'Be3'];
    expect(ratedNodes(tree, [NAJDORF, SICILIAN], line)).toEqual([SICILIAN, NAJDORF]);
    // A Dragon move is inside the starred Sicilian and outside the Najdorf.
    expect(ratedNodes(tree, [NAJDORF, SICILIAN], DRAGON.split(' '))).toEqual([SICILIAN]);
    expect(ratedNodes(tree, [], line)).toEqual([]);
    expect(ratedNodes(tree, ['d4'], line)).toEqual([]);
  });

  it('never rates the whole book, however it is starred', () => {
    expect(ratedNodes(tree, [''], [...NAJDORF.split(' '), 'Be3'])).toEqual([]);
  });
});

describe('applying a result', () => {
  it('moves the starred openings and nothing else', () => {
    const { state, moves } = applyResult(EMPTY_SCORE, tree, [NAJDORF, SICILIAN], result());
    expect(moves.map((move) => move.id)).toEqual([SICILIAN, NAJDORF]);
    expect(nodeStats(state, NAJDORF).rating).toBeGreaterThan(0);
    expect(nodeStats(state, SICILIAN).rating).toBeGreaterThan(0);
    // Credited for activity, but not starred, so not rated.
    expect(nodeStats(state, 'e4').rating).toBe(0);
    expect(nodeStats(state, 'e4').answered).toBe(1);
    expect(state.global.rating).toBe(0);
  });

  it('pulls a rating down on a miss', () => {
    const up = answered([NAJDORF], 20, true);
    const down = applyResult(up, tree, [NAJDORF], result({ correct: false }));
    expect(down.state.nodes[NAJDORF].rating).toBeLessThan(up.nodes[NAJDORF].rating);
    expect(down.moves[0].after).toBeLessThan(down.moves[0].before);
  });

  it('records an unrated mode without moving anything', () => {
    const { state, moves } = applyResult(EMPTY_SCORE, tree, [NAJDORF], result({ mode: 'drill', rated: false }));
    expect(moves).toEqual([]);
    expect(nodeStats(state, NAJDORF).rating).toBe(0);
    expect(nodeStats(state, NAJDORF).rated).toBe(0);
    expect(nodeStats(state, NAJDORF).answered).toBe(1);
    expect(nodeStats(state, NAJDORF).byMode.drill.answered).toBe(1);
  });

  it('flags the answer that crosses a piece, up or down', () => {
    let state = EMPTY_SCORE;
    let promotions = 0;
    for (let i = 0; i < 10; i += 1) {
      const applied = applyResult(state, tree, [NAJDORF], result());
      state = applied.state;
      promotions += applied.moves.filter((move) => move.promotion === 1).length;
    }
    expect(promotions).toBe(1);
    expect(rankOf(nodeStats(state, NAJDORF).rating).heldLabel).toBe('Pawn');

    // Back down through the same rung.
    let demotions = 0;
    for (let i = 0; i < 30; i += 1) {
      const applied = applyResult(state, tree, [NAJDORF], result({ correct: false }));
      state = applied.state;
      demotions += applied.moves.filter((move) => move.promotion === -1).length;
    }
    expect(demotions).toBe(1);
    expect(nodeStats(state, NAJDORF).rating).toBe(RATING.floor);
  });

  it('keeps accuracy from answers', () => {
    let state = applyResult(EMPTY_SCORE, tree, [], result()).state;
    state = applyResult(state, tree, [], result({ correct: false })).state;
    const najdorf = nodeStats(state, NAJDORF);
    expect(najdorf.answered).toBe(2);
    expect(najdorf.correct).toBe(1);
    expect(accuracy(najdorf)).toBe(0.5);
    expect(accuracy(nodeStats(state, 'd4'))).toBeNull();
  });

  it('files the day, and where the rating stood at the end of it', () => {
    const at = new Date(2026, 8, 13, 9).getTime();
    const { state } = applyResult(EMPTY_SCORE, tree, [NAJDORF], result({ at }));
    expect(state.global.days[dayKey(at)]).toEqual({ answered: 1, correct: 1, rounds: 0, rating: null });
    const day = nodeStats(state, NAJDORF).days[dayKey(at)];
    expect(day?.answered).toBe(1);
    expect(day?.rating).toBe(nodeStats(state, NAJDORF).rating);
  });

  it('touches only the global record when the book names nothing on the line', () => {
    const { state } = applyResult(EMPTY_SCORE, tree, [NAJDORF], result({ line: ['Nh3', 'h6'] }));
    expect(state.global.answered).toBe(1);
    expect(Object.keys(state.nodes)).toEqual([]);
  });
});

describe('rounds', () => {
  const at = new Date(2026, 8, 13, 9).getTime();

  it('counts a round against its opening, the openings above it, and the whole game', () => {
    const state = recordRound(EMPTY_SCORE, tree, {
      mode: 'run', openingId: NAJDORF, color: 'w', answered: 8, correct: 8, perfect: true, at,
    });
    expect(state.rounds).toHaveLength(1);
    expect(state.global.byMode.run.rounds).toBe(1);
    expect(nodeStats(state, NAJDORF).byMode.run.rounds).toBe(1);
    expect(nodeStats(state, SICILIAN).byMode.run.rounds).toBe(1);
    expect(nodeStats(state, SICILIAN).byMode.run.lastAt).toBe(at);
    expect(nodeStats(state, SICILIAN).byMode.drill.rounds).toBe(0);
    expect(nodeStats(state, SICILIAN).bestRun).toBe(8);
    expect(state.global.days[dayKey(at)]?.rounds).toBe(1);
  });

  it('counts the root round only on the whole game', () => {
    const state = recordRound(EMPTY_SCORE, tree, {
      mode: 'drill', openingId: '', color: 'b', answered: 10, correct: 9, perfect: false, at,
    });
    expect(state.global.byMode.drill.rounds).toBe(1);
    expect(Object.keys(state.nodes)).toEqual([]);
  });

  it('leaves a rating alone', () => {
    const rated = answered([NAJDORF], 5, true);
    const after = recordRound(rated, tree, {
      mode: 'run', openingId: NAJDORF, color: 'w', answered: 5, correct: 5, perfect: true, at,
    });
    expect(after.nodes[NAJDORF].rating).toBe(rated.nodes[NAJDORF].rating);
  });
});

describe('streaks', () => {
  const DAY = 86_400_000;
  const noon = new Date(2026, 8, 13, 12).getTime();
  const played = (days: number[]) => {
    let state = EMPTY_SCORE;
    for (const back of days) {
      state = recordRound(state, tree, {
        mode: 'run', openingId: '', color: 'w', answered: 1, correct: 1, perfect: false,
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
    const fixed = normalizeScore({ nodes: { e4: { answered: 9 } as never } });
    expect(fixed.nodes.e4.answered).toBe(9);
    expect(fixed.nodes.e4.rating).toBe(RATING.start);
    expect(fixed.nodes.e4.byMode.run.rounds).toBe(0);
    expect(fixed.rounds).toEqual([]);
  });

  it('drops the points a save from the scoring era carries', () => {
    const legacy = {
      total: 4200,
      global: { score: 4200, own: 12, byMode: { run: { score: 4200, rounds: 9, answered: 40, correct: 38 } } },
      nodes: { e4: { score: 900, own: 3, answered: 12, correct: 11 } },
    };
    const fixed = normalizeScore(legacy as never);
    expect('total' in fixed).toBe(false);
    expect(fixed.global.rating).toBe(RATING.start);
    expect(fixed.nodes.e4.rating).toBe(RATING.start);
    expect('score' in fixed.nodes.e4).toBe(false);
    expect('own' in fixed.nodes.e4).toBe(false);
    expect('score' in fixed.global.byMode.run).toBe(false);
    // What the player actually did is kept.
    expect(fixed.nodes.e4.answered).toBe(12);
    expect(fixed.global.byMode.run.rounds).toBe(9);
    expect(fixed.global.byMode.run.correct).toBe(38);
  });

  it('reads rounds that were saved as games, without their scores', () => {
    const round = { mode: 'run', openingId: '', color: 'w', score: 1, answered: 1, correct: 1, perfect: false, at: 5 };
    const legacy = {
      games: [round],
      global: { byMode: { run: { games: 2 } }, days: { '2026-09-13': { score: 1, answered: 1, correct: 1, games: 1 } } },
      nodes: { e4: { byMode: { drill: { games: 3 } } } },
    };
    const fixed = normalizeScore(legacy as never);
    expect(fixed.rounds).toHaveLength(1);
    expect(fixed.rounds[0].answered).toBe(1);
    expect(fixed.global.byMode.run.rounds).toBe(2);
    expect(fixed.global.days['2026-09-13'].rounds).toBe(1);
    expect(fixed.global.days['2026-09-13'].rating).toBeNull();
    expect(fixed.nodes.e4.byMode.drill.rounds).toBe(3);
    expect('games' in fixed.global.byMode.run).toBe(false);
    expect('score' in fixed.global.days['2026-09-13']).toBe(false);
  });
});
