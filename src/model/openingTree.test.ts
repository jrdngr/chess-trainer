import { describe, expect, it } from 'vitest';
import { positionKey, walkSan } from '../chess/core';
import {
  ancestorsOf,
  approachKeys,
  deepestNodeAlong,
  deepestNodeWithin,
  descendantsOf,
  insideRegion,
  lineStatus,
  moveLabel,
  nodeById,
  openingTree,
  orderedChildren,
  starredWithin,
} from './openingTree';
import { referenceIndex } from './referenceIndex';

const tree = openingTree(referenceIndex());
const keyAfter = (sans: string[]) => {
  const { fens } = walkSan(sans);
  return positionKey(fens[fens.length - 1]);
};
const byName = (name: string) => {
  const found = [...tree.byId.values()].find((node) => node.name === name);
  if (!found) throw new Error(`no node named ${name}`);
  return found;
};

describe('the shape of the tree', () => {
  it('starts with the first moves, most played first', () => {
    const firsts = tree.root.children.map((node) => node.id);
    expect(firsts.slice(0, 4)).toEqual(['e4', 'd4', 'Nf3', 'c4']);
    expect(tree.root.children.every((node) => node.depth === 1)).toBe(true);
  });

  it('names a first move after the book where it can, and after the move where it cannot', () => {
    expect(nodeById(tree, 'e4').name).toBe("King's Pawn Opening");
    expect(nodeById(tree, 'g3').name).toBe('1.g3');
    expect(moveLabel(['e4', 'c5'])).toBe('1...c5');
  });

  it('files a family under its first move and a variation under its family', () => {
    const sicilian = byName('Sicilian Defence');
    expect(sicilian.parentId).toBe('e4');
    expect(sicilian.depth).toBe(2);
    const najdorf = byName('Sicilian: Najdorf');
    expect(ancestorsOf(tree, najdorf.id).map((node) => node.name)).toEqual([
      "King's Pawn Opening",
      'Sicilian Defence',
      'Sicilian: Open, ...d6',
      'Sicilian: Najdorf',
    ]);
  });

  it('nests as deep as the names go', () => {
    const poisoned = byName('Najdorf: Poisoned Pawn');
    expect(nodeById(tree, poisoned.parentId!).name).toBe('Najdorf: Main Line, 6.Bg5');
    expect(poisoned.depth).toBe(6);
  });

  it('uses the family name where the move order never passes through the family', () => {
    // The Fianchetto never reaches the position the book calls the King's
    // Indian Defence, so its moves say nothing; its name does.
    const fianchetto = byName('KID: Fianchetto Variation');
    expect(nodeById(tree, fianchetto.parentId!).name).toBe("King's Indian Defence");
  });

  it('has every catalogue entry exactly once', () => {
    const index = referenceIndex();
    for (const entry of index.catalogue) expect(tree.byId.get(entry.id)?.name).toBe(entry.name);
    const all = descendantsOf(tree.root);
    expect(new Set(all.map((node) => node.id)).size).toBe(all.length);
    expect(all.length).toBe(tree.byId.size - 1);
  });

  it('answers the root for an id it has never heard of', () => {
    expect(nodeById(tree, 'nope').depth).toBe(0);
    expect(nodeById(tree, '').name).toBe('Any opening');
  });
});

describe('ordering', () => {
  it('lifts starred openings above more popular ones', () => {
    const e4 = nodeById(tree, 'e4');
    const plain = orderedChildren(e4, []).map((node) => node.name);
    expect(plain[0]).toBe('Sicilian Defence');
    const starred = orderedChildren(e4, ['e4 e6']).map((node) => node.name);
    expect(starred[0]).toBe('French Defence');
    expect(starred[1]).toBe('Sicilian Defence');
  });

  it('counts a star on an ancestor as a star on the variation', () => {
    const najdorf = byName('Sicilian: Najdorf');
    expect(starredWithin(tree, najdorf.id, ['e4 c5'])).toBe(true);
    expect(starredWithin(tree, najdorf.id, ['e4 e5'])).toBe(false);
  });
});

