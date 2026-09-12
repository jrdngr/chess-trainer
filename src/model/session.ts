import { fenTurn } from '../chess/core';
import { childrenOf, decisionPoints, subtreeIds, type DecisionPoint } from './repertoire';
import { isDue } from './srs';
import type { Card, Repertoire } from './types';

export interface ExpectedMove {
  nodeId: string;
  san: string;
  preferred: boolean;
  note?: string;
}

/** Everything the Train screen needs to ask one question. */
export interface TrainingItem {
  cardId: string;
  repertoireId: string;
  repertoireName: string;
  key: string;
  fen: string;
  orientation: 'white' | 'black';
  expected: ExpectedMove[];
  /** SAN path from the start position to this decision point. */
  pathSans: string[];
  /** Preferred continuation after the answer, for "show the line". */
  continuation: string[];
  depth: number;
}

export function cardId(repertoireId: string, key: string): string {
  return `${repertoireId}#${key}`;
}

/** Follow preferred children from a node for up to `plies` moves. */
function preferredContinuation(rep: Repertoire, nodeId: string, plies: number): string[] {
  const out: string[] = [];
  let cur: string | null = nodeId;
  for (let i = 0; i < plies && cur; i += 1) {
    const kids = childrenOf(rep, cur);
    if (!kids.length) break;
    const next = kids.find((k) => k.preferred) ?? kids[0];
    out.push(next.san);
    cur = next.id;
  }
  return out;
}

export function buildItem(rep: Repertoire, dp: DecisionPoint): TrainingItem {
  const preferred = dp.options.find((o) => o.preferred) ?? dp.options[0];
  return {
    cardId: cardId(rep.id, dp.key),
    repertoireId: rep.id,
    repertoireName: rep.name,
    key: dp.key,
    fen: dp.fen,
    orientation: rep.color === 'w' ? 'white' : 'black',
    expected: dp.options.map((o) => ({
      nodeId: o.id,
      san: o.san,
      preferred: o.preferred,
      note: o.note,
    })),
    pathSans: dp.pathSans,
    continuation: preferred ? [preferred.san, ...preferredContinuation(rep, preferred.id, 5)] : [],
    depth: dp.depth,
  };
}

/** Every trainable item across the given repertoires. */
export function allItems(reps: Repertoire[]): TrainingItem[] {
  const out: TrainingItem[] = [];
  for (const rep of reps) {
    for (const dp of decisionPoints(rep)) out.push(buildItem(rep, dp));
  }
  return out;
}

/** Items restricted to the subtree under `nodeId` (inclusive of its position). */
export function branchItems(rep: Repertoire, nodeId: string): TrainingItem[] {
  const ids = new Set(subtreeIds(rep, nodeId));
  const node = rep.nodes[nodeId];
  const items: TrainingItem[] = [];
  for (const dp of decisionPoints(rep)) {
    const inBranch = dp.options.some((o) => ids.has(o.id));
    const isTheNodeItself = node && fenTurn(node.fenAfter) === rep.color && dp.fen === node.fenAfter;
    if (inBranch || isTheNodeItself) items.push(buildItem(rep, dp));
  }
  return items;
}

export type SessionMode = 'due' | 'branch' | 'repertoire' | 'cram' | 'new';

export interface SessionOptions {
  mode: SessionMode;
  now: number;
  maxItems: number;
  maxNew: number;
  /** Deterministic shuffle seed. */
  seed?: number;
}

