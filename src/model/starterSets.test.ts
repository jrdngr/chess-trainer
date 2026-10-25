import { describe, expect, it } from 'vitest';
import { openingTree } from './openingTree';
import { referenceIndex } from './referenceIndex';
import { countOwnMoves, setOpenings, setSeed, STARTER_SETS } from './starterSets';

const tree = openingTree(referenceIndex());

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

  it('puts in only the openings’ own moves', () => {
    const [classical] = STARTER_SETS;
    // Three White moves to 3.Bc4, then 1...e5, then 1...d5 and 2...e6 in the QGD.
    expect(countOwnMoves(setSeed(classical))).toBe(3 + 1 + 2);
  });
});
