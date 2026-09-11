import { describe, expect, it } from 'vitest';
import { fenTurn } from '../chess/core';
import { decisionPoints } from '../model/repertoire';
import { allItems, buildSession, checkAnswer } from '../model/session';
import { createCard, review } from '../model/srs';
import { SEED_REPERTOIRES } from '../model/seed/repertoires';
import { buildSeedRepertoires } from './seed';

describe('seeded repertoires', () => {
  const reps = buildSeedRepertoires();

  it('builds the three repertoires the user actually plays', () => {
    expect(reps.map((r) => r.name)).toEqual([
      "White — Queen's Gambit",
      "Black — King's Indian",
      'Black — Sicilian Dragon',
    ]);
    expect(reps.map((r) => r.color)).toEqual(['w', 'b', 'b']);
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

  it('attaches every seeded note to a real node', () => {
    const expected = SEED_REPERTOIRES.reduce((n, r) => n + Object.keys(r.notes ?? {}).length, 0);
    const noted = reps.flatMap((r) => Object.values(r.nodes)).filter((n) => n.note);
    expect(expected).toBeGreaterThan(10);
    expect(noted).toHaveLength(expected);
  });

  it('produces hundreds of trainable positions', () => {
    expect(allItems(reps).length).toBeGreaterThan(800);
  });

  it('opens 1.d4 and answers 1...d5 with 2.c4', () => {
    const white = reps[0];
    const points = decisionPoints(white);
    expect(points[0].depth).toBe(0);
    expect(points[0].options.map((o) => o.san)).toEqual(['d4']);
    const afterD5 = points.find((p) => p.pathSans.join(' ') === 'd4 d5')!;
    expect(afterD5.options.map((o) => o.san)).toEqual(['c4']);
  });

  it('answers 1.e4 with the Sicilian Dragon', () => {
    const dragon = reps[2];
    const points = decisionPoints(dragon);
    expect(points.find((p) => p.pathSans.join(' ') === 'e4')!.options.map((o) => o.san)).toEqual(['c5']);
    expect(
      points.find((p) => p.pathSans.join(' ') === 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3')!
        .options.map((o) => o.san),
    ).toEqual(['g6']);
    // The Yugoslav tabiya, where the whole variation is decided.
    const yugoslav = points.find(
      (p) =>
        p.pathSans.join(' ') ===
        'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6 Be3 Bg7 f3 O-O Qd2 Nc6 Bc4 Bd7 O-O-O',
    )!;
    expect(yugoslav.options.map((o) => o.san)).toEqual(['Rc8']);
  });

  it('answers 1.d4 with the King\u2019s Indian', () => {
    const black = reps[1];
    const points = decisionPoints(black);
    const afterD4 = points.find((p) => p.pathSans.join(' ') === 'd4')!;
    expect(afterD4.options.map((o) => o.san)).toEqual(['Nf6']);
    const afterC4 = points.find((p) => p.pathSans.join(' ') === 'd4 Nf6 c4')!;
    expect(afterC4.options.map((o) => o.san)).toEqual(['g6']);
    const tabiya = points.find(
      (p) => p.pathSans.join(' ') === 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nc6 d5',
    )!;
    expect(tabiya.options.map((o) => o.san)).toEqual(['Ne7']);
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