/** Small deterministic PRNG so sessions are reproducible in tests. */
export function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function shuffle<T>(arr: T[], rand: () => number): T[] {
  const out = [...arr];
  for (let i = out.length - 1; i > 0; i -= 1) {
    const j = Math.floor(rand() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

/**
 * Order a set of candidate items into a session queue.
 *
 * Due reviews come first (most overdue first), then learning cards, then a
 * capped number of new positions ordered shallow-to-deep so the user meets a
 * line's early branches before its depths.
 */
export function buildSession(
  items: TrainingItem[],
  cards: Record<string, Card>,
  opts: SessionOptions,
): TrainingItem[] {
  const { mode, now, maxItems, maxNew } = opts;
  const rand = mulberry32(opts.seed ?? 1);

  const withCard = items.map((item) => ({ item, card: cards[item.cardId] }));

  if (mode === 'cram' || mode === 'branch' || mode === 'repertoire') {
    // Everything in scope, shallow first, regardless of due date.
    const ordered = [...withCard].sort((a, b) => a.item.depth - b.item.depth);
    return ordered.slice(0, maxItems).map((x) => x.item);
  }

  if (mode === 'new') {
    const fresh = withCard.filter((x) => !x.card || x.card.stage === 'new');
    return fresh
      .sort((a, b) => a.item.depth - b.item.depth)
      .slice(0, Math.min(maxItems, maxNew))
      .map((x) => x.item);
  }

  const dueReviews = withCard
    .filter((x) => x.card && x.card.stage === 'review' && isDue(x.card, now))
    .sort((a, b) => a.card!.due - b.card!.due);

  const dueLearning = withCard
    .filter((x) => x.card && x.card.stage === 'learning' && isDue(x.card, now))
    .sort((a, b) => a.card!.due - b.card!.due);

  const fresh = withCard
    .filter((x) => !x.card || x.card.stage === 'new')
    .sort((a, b) => a.item.depth - b.item.depth)
    .slice(0, maxNew);

  // Reviews and learning cards interleave (shuffled together so the user does
  // not get a predictable run of one kind); new material is woven in after.
  const head = shuffle([...dueReviews, ...dueLearning], rand).map((x) => x.item);
  const tail = fresh.map((x) => x.item);
  return interleave(head, tail).slice(0, maxItems);
}

/**
 * What to practise once nothing is due.
 *
 * A session that never ends has to have something to serve after the schedule
 * is clear. Least recently practised first is the honest order: it is the
 * material you have looked at least lately, and answering it early cannot push
 * the schedule out — `review()` holds an early card's date where it is.
 */
export function extraPractice(
  items: TrainingItem[],
  cards: Record<string, Card>,
  count: number,
  rand: () => number,
  skip: (cardId: string) => boolean = () => false,
): TrainingItem[] {
  const pool = items
    .filter((item) => !skip(item.cardId))
    .map((item) => ({ item, seen: cards[item.cardId]?.lastReviewed ?? 0 }))
    .sort((a, b) => a.seen - b.seen);
  // Take a generous slice of the stalest material, then shuffle it, so a long
  // session does not serve the same run of positions in the same order.
  const slice = pool.slice(0, Math.max(count, Math.min(pool.length, count * 3)));
  return shuffle(slice, rand).slice(0, count).map((x) => x.item);
}

/** Spread `b` evenly through `a` rather than appending it. */
export function interleave<T>(a: T[], b: T[]): T[] {
  if (!b.length) return a;
  if (!a.length) return b;
  const out: T[] = [];
  const gap = a.length / b.length;
  let bi = 0;
  for (let i = 0; i < a.length; i += 1) {
    out.push(a[i]);
    while (bi < b.length && (bi + 1) * gap <= i + 1) {
      out.push(b[bi]);
      bi += 1;
    }
  }
  while (bi < b.length) {
    out.push(b[bi]);
    bi += 1;
  }
  return out;
}

export interface AnswerCheck {
  correct: boolean;
  /** The expected move that matched, when correct. */
  matched?: ExpectedMove;
  /** The preferred repertoire move, always present when the item has options. */
  preferred?: ExpectedMove;
}

/** Compare a played SAN against the repertoire's expectations for an item. */
export function checkAnswer(item: TrainingItem, playedSan: string): AnswerCheck {
  const preferred = item.expected.find((e) => e.preferred) ?? item.expected[0];
  const matched = item.expected.find((e) => e.san === playedSan);
  return { correct: !!matched, matched, preferred };
}
