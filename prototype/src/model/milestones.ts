import { ancestorsOf, type OpeningTree } from './openingTree';
import { ACTIVITY_MODES, dayKey, TIERS, type NodeStats, type ScoreState } from './scoring';
import type { SurvivalRecord } from './survival';

/**
 * Milestones: goals reached once and kept. Every one is read from what the app
 * already records, so whatever was done before they existed counts.
 */

export type MilestoneKind = 'streak' | 'survival' | 'tier' | 'breadth' | 'rounds';

export interface Milestone {
  id: string;
  kind: MilestoneKind;
  /** The badge's name: "7 days", "Mastered", "1k rounds". */
  label: string;
  target: number;
  /** How far along you are, in the target's units. Earned at `value >= target`. */
  value: number;
  /** For a tier milestone, the tier's color. */
  color?: string;
}

/** Days in a row with a round, the longest run of them ever. */
export function longestStreak(stats: NodeStats): number {
  const DAY = 86_400_000;
  const played = Object.entries(stats.days)
    .filter(([, day]) => day.rounds > 0)
    .map(([key]) => key)
    .sort();
  let best = 0;
  let run = 0;
  let previous: string | null = null;
  for (const key of played) {
    // A day's noon, so a daylight-saving shift cannot skip or repeat a day.
    const [y, m, d] = key.split('-').map(Number);
    const yesterday = dayKey(new Date(y, m - 1, d, 12).getTime() - DAY);
    run = previous === yesterday ? run + 1 : 1;
    best = Math.max(best, run);
    previous = key;
  }
  return best;
}

/** The highest an opening's rating has ever stood: its end-of-day ratings and where it is now. */
export function peakRating(stats: NodeStats): number {
  if (stats.rated === 0) return 0;
  let peak = stats.rating;
  for (const day of Object.values(stats.days)) if (day.rating !== null && day.rating > peak) peak = day.rating;
  return peak;
}

/** The second rung of the tree: a family such as the Sicilian, under its first move. */
function familyOf(tree: OpeningTree, id: string): string | null {
  return ancestorsOf(tree, id).find((node) => node.depth === 2)?.id ?? null;
}

const FAMILIAR = TIERS.find((tier) => tier.name === 'Familiar')!.at;

const STREAKS = [3, 7, 30];
const SURVIVALS = [10, 20, 30];
const BREADTHS = [3, 5, 10];
const ROUNDS = [100, 500, 1000, 5000];

function roundsLabel(n: number): string {
  return n >= 1000 ? `${n / 1000}k rounds` : `${n} rounds`;
}

/**
 * Every milestone with how far along it is. Breadth counts families (a
 * Najdorf and the Sicilian above it are one), so one good line cannot earn it
 * three times over.
 */
export function milestones(score: ScoreState, survival: SurvivalRecord, tree: OpeningTree): Milestone[] {
  const streak = longestStreak(score.global);
  const best = survival.global.best;
  const rounds = ACTIVITY_MODES.reduce((sum, mode) => sum + (score.global.byMode[mode]?.rounds ?? 0), 0);

  let peak = 0;
  const familiar = new Set<string>();
  for (const [id, stats] of Object.entries(score.nodes)) {
    if (!tree.byId.has(id)) continue;
    const top = peakRating(stats);
    peak = Math.max(peak, top);
    if (top >= FAMILIAR) {
      const family = familyOf(tree, id);
      if (family) familiar.add(family);
    }
  }

  return [
    ...STREAKS.map((n) => ({ id: `streak-${n}`, kind: 'streak' as const, label: `${n} days`, target: n, value: streak })),
    ...SURVIVALS.map((n) => ({ id: `survival-${n}`, kind: 'survival' as const, label: `${n} moves`, target: n, value: best })),
    ...TIERS.filter((tier) => tier.at >= FAMILIAR).map((tier) => ({
      id: `tier-${tier.name.toLowerCase()}`,
      kind: 'tier' as const,
      label: tier.name,
      target: tier.at,
      value: peak,
      color: tier.color,
    })),
    ...BREADTHS.map((n) => ({ id: `breadth-${n}`, kind: 'breadth' as const, label: `${n} Familiar`, target: n, value: familiar.size })),
    ...ROUNDS.map((n) => ({ id: `rounds-${n}`, kind: 'rounds' as const, label: roundsLabel(n), target: n, value: rounds })),
  ];
}

export function earned(milestone: Milestone): boolean {
  return milestone.value >= milestone.target;
}

/** How close an unearned milestone is, 0..1. */
export function progress(milestone: Milestone): number {
  return Math.max(0, Math.min(1, milestone.value / milestone.target));
}

/** The unearned milestones closest to done, first. Ties keep the list's own order. */
export function nextUp(list: Milestone[], count: number): Milestone[] {
  return list
    .map((milestone, i) => ({ milestone, i }))
    .filter(({ milestone }) => !earned(milestone))
    .sort((a, b) => progress(b.milestone) - progress(a.milestone) || a.i - b.i)
    .slice(0, count)
    .map(({ milestone }) => milestone);
}
