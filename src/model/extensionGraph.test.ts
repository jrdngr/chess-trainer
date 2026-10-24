import { describe, expect, it } from 'vitest';
import { extensionRoot, extensionRoots, layoutGraph, MAX_PLIES } from './extensionGraph';
import { treeKinds } from './extensions';
import { referenceIndex } from './referenceIndex';
import { addLine, createRepertoire, pathTo } from './repertoire';
import type { Repertoire } from './types';

const index = referenceIndex();
const ITALIAN = 'e4 e5 Nf3 Nc6 Bc4 Bc5';

function build(lines: string[]): Repertoire {
  let rep = createRepertoire('White Playbook', 'w', 'w');
  for (const line of lines) rep = addLine(rep, line.split(' '), 'board').rep;
  return rep;
}
const nodeAt = (rep: Repertoire, line: string) =>
  Object.values(rep.nodes).find((n) => pathTo(rep, n.id).map((m) => m.san).join(' ') === line)!;

describe('the review graph', () => {
  const rep = build([`${ITALIAN} c3 Nf6 d4`, `${ITALIAN} d3 Nf6 Nbd2`, `${ITALIAN} d3 Nf6 O-O`]);
  const kinds = treeKinds(rep, index);
  const root = nodeAt(rep, ITALIAN);

  it('carries the first child along its row and forks the rest below', () => {
    const rows = layoutGraph(rep, index, kinds, root.id);
    expect(rows[0].parent).toBeNull();
    expect(rows[0].cells.map((c) => c.label)).toEqual(['c3', 'Nf6', 'd4']);
    // 4.d3 forks off the root; its own branch, 6.O-O or 6.Nbd2, forks off 5...Nf6.
    expect(rows).toHaveLength(3);
    expect(rows[1].start).toBe(0);
    expect(rows[2].parent).toEqual({ row: 1, col: 1 });
  });

  it('marks the moves that leave the book', () => {
    const rows = layoutGraph(rep, index, kinds, root.id);
    const nbd2 = rows.flatMap((r) => r.cells).find((c) => c.label === 'Nbd2');
    expect(nbd2?.kind).not.toBe('book');
    expect(rows[0].cells[0].kind).toBe('book');
  });

  it('keeps only the paths to extensions under the Extensions filter', () => {
    const rows = layoutGraph(rep, index, kinds, root.id, { extOnly: true });
    expect(rows.flatMap((r) => r.cells.map((c) => c.label))).not.toContain('c3');
  });

  it('ends a row that reaches a position drawn above with a join to it', () => {
    const t = build([`${ITALIAN} d3 Nf6 O-O d6 c3`, `${ITALIAN} d3 Nf6 c3 d6 O-O`]);
    const rows = layoutGraph(t, index, treeKinds(t, index), nodeAt(t, ITALIAN).id);
    const join = rows.flatMap((r) => r.cells).find((c) => c.kind === 'join');
    expect(join?.joinRow).toBe(0);
  });

  it('cuts a line past the depth limit to a "+N"', () => {
    const long = `${ITALIAN} c3 Nf6 d4 exd4 cxd4 Bb4+ Bd2 Bxd2+ Nbxd2 d5 exd5 Nxd5 Qb3 Nce7 O-O O-O Rfe1 c6 a4`;
    const t = build([long]);
    const rows = layoutGraph(t, index, treeKinds(t, index), nodeAt(t, ITALIAN).id);
    expect(rows[0].cells).toHaveLength(MAX_PLIES + 1);
    expect(rows[0].cells.at(-1)).toMatchObject({ kind: 'more', label: '+3' });
  });

  it('acts on an extension from its first move off the book', () => {
    const tip = nodeAt(rep, `${ITALIAN} d3 Nf6 Nbd2`);
    expect(extensionRoot(rep, kinds, tip.id)?.san).toBe('Nbd2');
    expect(extensionRoot(rep, kinds, root.id)).toBeNull();
    expect(extensionRoots(rep, kinds).map((n) => n.san)).toContain('Nbd2');
  });
});
