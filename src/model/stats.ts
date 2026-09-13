import { ancestorsOf, nodeById, type OpeningNode, type OpeningTree } from './openingTree';
import { dayKey, nodeStats, type NodeStats, type ScoreState } from './scoring';

/**
 * Stats: the numbers behind one opening, or the whole game, shaped for a
 * chart. Everything here reads the per-day tallies the score keeps and
 * folds them into series; nothing is stored twice.
 */

const DAY = 86_400_000;

export interface DayPoint {
  /** Start of the day, local time. */
  at: number;
  key: string;
  value: number;
}

/** Midnight, local time, `back` days before `now`. */
function dayStart(now: number, back: number): number {
  const date = new Date(now - back * DAY);
  date.setHours(0, 0, 0, 0);
  return date.getTime();
}

/** The last `days` days, oldest first, each with what was earned that day. */
export function dailyScore(stats: NodeStats, days: number, now = Date.now()): DayPoint[] {
  const out: DayPoint[] = [];
  for (let back = days - 1; back >= 0; back -= 1) {
    const at = dayStart(now, back);
    const key = dayKey(at);
    out.push({ at, key, value: stats.days[key]?.score ?? 0 });
  }
  return out;
}

/**
 * Score as it climbed, one point per day in the window.
 *
 * The curve starts at whatever had been earned before the window, so a
 * ninety-day view of a year-old record does not start from nothing.
 */
export function cumulativeScore(stats: NodeStats, days: number, now = Date.now()): DayPoint[] {
  const first = dayKey(dayStart(now, days - 1));
  let before = 0;
  for (const [key, day] of Object.entries(stats.days)) if (key < first) before += day.score;
  let running = before;
  return dailyScore(stats, days, now).map((point) => {
    running += point.value;
    return { ...point, value: running };
  });
}

/**
 * Accuracy over the window, smoothed: each day is the share of the answers
 * over the seven days ending there that were right. Days with nothing to
 * average over are left out rather than drawn as zero.
 */
export function rollingAccuracy(stats: NodeStats, days: number, now = Date.now(), window = 7): DayPoint[] {
  const out: DayPoint[] = [];
  for (let back = days - 1; back >= 0; back -= 1) {
    let answered = 0;
    let correct = 0;
    for (let w = 0; w < window; w += 1) {
      const day = stats.days[dayKey(dayStart(now, back + w))];
      if (!day) continue;
      answered += day.answered;
      correct += day.correct;
    }
    if (!answered) continue;
    const at = dayStart(now, back);
    out.push({ at, key: dayKey(at), value: correct / answered });
  }
  return out;
}

/** Games in the last `days` days. */
export function recentGames(stats: NodeStats, days: number, now = Date.now()): number {
  let total = 0;
  for (let back = days - 1; back >= 0; back -= 1) total += stats.days[dayKey(dayStart(now, back))]?.games ?? 0;
  return total;
}

/* ── favouriteness ──────────────────────────────────────────────────────── */

export interface Sibling {
  node: OpeningNode;
  games: number;
  /** Of the games among these siblings. */
  share: number;
}

/**
 * How an opening ranks against its siblings by games played lately: "your
 * second favourite Sicilian". Siblings that have never been played are left
 * out — a rank among a hundred untouched variations says nothing.
 */
export function favouriteness(
  tree: OpeningTree,
  score: ScoreState,
  id: string,
  days = 30,
  now = Date.now(),
): { rank: number; of: number; siblings: Sibling[]; parent: OpeningNode | null } | null {
  const node = tree.byId.get(id);
  if (!node || node.depth === 0) return null;
  const parent = node.parentId === null ? null : nodeById(tree, node.parentId);
  const pool = parent ? parent.children : tree.root.children;
  const siblings = pool
    .map((sibling) => ({ node: sibling, games: recentGames(nodeStats(score, sibling.id), days, now), share: 0 }))
    .filter((sibling) => sibling.games > 0)
    .sort((a, b) => b.games - a.games || a.node.name.localeCompare(b.node.name));
  const total = siblings.reduce((sum, sibling) => sum + sibling.games, 0);
  for (const sibling of siblings) sibling.share = total ? sibling.games / total : 0;
  const rank = siblings.findIndex((sibling) => sibling.node.id === id);
  if (rank < 0) return null;
  return { rank: rank + 1, of: siblings.length, siblings, parent };
}

/* ── the openings that matter ───────────────────────────────────────────── */

export interface Ranked {
  node: OpeningNode;
  stats: NodeStats;
  trail: string;
}

/** Every opening with a score, best first. */
export function topOpenings(tree: OpeningTree, score: ScoreState, limit = 12): Ranked[] {
  return Object.entries(score.nodes)
    .filter(([, stats]) => stats.score > 0)
    .map(([id, stats]) => ({
      node: nodeById(tree, id),
      stats,
      trail: ancestorsOf(tree, id).slice(0, -1).map((n) => n.name).join(' › '),
    }))
    .filter((entry) => entry.node.depth > 0)
    .sort((a, b) => b.stats.score - a.stats.score || a.node.depth - b.node.depth)
    .slice(0, limit);
}

/** Ticks for an axis: a few round numbers that cover the range. */
export function niceTicks(max: number, count = 3): number[] {
  if (max <= 0) return [0];
  const rough = max / count;
  const magnitude = 10 ** Math.floor(Math.log10(rough));
  const step = [1, 2, 5, 10].map((n) => n * magnitude).find((n) => n >= rough) ?? magnitude * 10;
  const out: number[] = [];
  for (let tick = 0; tick <= max + step * 0.999; tick += step) out.push(tick);
  return out;
}
