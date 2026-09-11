import { describe, expect, it } from 'vitest';
import { fenTurn } from '../chess/core';
import { decisionPoints } from '../model/repertoire';
import { allItems, buildSession, checkAnswer } from '../model/session';
import { createCard, review } from '../model/srs';
import { buildSeedRepertoires } from './seed';

describe('seeded repertoires', () => {
  const reps = buildSeedRepertoires();

  it('builds all three repertoires', () => {
    expect(reps.map((r) => r.name)).toEqual([
      'White — 1.e4',
      'Black vs 1.e4 — Najdorf',
      'Black vs 1.d4 — Nimzo / QID',
    ]);
  });

  it('gives every repertoire a substantial tree', () => {
    for (const rep of reps) {
      expect(Object.keys(rep.nodes).length).toBeGreaterThan(80);
    }
  });

  it('only asks the user about positions on their own turn', () => {
    for (const rep of reps) {
      for (const dp of decisionPoints(rep)) {
        expect(fenTurn(dp.fen)).toBe(rep.color);
        expect(dp.options.length).toBeGreaterThan(0);
      }
    }
  });

  it('attaches the seeded notes', () => {
    const noted = reps.flatMap((r) => Object.values(r.nodes)).filter((n) => n.note);
    expect(noted.length).toBeGreaterThanOrEqual(10);
  });

  it('produces hundreds of trainable positions', () => {
    expect(allItems(reps).length).toBeGreaterThan(300);
  });

  it('starts the White repertoire at move one', () => {
    const white = reps[0];
    const first = decisionPoints(white)[0];
    expect(first.depth).toBe(0);
    expect(first.options.map((o) => o.san)).toEqual(['e4']);
  });
});

describe('a full training round trip', () => {
  it('takes a fresh user from seed data through a graded answer', () => {
    const reps = buildSeedRepertoires();
    const items = allItems(reps);
    const now = 1_700_000_000_000;

    const queue = buildSession(items, {}, { mode: 'due', now, maxItems: 10, maxNew: 5, seed: 1 });
    expect(queue).toHaveLength(5);

    const first = queue[0];
    const card = createCard(first.cardId, first.repertoireId, first.key, first.fen, now);
    expect(card.stage).toBe('new');

    // Right answer, graded "good": the card leaves the new pile.
    const right = checkAnswer(first, first.expected[0].san);
    expect(right.correct).toBe(true);
    const afterGood = review(card, 'good', now).card;
    expect(afterGood.stage).toBe('learning');
    expect(afterGood.due).toBeGreaterThan(now);

    // Wrong answer resets it to the first learning step.
    const wrong = checkAnswer(first, illegalAlternative(first.expected[0].san));
    expect(wrong.correct).toBe(false);
    const afterAgain = review(afterGood, 'again', now).card;
    expect(afterAgain.step).toBe(0);
    expect(afterAgain.incorrect).toBe(1);
  });
});

function illegalAlternative(san: string) {
  return `${san}-not-a-move`;
}
