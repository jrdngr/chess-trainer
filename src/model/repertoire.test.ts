import { describe, expect, it } from 'vitest';
import { positionKey, walkSan } from '../chess/core';
import {
  hasLine,
  addLine,
  addMove,
  childrenOf,
  countNodes,
  createRepertoire,
  decisionPoints,
  fenAt,
  leafLines,
  lineText,
  moveSibling,
  nodeAtLine,
  pathTo,
  removeSubtree,
  setNote,
  setPreferred,
  subtreeIds,
} from './repertoire';

const najdorf = ['e4', 'c5', 'Nf3', 'd6', 'd4', 'cxd4', 'Nxd4', 'Nf6', 'Nc3', 'a6'];

describe('repertoire tree', () => {
  it('adds a line and reuses shared prefixes', () => {
    let rep = createRepertoire('Black vs e4', 'b');
    rep = addLine(rep, najdorf, 'seed').rep;
    expect(countNodes(rep)).toBe(10);

    // A second line sharing the first 6 plies should only add the new moves.
    const dragon = ['e4', 'c5', 'Nf3', 'd6', 'd4', 'cxd4', 'Nxd4', 'Nf6', 'Nc3', 'g6'];
    const res = addLine(rep, dragon, 'manual');
    expect(res.added).toBe(1);
    expect(countNodes(res.rep)).toBe(11);
  });

  it('rejects an illegal move', () => {
    const rep = createRepertoire('X', 'w');
    expect(addMove(rep, null, 'e5')).toBeNull();
  });

  it('is idempotent when the same move is added twice', () => {
    let rep = createRepertoire('X', 'w');
    const first = addMove(rep, null, 'e4')!;
    rep = first.rep;
    const second = addMove(rep, null, 'e4')!;
    expect(second.created).toBe(false);
    expect(second.node.id).toBe(first.node.id);
    expect(countNodes(second.rep)).toBe(1);
  });

  it('tracks the path and line text back to the root', () => {
    let rep = createRepertoire('Black vs e4', 'b');
    const { rep: next, tipId } = addLine(rep, najdorf, 'seed');
    rep = next;
    expect(pathTo(rep, tipId).map((n) => n.san)).toEqual(najdorf);
    expect(lineText(rep, tipId)).toBe('1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6');
  });

  it('keeps FENs consistent with a plain walk of the line', () => {
    const { rep, tipId } = addLine(createRepertoire('X', 'b'), najdorf, 'seed');
    expect(fenAt(rep, tipId)).toBe(walkSan(najdorf).fens.at(-1));
  });

  it('removes a subtree and promotes a new preferred sibling', () => {
    let rep = createRepertoire('White', 'w');
    rep = addLine(rep, ['e4', 'e5', 'Nf3'], 'seed').rep;
    rep = addLine(rep, ['e4', 'c5', 'Nf3'], 'seed').rep;
    const e4 = childrenOf(rep, null)[0];
    const e5 = childrenOf(rep, e4.id).find((m) => m.san === 'e5')!;
    expect(e5.preferred).toBe(true);
    expect(subtreeIds(rep, e5.id)).toHaveLength(2);

    rep = removeSubtree(rep, e5.id);
    const remaining = childrenOf(rep, e4.id);
    expect(remaining.map((m) => m.san)).toEqual(['c5']);
    expect(remaining[0].preferred).toBe(true);
    expect(countNodes(rep)).toBe(3);
  });

  it('moves the preferred flag between siblings', () => {
    let rep = createRepertoire('Black', 'b');
    rep = addLine(rep, ['e4', 'c5'], 'seed').rep;
    rep = addLine(rep, ['e4', 'e5'], 'seed').rep;
    const e4 = childrenOf(rep, null)[0];
    const e5 = childrenOf(rep, e4.id).find((m) => m.san === 'e5')!;
    rep = setPreferred(rep, e5.id);
    const kids = childrenOf(rep, e4.id);
    expect(kids.find((k) => k.san === 'e5')!.preferred).toBe(true);
    expect(kids.find((k) => k.san === 'c5')!.preferred).toBe(false);
  });

  it('reorders siblings', () => {
    let rep = createRepertoire('Black', 'b');
    rep = addLine(rep, ['e4', 'c5'], 'seed').rep;
    rep = addLine(rep, ['e4', 'e5'], 'seed').rep;
    const e4 = childrenOf(rep, null)[0];
    const e5 = childrenOf(rep, e4.id).find((m) => m.san === 'e5')!;
    rep = moveSibling(rep, e5.id, -1);
    expect(childrenOf(rep, e4.id).map((m) => m.san)).toEqual(['e5', 'c5']);
  });

  it('stores and clears notes', () => {
    let rep = createRepertoire('Black', 'b');
    const added = addMove(rep, null, 'e4')!;
    rep = added.rep;
    const node = added.node;
    rep = setNote(rep, node.id, '  main try  ');
    expect(rep.nodes[node.id].note).toBe('main try');
    rep = setNote(rep, node.id, '   ');
    expect(rep.nodes[node.id].note).toBeUndefined();
  });

  it('lists leaf lines longest first', () => {
    let rep = createRepertoire('White', 'w');
    rep = addLine(rep, ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5'], 'seed').rep;
    rep = addLine(rep, ['e4', 'c5'], 'seed').rep;
    const leaves = leafLines(rep);
    expect(leaves[0].sans).toHaveLength(5);
    expect(leaves[1].sans).toHaveLength(2);
  });
});

describe('decision points', () => {
  it('only asks about positions where it is the user turn', () => {
    const { rep } = addLine(createRepertoire('Black vs e4', 'b'), najdorf, 'seed');
    const dps = decisionPoints(rep);
    // Black answers after 1.e4, 2.Nf3, 3.d4, 4.Nxd4, 5.Nc3 => 5 decisions.
    expect(dps).toHaveLength(5);
    expect(dps[0].options.map((o) => o.san)).toEqual(['c5']);
    expect(dps.at(-1)!.options.map((o) => o.san)).toEqual(['a6']);
    for (const dp of dps) expect(dp.fen.split(' ')[1]).toBe('b');
  });

  it('offers every repertoire move from a position, preferred first', () => {
    let rep = createRepertoire('Black vs e4', 'b');
    rep = addLine(rep, ['e4', 'c5'], 'seed').rep;
    rep = addLine(rep, ['e4', 'e5'], 'seed').rep;
    const e4Dp = decisionPoints(rep).find((d) => d.depth === 1)!;
    expect(e4Dp.options.map((o) => o.san)).toEqual(['c5', 'e5']);
  });

  it('collapses transpositions onto one decision point', () => {
    let rep = createRepertoire('White', 'w');
    // Both orders reach the same position with White to move.
    rep = addLine(rep, ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5'], 'seed').rep;
    rep = addLine(rep, ['Nf3', 'Nc6', 'e4', 'e5', 'Bc4'], 'seed').rep;
    const target = positionKey(walkSan(['e4', 'e5', 'Nf3', 'Nc6']).fens.at(-1)!);
    const matches = decisionPoints(rep).filter((d) => d.key === target);
    expect(matches).toHaveLength(1);
    // Both routes' moves are offered from the merged decision point.
    expect(matches[0].options.map((o) => o.san).sort()).toEqual(['Bb5', 'Bc4']);
  });

  it('counts a white repertoire from move one', () => {
    const { rep } = addLine(createRepertoire('White', 'w'), ['e4', 'c5', 'Nf3', 'd6', 'd4'], 'seed');
    const dps = decisionPoints(rep);
    expect(dps).toHaveLength(3);
    expect(dps[0].depth).toBe(0);
    expect(dps[0].options.map((o) => o.san)).toEqual(['e4']);
  });
});

describe('checking for a line without adding it', () => {
  const base = addLine(createRepertoire('White', 'w', 'r'), ['e4', 'c5', 'Nf3', 'd6'], 'seed').rep;

  it('finds a line that is fully there', () => {
    expect(hasLine(base, ['e4', 'c5', 'Nf3', 'd6'])).toBe(true);
  });

  it('finds a prefix of one', () => {
    expect(hasLine(base, ['e4', 'c5'])).toBe(true);
  });

  it('rejects a line that runs past what is there', () => {
    expect(hasLine(base, ['e4', 'c5', 'Nf3', 'd6', 'd4'])).toBe(false);
  });

  it('rejects a line that diverges', () => {
    expect(hasLine(base, ['e4', 'e5'])).toBe(false);
    expect(hasLine(base, ['d4'])).toBe(false);
  });

  it('says no to an empty line, which is nothing to save', () => {
    expect(hasLine(base, [])).toBe(false);
  });

  it('does not change the repertoire it inspects', () => {
    const before = JSON.stringify(base);
    hasLine(base, ['e4', 'c5', 'Nf3', 'd6', 'd4']);
    expect(JSON.stringify(base)).toBe(before);
  });
});

describe('finding the node a line ends on', () => {
  const base = addLine(createRepertoire('White', 'w', 'r'), ['e4', 'c5', 'Nf3', 'd6'], 'seed').rep;

  it('finds it, and taking it away leaves the moves before it', () => {
    const node = nodeAtLine(base, ['e4', 'c5', 'Nf3'])!;
    expect(node.san).toBe('Nf3');
    const cut = removeSubtree(base, node.id);
    expect(hasLine(cut, ['e4', 'c5'])).toBe(true);
    expect(hasLine(cut, ['e4', 'c5', 'Nf3'])).toBe(false);
  });

  it('is null for a line the repertoire does not have', () => {
    expect(nodeAtLine(base, ['e4', 'e5'])).toBeNull();
  });
});
