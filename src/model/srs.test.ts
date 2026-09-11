import { describe, expect, it } from 'vitest';
import {
  countDue,
  createCard,
  DAY,
  describeDelay,
  forecast,
  gradePreview,
  isDue,
  masteryBuckets,
  MINUTE,
  retention,
  review,
} from './srs';
import type { Card, Grade } from './types';

const T0 = 1_700_000_000_000;

function card(overrides: Partial<Card> = {}): Card {
  return { ...createCard('c1', 'rep', 'key', 'fen', T0), ...overrides };
}

function grade(c: Card, g: Grade, at = T0): Card {
  return review(c, g, at).card;
}

describe('review scheduling', () => {
  it('walks a new card through the learning steps', () => {
    const c0 = card();
    const c1 = grade(c0, 'good');
    expect(c1.stage).toBe('learning');
    expect(c1.step).toBe(1);
    expect(c1.due - T0).toBe(10 * MINUTE);

    const c2 = grade(c1, 'good');
    expect(c2.stage).toBe('review');
    expect(c2.interval).toBe(1);
    expect(c2.due - T0).toBe(DAY);
  });

  it('graduates immediately on easy', () => {
    const c = grade(card(), 'easy');
    expect(c.stage).toBe('review');
    expect(c.interval).toBe(4);
    expect(c.ease).toBeGreaterThan(2.5);
  });

  it('sends a failed card back to the first learning step', () => {
    const mature = card({ stage: 'review', interval: 30, reps: 6 });
    const failed = grade(mature, 'again');
    expect(failed.stage).toBe('learning');
    expect(failed.step).toBe(0);
    expect(failed.lapses).toBe(1);
    expect(failed.due - T0).toBe(10 * MINUTE);
    // The old interval is halved, not thrown away.
    expect(failed.interval).toBe(15);
  });

  it('does not count a lapse for a card still in learning', () => {
    const learning = card({ stage: 'learning', step: 1 });
    const failed = grade(learning, 'again');
    expect(failed.lapses).toBe(0);
    expect(failed.due - T0).toBe(1 * MINUTE);
  });

  it('grows review intervals by ease and shrinks ease on hard', () => {
    const c = card({ stage: 'review', interval: 10, ease: 2.5 });
    expect(grade(c, 'good').interval).toBe(25);
    const hard = grade(c, 'hard');
    expect(hard.interval).toBe(12);
    expect(hard.ease).toBe(2.35);
    expect(grade(c, 'easy').interval).toBeCloseTo(10 * 2.65 * 1.3, 1);
  });

  it('never lets ease fall below the floor', () => {
    let c = card({ stage: 'review', interval: 5 });
    for (let i = 0; i < 20; i += 1) c = grade(c, 'again', T0 + i);
    expect(c.ease).toBe(1.3);
  });

  it('caps intervals at a year', () => {
    const c = card({ stage: 'review', interval: 300, ease: 2.5 });
    expect(grade(c, 'easy').interval).toBe(365);
  });

  it('is deterministic', () => {
    const c = card({ stage: 'review', interval: 7 });
    expect(grade(c, 'good')).toEqual(grade(c, 'good'));
  });

  it('tracks attempt counters', () => {
    let c = card();
    c = grade(c, 'good');
    c = grade(c, 'again');
    c = grade(c, 'good');
    expect(c.reps).toBe(3);
    expect(c.correct).toBe(2);
    expect(c.incorrect).toBe(1);
    expect(c.lastReviewed).toBe(T0);
  });
});

describe('grade previews', () => {
  it('labels all four buttons for a new card', () => {
    const preview = gradePreview(card(), T0);
    expect(preview).toEqual({ again: '1m', hard: '1m', good: '10m', easy: '4d' });
  });

  it('labels a mature card in days', () => {
    const preview = gradePreview(card({ stage: 'review', interval: 20, ease: 2.5 }), T0);
    expect(preview.good).toBe('1.6mo');
    expect(preview.again).toBe('10m');
  });
});

describe('describeDelay', () => {
  it('formats across units', () => {
    expect(describeDelay(MINUTE)).toBe('1m');
    expect(describeDelay(3 * 3600_000)).toBe('3h');
    expect(describeDelay(2 * DAY)).toBe('2d');
    expect(describeDelay(60 * DAY)).toBe('2mo');
    expect(describeDelay(730 * DAY)).toBe('2y');
  });
});

describe('queue summaries', () => {
  const cards = [
    card({ id: 'a', due: T0 - 1000 }),
    card({ id: 'b', stage: 'review', interval: 30, due: T0 + 5 * DAY }),
    card({ id: 'c', stage: 'learning', due: T0 - 5 }),
    card({ id: 'd', stage: 'review', interval: 3, due: T0 - 5 }),
  ];

  it('counts what is due by stage', () => {
    const counts = countDue(cards, T0);
    expect(counts).toEqual({ due: 3, new: 1, learning: 1, review: 1, later: 1, total: 4 });
  });

  it('knows whether a single card is due', () => {
    expect(isDue(cards[0], T0)).toBe(true);
    expect(isDue(cards[1], T0)).toBe(false);
  });

  it('buckets cards by maturity', () => {
    expect(masteryBuckets(cards)).toEqual({ unseen: 1, learning: 1, young: 1, mature: 1 });
  });

  it('reports retention only once something was answered', () => {
    expect(retention(cards)).toBeNull();
    expect(retention([card({ correct: 3, incorrect: 1 })])).toBe(0.75);
  });

  it('forecasts the coming week', () => {
    const f = forecast(cards, 7, T0);
    expect(f[0]).toBe(3);
    expect(f[5]).toBe(1);
    expect(f).toHaveLength(7);
  });
});
