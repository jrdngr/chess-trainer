import { describe, expect, it } from 'vitest';
import { fenTurn, walkSan } from '../chess/core';
import { openingTree } from './openingTree';
import { lookup, totalGamesAt } from './reference';
import { referenceIndex } from './referenceIndex';
import { seedLines, setOpenings, setSeed, STARTER_SETS, SEED_SHARE } from './starterSets';

const index = referenceIndex();
const tree = openingTree(index);

/** The share of the book's games that play a move at the position a move order reaches. */
function share(sans: string[], san: string): number {
  const { fens } = walkSan(sans);
  const entry = lookup(index, fens[fens.length - 1]);
  const total = totalGamesAt(entry);
  const move = entry?.moves.find((m) => m.san === san);
  return move && total ? move.games / total : 0;
}

describe('starter sets', () => {
  it('has one opening or more in every slot', () => {
    for (const set of STARTER_SETS) {
      expect(set.slots.w.length, set.id).toBeGreaterThan(0);
      expect(set.slots.e4.length, set.id).toBeGreaterThan(0);
      expect(set.slots.d4.length, set.id).toBeGreaterThan(0);
    }
  });

  it('names only openings the book names, from the slot’s first move', () => {
    for (const set of STARTER_SETS) {
      for (const opening of setOpenings(set)) {
        const node = tree.byId.get(opening.id);
        expect(node, `${set.id}: ${opening.id}`).toBeDefined();
        if (opening.slot !== 'w') expect(opening.id.split(' ')[0]).toBe(opening.slot);
      }
    }
  });

  it('only plays moves the book plays', () => {
    for (const set of STARTER_SETS) {
      for (const [order, san] of set.plays ?? []) {
        expect(share(order.split(' '), san), `${set.id}: ${order} ${san}`).toBeGreaterThan(0.05);
      }
    }
  });

  it('seeds every opening past its name with book moves, one answer a position', () => {
    for (const set of STARTER_SETS) {
      const lines = seedLines(index, setSeed(set), set.plays);
      const answers = new Map<string, string>();
      for (const line of lines) {
        const { fens } = walkSan(line.sans);
        line.sans.forEach((san, i) => {
          if (fenTurn(fens[i]) !== line.color) {
            // Every reply was asked for by the book, past the opening's own moves.
            return;
          }
          const key = `${line.color}:${fens[i].split(' ').slice(0, 4).join(' ')}`;
          expect(answers.get(key) ?? san, `${set.id}: ${line.sans.slice(0, i + 1).join(' ')}`).toBe(san);
          answers.set(key, san);
        });
      }
      for (const opening of setOpenings(set)) {
        const longest = Math.max(
          ...lines.filter((line) => line.sans.join(' ').startsWith(opening.id)).map((line) => line.sans.length),
        );
        expect(longest, `${set.id}: ${opening.id}`).toBeGreaterThan(opening.id.split(' ').length);
      }
    }
  });

  it('answers the common replies', () => {
    const [classical] = STARTER_SETS;
    const lines = seedLines(index, setSeed(classical), classical.plays);
    // After 1.e4 e5 2.Nf3 Nc6 3.Bc4, both 3...Bc5 and 3...Nf6 are common enough to answer.
    for (const reply of ['Bc5', 'Nf6']) {
      expect(share('e4 e5 Nf3 Nc6 Bc4'.split(' '), reply)).toBeGreaterThanOrEqual(SEED_SHARE);
      expect(lines.some((line) => line.sans.join(' ').startsWith(`e4 e5 Nf3 Nc6 Bc4 ${reply} `))).toBe(true);
    }
  });
});
