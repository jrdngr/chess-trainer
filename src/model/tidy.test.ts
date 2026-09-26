import { describe, expect, it } from 'vitest';
import { walkSan } from '../chess/core';
import { nodeById, openingTree } from './openingTree';
import { referenceIndex } from './referenceIndex';
import { addLine, childrenOf, createRepertoire, nodeAtLine } from './repertoire';
import { findAt, offPrepHint, switchMove, tidyFinds, type TidyOptions } from './tidy';
import type { Repertoire } from './types';

const index = referenceIndex();
const tree = openingTree(index);
const opts: TidyOptions = { prefs: { priority: 'transposition', pawns: false }, minShare: 5 };

function rep(color: 'w' | 'b', lines: string[]): Repertoire {
  let out = createRepertoire('Test', color, `r_${color}`);
  for (const line of lines) out = addLine(out, line.split(' '), 'reference').rep;
  return out;
}

/** An exchange Queen's Gambit met with 6.Bg5, beside Catalan and Slav lines with g3. */
const qgd = rep('w', [
  'd4 d5 c4 e6 cxd5 exd5 Nc3 Nf6 Nf3 c6 Bg5 Be7 e3',
  'd4 Nf6 c4 e6 Nf3 d5 g3 Be7 Bg2 O-O O-O',
  'd4 Nf6 c4 e6 Nf3 d5 g3 dxc4 Bg2',
  'd4 d5 c4 c6 Nf3 Nf6 g3',
]);
const exchange = 'd4 d5 c4 e6 cxd5 exd5 Nc3 Nf6 Nf3 c6'.split(' ');

describe('the off-prep hint', () => {
  it('says when the move you played is closer to your other lines', () => {
    const fen = walkSan(exchange).fens.at(-1)!;
    const hint = offPrepHint(qgd, index, fen, 'g3', 'Bg5', opts)!;
    expect(hint.suggestion).toBe('g3');
    expect(hint.mine).toBe('Bg5');
    expect(hint.reason).toBe('You play g3 in 2 Slav and Indian lines, Bg5 in none');
    // The book has no 6.g3 here.
    expect(hint.offBook).toBe(true);
    expect(hint.tone).toBe('toward-far');
    expect(hint.removes).toBe(3);
  });

  it('says nothing when the move you played is no closer', () => {
    const fen = walkSan(exchange).fens.at(-1)!;
    expect(offPrepHint(qgd, index, fen, 'Qc2', 'Bg5', opts)).toBeNull();
  });

  it('says nothing about a capture you did not make', () => {
    const r = rep('w', ['d4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5']);
    const node = nodeAtLine(r, 'd4 d5 c4 e6 Nc3 Nf6 cxd5'.split(' '))!;
    expect(findAt(r, index, node, opts, ['Nf3'])).toBeNull();
  });
});

describe('the list', () => {
  it('finds a switch that transposes, and keeps to the region', () => {
    // 1...g6 first, and a King's Indian reached by 1...Nf6.
    const r = rep('b', ['d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O', 'd4 g6 c4 Bg7 Nc3 c5']);
    const all = tidyFinds([r], index, tree, nodeById(tree, ''), opts);
    const find = all.find((f) => f.mine === 'c5');
    expect(find?.suggestion).toBe('Nf6');
    expect(find?.kind).toBe('transposes');
    const sicilian = [...tree.byId.values()].find((node) => node.name === 'Sicilian Defence')!;
    expect(tidyFinds([r], index, tree, sicilian, opts)).toEqual([]);
  });

  it('puts the biggest savings first', () => {
    const finds = tidyFinds([qgd], index, tree, nodeById(tree, ''), opts);
    for (let i = 1; i < finds.length; i++) expect(finds[i - 1].removes).toBeGreaterThanOrEqual(finds[i].removes);
  });
});

describe('switching', () => {
  it('makes the new move yours and removes the old one with its line', () => {
    const node = nodeAtLine(qgd, [...exchange, 'Bg5'])!;
    const next = switchMove(qgd, node.id, 'g3')!;
    const parent = nodeAtLine(next, exchange)!;
    const kids = childrenOf(next, parent.id);
    expect(kids.map((kid) => kid.san)).toEqual(['g3']);
    expect(kids[0].preferred).toBe(true);
    expect(nodeAtLine(next, [...exchange, 'Bg5', 'Be7'])).toBeNull();
  });

  it('refuses an illegal move', () => {
    const node = nodeAtLine(qgd, [...exchange, 'Bg5'])!;
    expect(switchMove(qgd, node.id, 'Ke3')).toBeNull();
  });
});
