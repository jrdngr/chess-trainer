import { describe, expect, it } from 'vitest';
import { ancestorsOf, openingTree } from './openingTree';
import { referenceIndex } from './referenceIndex';
import { earned, longestStreak, milestones, nextUp, peakRating } from './milestones';
import { EMPTY_SCORE, emptyNodeStats, ratingChange, type NodeStats, type ScoreState } from './scoring';
import { EMPTY_SURVIVAL_RECORD, type SurvivalRecord } from './survival';

const tree = openingTree(referenceIndex());
const NAJDORF = 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6';

function days(keys: string[]): NodeStats {
  const stats = emptyNodeStats();
  for (const key of keys) stats.days[key] = { answered: 1, correct: 1, rounds: 1, rating: null };
  return stats;
}

function rated(rating: number, dayRatings: (number | null)[] = []): NodeStats {
  const stats = { ...emptyNodeStats(), rating, rated: 10 };
  dayRatings.forEach((r, i) => (stats.days[`2026-01-${String(i + 1).padStart(2, '0')}`] = { answered: 1, correct: 1, rounds: 1, rating: r }));
  return stats;
}

const byId = (list: ReturnType<typeof milestones>) => Object.fromEntries(list.map((m) => [m.id, m]));

describe('milestones', () => {
  it('finds the longest streak ever, not the current one', () => {
    expect(longestStreak(days(['2026-03-01', '2026-03-02', '2026-03-03', '2026-03-05', '2026-03-06']))).toBe(3);
    expect(longestStreak(days(['2026-03-31', '2026-04-01']))).toBe(2);
    expect(longestStreak(emptyNodeStats())).toBe(0);
  });

  it('keeps a tier once reached, though the rating fell back', () => {
    expect(peakRating(rated(200, [180, 420, 300]))).toBe(420);
    expect(peakRating(emptyNodeStats())).toBe(0);
  });

  it('counts breadth by family, so a variation and its family are one', () => {
    const najdorf = ancestorsOf(tree, NAJDORF);
    expect(najdorf.length).toBeGreaterThan(2);
    const nodes = Object.fromEntries(najdorf.map((node) => [node.id, rated(300)]));
    const score: ScoreState = { ...EMPTY_SCORE, nodes };
    const list = byId(milestones(score, EMPTY_SURVIVAL_RECORD, tree));
    expect(list['breadth-3'].value).toBe(1);
    expect(earned(list['tier-familiar'])).toBe(true);
    expect(earned(list['tier-solid'])).toBe(false);
  });

  it('reads Survival best and rounds played', () => {
    const survival: SurvivalRecord = { ...EMPTY_SURVIVAL_RECORD, global: { best: 22, recent: [], history: [], runs: 1, ended: 0, bestPoints: 0 } };
    const global = emptyNodeStats();
    global.byMode.survival.rounds = 80;
    global.byMode.drill.rounds = 40;
    const list = byId(milestones({ ...EMPTY_SCORE, global }, survival, tree));
    expect(earned(list['survival-20'])).toBe(true);
    expect(earned(list['survival-30'])).toBe(false);
    expect(earned(list['rounds-100'])).toBe(true);
    expect(list['rounds-1000'].label).toBe('1k rounds');
  });

  it('puts the closest unearned ones next', () => {
    const survival: SurvivalRecord = { ...EMPTY_SURVIVAL_RECORD, global: { best: 18, recent: [], history: [], runs: 1, ended: 0, bestPoints: 0 } };
    const next = nextUp(milestones(EMPTY_SCORE, survival, tree), 2).map((m) => m.id);
    expect(next).toEqual(['survival-20', 'survival-30']);
  });
});

describe('rating change', () => {
  it('reads the rating a week ago from the last day that moved it', () => {
    const now = new Date(2026, 0, 20, 12).getTime();
    const stats = rated(300, []);
    stats.days['2026-01-05'] = { answered: 1, correct: 1, rounds: 1, rating: 200 };
    stats.days['2026-01-12'] = { answered: 1, correct: 1, rounds: 1, rating: 250 };
    stats.days['2026-01-18'] = { answered: 1, correct: 1, rounds: 1, rating: 300 };
    // A week before the 20th is the 13th; the 12th is the last day at or before it.
    expect(ratingChange(stats, 7, now)).toBe(300 - 250);
    expect(ratingChange(rated(80, []), 7, now)).toBe(80);
  });
});
