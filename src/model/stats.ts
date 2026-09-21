import { ancestorsOf, nodeById, type OpeningNode, type OpeningTree } from './openingTree';
import { dayKey, nodeStats, RATING, type NodeStats, type ScoreState } from './scoring';

/**
 * Stats: the numbers behind one opening, or the whole game, shaped for a
 * chart. Everything here reads the per-day tallies the record keeps and
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

/** The last `days` days, oldest first, each with the rounds played that day. */
export function dailyRounds(stats: NodeStats, days: number, now = Date.now()): DayPoint[] {
  const out: DayPoint[] = [];
  for (let back = days - 1; back >= 0; back -= 1) {
    const at = dayStart(now, back);
    const key = dayKey(at);
    out.push({ at, key, value: stats.days[key]?.rounds ?? 0 });
  }
  return out;
}

/**
 * The rating as it stood at the end of each day in the window.
 *
 * A day the rating never moved holds the day before's, so the line is
 * continuous rather than dropping to nothing whenever the opening was rested.
 * It starts from wherever the rating stood going into the window, and an
 * opening that has never been rated has no line at all.
 */
export function ratingOverTime(stats: NodeStats, days: number, now = Date.now()): DayPoint[] {
  if (stats.rated === 0) return [];
  const first = dayKey(dayStart(now, days - 1));
  let running: number = RATING.start;
  let latest = '';
  for (const [key, day] of Object.entries(stats.days)) {
    if (key >= first || day.rating === null) continue;
    if (key > latest) {
      latest = key;
      running = day.rating;
    }
  }
  const out: DayPoint[] = [];
  for (let back = days - 1; back >= 0; back -= 1) {
    const at = dayStart(now, back);
    const key = dayKey(at);
    const rating = stats.days[key]?.rating;
    if (rating !== null && rating !== undefined) running = rating;
    out.push({ at, key, value: running });
  }
  return out;
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

/** Rounds in the last `days` days. */
export function recentRounds(stats: NodeStats, days: number, now = Date.now()): number {
  let total = 0;
  for (let back = days - 1; back >= 0; back -= 1) total += stats.days[dayKey(dayStart(now, back))]?.rounds ?? 0;
  return total;
}

/* ── favouriteness ──────────────────────────────────────────────────────── */

export interface Sibling {
  node: OpeningNode;
  rounds: number;
  /** Of the rounds among these siblings. */
  share: number;
}

/**
 * How an opening ranks against its siblings by rounds played lately: "your
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
    .map((sibling) => ({ node: sibling, rounds: recentRounds(nodeStats(score, sibling.id), days, now), share: 0 }))
    .filter((sibling) => sibling.rounds > 0)
    .sort((a, b) => b.rounds - a.rounds || a.node.name.localeCompare(b.node.name));
  const total = siblings.reduce((sum, sibling) => sum + sibling.rounds, 0);
  for (const sibling of siblings) sibling.share = total ? sibling.rounds / total : 0;
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

/**
 * Your starred openings, best rated first. Unrated stars are kept and sort
 * last: a star you have not tested yet is still one of yours, and seeing it
 * sitting at Unrated is the nudge to go and run it.
 */
export function starredOpenings(tree: OpeningTree, score: ScoreState, starred: Iterable<string>): Ranked[] {
  const seen = new Set<string>();
  const out: Ranked[] = [];
  for (const id of starred) {
    const node = tree.byId.get(id);
    if (!node || node.depth === 0 || seen.has(id)) continue;
    seen.add(id);
    out.push({
      node,
      stats: nodeStats(score, id),
      trail: ancestorsOf(tree, id).slice(0, -1).map((n) => n.name).join(' \u203a '),
    });
  }
  return out.sort(
    (a, b) =>
      b.stats.rating - a.stats.rating ||
      a.node.depth - b.node.depth ||
      a.node.name.localeCompare(b.node.name),
  );
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