describe('regions', () => {
  const najdorf = byName('Sicilian: Najdorf');
  const kid = byName("King's Indian Defence");

  it('is reached once the line passes through the node', () => {
    expect(lineStatus(tree, najdorf, najdorf.sans)).toBe('reached');
    expect(lineStatus(tree, najdorf, [...najdorf.sans, 'Be3', 'e5'])).toBe('reached');
  });

  it('is on the way while the line follows the move order', () => {
    expect(lineStatus(tree, najdorf, [])).toBe('onWay');
    expect(lineStatus(tree, najdorf, ['e4', 'c5', 'Nf3'])).toBe('onWay');
  });

  it('is outside as soon as the line leaves the move order', () => {
    expect(lineStatus(tree, najdorf, ['e4', 'e5'])).toBe('outside');
    expect(lineStatus(tree, najdorf, ['e4', 'c5', 'Nf3', 'Nc6'])).toBe('outside');
    expect(insideRegion(tree, najdorf, ['d4'])).toBe(false);
  });

  it('lets a transposition in', () => {
    // ...Nf6 and ...d6 the other way round reach the same position.
    expect(lineStatus(tree, byName('Sicilian: Open, ...d6'), ['e4', 'c5', 'Nf3', 'd6', 'd4', 'cxd4', 'Nxd4', 'Nf6', 'Nc3'])).toBe('reached');
    expect(lineStatus(tree, kid, ['d4', 'Nf6', 'c4', 'g6', 'Nc3', 'Bg7', 'e4'])).toBe('reached');
    // On the way is decided by the book, not by the node's own move order.
    const approach = approachKeys(tree, kid);
    expect(approach.has(keyAfter(['d4', 'Nf6', 'c4', 'g6', 'Nc3']))).toBe(true);
    expect(approach.has(keyAfter(['d4', 'd5']))).toBe(false);
  });

  it('treats the root as everywhere', () => {
    expect(lineStatus(tree, tree.root, ['a3', 'h6'])).toBe('reached');
  });

  it('is a family and every variation under it, not one position', () => {
    // The Fianchetto sits under the King's Indian and never passes the
    // position the family is named by. It is a King's Indian all the same.
    const fianchetto = ['d4', 'Nf6', 'c4', 'g6', 'Nf3', 'Bg7', 'g3'];
    expect(ancestorsOf(tree, fianchetto.join(' ')).map((n) => n.name)).toContain("King's Indian Defence");
    expect(lineStatus(tree, kid, fianchetto)).toBe('reached');
    expect(lineStatus(tree, kid, fianchetto.slice(0, 5))).toBe('onWay');
    // 4.Nf3 O-O 5.e4 d6 is the Classical by another road; it skips the
    // family's own position on the way to the variation's.
    const castled = ['d4', 'Nf6', 'c4', 'g6', 'Nc3', 'Bg7', 'Nf3', 'O-O', 'e4', 'd6'];
    expect(lineStatus(tree, kid, castled)).toBe('onWay');
    expect(lineStatus(tree, kid, [...castled, 'Be2', 'e5'])).toBe('onWay');
    // Gligorić by that road: a variation's position, the family's never passed.
    expect(lineStatus(tree, kid, [...castled, 'Be2', 'e5', 'Be3'])).toBe('reached');
    expect(insideRegion(tree, kid, castled.slice(0, 7))).toBe(true);
    // What cannot get to any of them is still outside.
    expect(lineStatus(tree, kid, ['d4', 'd5'])).toBe('outside');
    expect(lineStatus(tree, kid, ['d4', 'Nf6', 'c4', 'e6'])).toBe('outside');
  });
});

describe('naming a line', () => {
  it('finds the deepest opening a line goes through', () => {
    const line = ['e4', 'c5', 'Nf3', 'd6', 'd4', 'cxd4', 'Nxd4', 'Nf6', 'Nc3', 'a6', 'Bg5', 'e6', 'f4', 'Qb6', 'Qd2'];
    expect(deepestNodeAlong(tree, line)?.name).toBe('Najdorf: Poisoned Pawn');
    expect(deepestNodeAlong(tree, ['e4'])?.name).toBe("King's Pawn Opening");
    expect(deepestNodeAlong(tree, ['a3'])).toBeNull();
  });

  it('narrows a wide selection to the variation the line is in, and no further out', () => {
    const sicilian = byName('Sicilian Defence');
    const najdorfLine = byName('Sicilian: Najdorf').sans;
    expect(deepestNodeWithin(tree, sicilian, najdorfLine).name).toBe('Sicilian: Najdorf');
    // Outside the selection the selection itself stands.
    expect(deepestNodeWithin(tree, sicilian, ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5']).name).toBe('Sicilian Defence');
    // The root has no outside.
    expect(deepestNodeWithin(tree, tree.root, ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5']).name).toBe('Ruy López');
  });
});
