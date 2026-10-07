import { describe, expect, it } from 'vitest';
import { nodeById, openingTree } from './openingTree';
import { referenceIndex } from './referenceIndex';
import { addLine, createRepertoire } from './repertoire';
import { itemsInRegion } from './selection';
import { allItems } from './session';

const tree = openingTree(referenceIndex());
const kingsIndian = nodeById(tree, 'd4 Nf6 c4 g6 Nc3');
const sicilian = nodeById(tree, 'e4 c5');

describe('itemsInRegion', () => {
  it('judges a card by its answer, not by the position alone', () => {
    // The book reaches the King's Indian from 1.e4 (1...d6 2.d4 Nf6 3.Nc3 g6
    // 4.Nf3 Bg7 5.c4), but 1...c5 never gets there.
    let rep = createRepertoire('Black', 'b', 'rep_b');
    rep = addLine(rep, ['e4', 'c5']).rep;
    rep = addLine(rep, ['d4', 'Nf6', 'c4', 'g6', 'Nc3', 'Bg7']).rep;
    const items = allItems([rep]);
    const lines = (node: typeof kingsIndian) => itemsInRegion(tree, node, items).map((i) => i.pathSans.join(' '));
    expect(lines(kingsIndian)).not.toContain('e4');
    expect(lines(kingsIndian)).toEqual(expect.arrayContaining(['d4', 'd4 Nf6 c4', 'd4 Nf6 c4 g6 Nc3']));
    expect(lines(sicilian)).toEqual(['e4']);
  });

  it('keeps your own first move on the way in', () => {
    let rep = createRepertoire('White', 'w', 'rep_w');
    rep = addLine(rep, ['d4', 'Nf6', 'c4', 'g6', 'Nc3']).rep;
    const lines = itemsInRegion(tree, kingsIndian, allItems([rep])).map((i) => i.pathSans.join(' '));
    expect(lines).toEqual(expect.arrayContaining(['', 'd4 Nf6']));
  });
});
