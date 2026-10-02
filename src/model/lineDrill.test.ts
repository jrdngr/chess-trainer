import { describe, expect, it } from 'vitest';
import { askedKeys, continueLine, drawLines, drillableLines, yoursAt } from './lineDrill';
import { nodeById, openingTree } from './openingTree';
import { referenceIndex } from './referenceIndex';
import { addLine, createRepertoire, leafLines } from './repertoire';
import { mulberry32 } from './session';
import type { Repertoire } from './types';

const index = referenceIndex();
const tree = openingTree(index);

function rep(color: 'w' | 'b', ...lines: string[]): Repertoire {
  let out = createRepertoire('Test', color, `rep_${color}`);
  for (const line of lines) out = addLine(out, line.split(' '), 'seed').rep;
  return out;
}

const NAJDORF = 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6';
const ALAPIN = 'e4 c5 c3 d5 exd5 Qxd5';
const FRENCH = 'e4 e6 d4 d5';
const black = rep('b', NAJDORF, ALAPIN, FRENCH);
const sicilian = nodeById(tree, 'e4 c5');

describe('lines to drill', () => {
  it('are your leaf lines inside the region', () => {
    const lines = drillableLines(black, tree, sicilian).map((line) => line.sans.join(' '));
    expect(lines.sort()).toEqual([ALAPIN, NAJDORF].sort());
    expect(drillableLines(black, tree, tree.root)).toHaveLength(3);
  });

  it('ask the positions where it is your move', () => {
    const tip = leafLines(black).find((line) => line.sans.join(' ') === ALAPIN)!.tipId;
    // c5, d5, Qxd5: three answers of Black's.
    expect(askedKeys(black, tip)).toHaveLength(3);
    expect(yoursAt('b', 1)).toBe(true);
    expect(yoursAt('b', 0)).toBe(false);
  });

  it('draws different lines, and no more than there are', () => {
    const drawn = drawLines({ rep: black, tree, region: tree.root, index, lean: 'popular', count: 5, rand: mulberry32(3) });
    expect(drawn).toHaveLength(3);
    expect(new Set(drawn.map((line) => line.tipId)).size).toBe(3);
  });

  it('holds the draw to the lines asked for, when any are in reach', () => {
    const french = leafLines(black).find((line) => line.sans.join(' ') === FRENCH)!.tipId;
    const drawn = drawLines({
      rep: black,
      tree,
      region: tree.root,
      index,
      lean: 'popular',
      only: new Set([french]),
      count: 3,
      rand: mulberry32(1),
    });
    expect(drawn.map((line) => line.tipId)).toEqual([french]);
    // Nothing asked for is in the region: the draw falls back to every line there.
    const sicilianOnly = drawLines({
      rep: black,
      tree,
      region: sicilian,
      index,
      lean: 'popular',
      only: new Set([french]),
      count: 3,
      rand: mulberry32(1),
    });
    expect(sicilianOnly).toHaveLength(2);
  });

  it('leans on the weak lines when asked to', () => {
    const keysOf = (line: string) => askedKeys(black, leafLines(black).find((l) => l.sans.join(' ') === line)!.tipId);
    const alapin = new Set(keysOf(ALAPIN));
    const sore = new Set(keysOf(NAJDORF).filter((key) => !alapin.has(key)));
    const weakness = (_rep: string, key: string) => (sore.has(key) ? 50 : 1);
    let najdorf = 0;
    for (let seed = 1; seed <= 40; seed += 1) {
      const [first] = drawLines({ rep: black, tree, region: sicilian, index, lean: 'weak', weakness, count: 1, rand: mulberry32(seed) });
      if (first.sans.join(' ') === NAJDORF) najdorf += 1;
    }
    expect(najdorf).toBeGreaterThan(30);
  });
});

describe('carrying on along another prepared move', () => {
  it('follows the move played to the end of your prep', () => {
    const both = rep('w', 'e4 e5 Nf3 Nc6 Bb5', 'e4 e5 Nf3 Nc6 Bc4');
    const line = continueLine(both, ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4']);
    expect(line?.sans).toEqual(['e4', 'e5', 'Nf3', 'Nc6', 'Bc4']);
    expect(continueLine(both, ['e4', 'e5', 'Nf3'])?.sans.slice(0, 4)).toEqual(['e4', 'e5', 'Nf3', 'Nc6']);
    expect(continueLine(both, ['d4'])).toBeNull();
  });
});
