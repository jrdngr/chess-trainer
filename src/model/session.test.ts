import { describe, expect, it } from 'vitest';
import { addLine, createRepertoire } from './repertoire';
import {
  allItems,
  branchItems,
  buildSession,
  cardId,
  checkAnswer,
  interleave,
  mulberry32,
  shuffle,
} from './session';
import { createCard, DAY } from './srs';
import type { Card } from './types';

const T0 = 1_700_000_000_000;

function blackRepertoire() {
  let rep = createRepertoire('Black vs e4', 'b', 'rep_b');
  rep = addLine(rep, ['e4', 'c5', 'Nf3', 'd6', 'd4', 'cxd4', 'Nxd4', 'Nf6', 'Nc3', 'a6'], 'seed').rep;
  rep = addLine(rep, ['e4', 'c5', 'Nc3', 'Nc6'], 'seed').rep;
  return rep;
}

describe('training items', () => {
  it('builds one item per decision point', () => {
    const rep = blackRepertoire();
    const items = allItems([rep]);
    expect(items.length).toBe(6);
    for (const item of items) {
      expect(item.orientation).toBe('black');
      expect(item.fen.split(' ')[1]).toBe('b');
    }
  });

  it('carries the preferred continuation for the feedback view', () => {
    const rep = blackRepertoire();
    const first = allItems([rep]).find((i) => i.depth === 1)!;
    expect(first.expected.map((e) => e.san)).toEqual(['c5']);
    expect(first.continuation.slice(0, 3)).toEqual(['c5', 'Nf3', 'd6']);
  });

  it('scopes a session to one branch', () => {
    const rep = blackRepertoire();
    const nc3 = Object.values(rep.nodes).find((n) => n.san === 'Nc3' && n.fenBefore.includes('/8/'))!;
    const items = branchItems(rep, nc3.id);
    expect(items.length).toBeGreaterThan(0);
    expect(items.length).toBeLessThan(allItems([rep]).length);
  });
});

describe('answer checking', () => {
  const item = allItems([blackRepertoire()]).find((i) => i.depth === 1)!;

  it('accepts the repertoire move', () => {
    const res = checkAnswer(item, 'c5');
    expect(res.correct).toBe(true);
    expect(res.matched!.san).toBe('c5');
  });

  it('rejects anything else and reports the preferred move', () => {
    const res = checkAnswer(item, 'e5');
    expect(res.correct).toBe(false);
    expect(res.preferred!.san).toBe('c5');
  });

  it('accepts any of several repertoire moves from one position', () => {
    let rep = createRepertoire('Black', 'b', 'r');
    rep = addLine(rep, ['e4', 'c5'], 'seed').rep;
    rep = addLine(rep, ['e4', 'e5'], 'seed').rep;
    const dp = allItems([rep])[0];
    expect(checkAnswer(dp, 'c5').correct).toBe(true);
    expect(checkAnswer(dp, 'e5').correct).toBe(true);
    expect(checkAnswer(dp, 'e6').correct).toBe(false);
    // The first move added stays the preferred answer.
    expect(checkAnswer(dp, 'e6').preferred!.san).toBe('c5');
  });
});

describe('session building', () => {
  const rep = blackRepertoire();
  const items = allItems([rep]);

  function cards(spec: Record<string, Partial<Card>>): Record<string, Card> {
    const out: Record<string, Card> = {};
    for (const [id, over] of Object.entries(spec)) {
      out[id] = { ...createCard(id, 'rep_b', 'k', 'f', T0), ...over };
    }
    return out;
  }

  it('puts due cards before new material', () => {
    const dueId = items[2].cardId;
    const deck = cards({ [dueId]: { stage: 'review', interval: 5, due: T0 - DAY } });
    const queue = buildSession(items, deck, { mode: 'due', now: T0, maxItems: 10, maxNew: 3, seed: 7 });
    expect(queue[0].cardId).toBe(dueId);
  });

  it('caps how many new positions enter a session', () => {
    const queue = buildSession(items, {}, { mode: 'due', now: T0, maxItems: 50, maxNew: 2, seed: 7 });
    expect(queue).toHaveLength(2);
  });

  it('leaves out cards that are not due yet', () => {
    const deck = cards(
      Object.fromEntries(items.map((i) => [i.cardId, { stage: 'review' as const, due: T0 + 5 * DAY }])),
    );
    expect(buildSession(items, deck, { mode: 'due', now: T0, maxItems: 50, maxNew: 5, seed: 1 })).toHaveLength(0);
  });

  it('cram mode ignores due dates and goes shallow first', () => {
    const deck = cards(
      Object.fromEntries(items.map((i) => [i.cardId, { stage: 'review' as const, due: T0 + 50 * DAY }])),
    );
    const queue = buildSession(items, deck, { mode: 'cram', now: T0, maxItems: 50, maxNew: 0, seed: 1 });
    expect(queue).toHaveLength(items.length);
    expect(queue[0].depth).toBeLessThanOrEqual(queue[1].depth);
  });

  it('is deterministic for a fixed seed', () => {
    const opts = { mode: 'due' as const, now: T0, maxItems: 50, maxNew: 5, seed: 42 };
    const a = buildSession(items, {}, opts).map((i) => i.cardId);
    const b = buildSession(items, {}, opts).map((i) => i.cardId);
    expect(a).toEqual(b);
  });

  it('derives stable card ids from repertoire and position', () => {
    expect(cardId('rep_b', 'k')).toBe('rep_b#k');
    expect(allItems([rep])[0].cardId.startsWith('rep_b#')).toBe(true);
  });
});

describe('queue helpers', () => {
  it('spreads new items through the review queue', () => {
    expect(interleave([1, 2, 3, 4], [9, 8])).toEqual([1, 2, 9, 3, 4, 8]);
    expect(interleave([], [1, 2])).toEqual([1, 2]);
    expect(interleave([1, 2], [])).toEqual([1, 2]);
  });

  it('shuffles deterministically', () => {
    const a = shuffle([1, 2, 3, 4, 5], mulberry32(3));
    const b = shuffle([1, 2, 3, 4, 5], mulberry32(3));
    expect(a).toEqual(b);
    expect(a.sort()).toEqual([1, 2, 3, 4, 5]);
  });
});
