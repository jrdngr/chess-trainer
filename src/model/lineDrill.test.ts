import { describe, expect, it } from 'vitest';
import { askedKeys, continueLine, drawLines, drillableLines, dueLines, LINE_BUDGET, MAX_LINES, sharedMoves, yourMoves, yoursAt } from './lineDrill';
import { createLineCard, DAY, gradeForLine, review } from './srs';
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

  it('leans on the lines whose card is weakest when asked to', () => {
    const tipOf = (line: string) => leafLines(black).find((l) => l.sans.join(' ') === line)!.tipId;
    const now = 1_000_000;
    const sore = { ...createLineCard(black.id, tipOf(NAJDORF), now), lapses: 4, ease: 1.3, stage: 'learning' as const };
    const fine = { ...createLineCard(black.id, tipOf(ALAPIN), now), stage: 'review' as const, due: now + 10 * DAY };
    const cards = { [sore.id]: sore, [fine.id]: fine };
    let najdorf = 0;
    for (let seed = 1; seed <= 40; seed += 1) {
      const [first] = drawLines({ rep: black, tree, region: sicilian, index, lean: 'weak', cards, count: 1, rand: mulberry32(seed), now: now - 1 });
      if (first.sans.join(' ') === NAJDORF) najdorf += 1;
    }
    expect(najdorf).toBeGreaterThan(30);
  });

  it('draws due lines first, then lines never drilled, then the rest', () => {
    const tipOf = (line: string) => leafLines(black).find((l) => l.sans.join(' ') === line)!.tipId;
    const now = 1_000_000;
    const due = { ...createLineCard(black.id, tipOf(FRENCH), now), stage: 'review' as const, due: now - 1 };
    const later = { ...createLineCard(black.id, tipOf(NAJDORF), now), stage: 'review' as const, due: now + DAY };
    const cards = { [due.id]: due, [later.id]: later };
    for (let seed = 1; seed <= 10; seed += 1) {
      const order = (draw: 'due' | 'new') =>
        drawLines({ rep: black, tree, region: tree.root, index, lean: 'popular', cards, draw, count: 3, rand: mulberry32(seed), now }).map(
          (line) => line.sans.join(' '),
        );
      expect(order('due')).toEqual([FRENCH, ALAPIN, NAJDORF]);
      expect(order('new')[0]).toBe(ALAPIN);
    }
    expect(dueLines(drillableLines(black, tree, tree.root), cards, now).map((line) => line.tipId)).toEqual([tipOf(FRENCH)]);
  });
});

describe('the grade a line earns', () => {
  it('is Guessed after any miss', () => {
    expect(gradeForLine([1, 1], 1)).toBe('again');
  });

  it('is the average time of the correct moves on the position scale', () => {
    expect(gradeForLine([1, 2, 4], 0)).toBe('easy');
    // One long think in a quick line pulls it down, but not all the way.
    expect(gradeForLine([1, 1, 10], 0)).toBe('good');
    expect(gradeForLine([9, 10], 0)).toBe('hard');
  });

  it('schedules the line card like a position card', () => {
    const card = createLineCard('rep_b', 'tip', 0);
    expect(review(card, 'easy', 0).card.tipId).toBe('tip');
    expect(review(card, 'easy', 0).card.stage).toBe('review');
    // Guessed: back after the first learning step, a minute.
    expect(review(card, 'again', 0).card.due).toBe(60_000);
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

describe('sized and grouped rounds of lines', () => {
  const NAJ_6G3 = 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Bg5 e6';
  const NAJ_BE3 = 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5';
  const DRAGON = 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6';
  const wide = rep('b', NAJ_6G3, NAJ_BE3, DRAGON, ALAPIN, FRENCH);

  it('counts your own moves in a line', () => {
    const [line] = drawLines({ rep: wide, tree, region: nodeById(tree, 'e4 e6'), index, lean: 'popular', count: 1, rand: mulberry32(1) });
    expect(yourMoves(line)).toBe(2);
  });

  it('keeps a sized round within the budget, and always plays one line', () => {
    for (let seed = 1; seed < 20; seed += 1) {
      const drawn = drawLines({ rep: wide, tree, region: tree.root, index, lean: 'popular', count: MAX_LINES, budget: 8, rand: mulberry32(seed) });
      expect(drawn.length).toBeGreaterThan(0);
      const total = drawn.reduce((sum, line) => sum + yourMoves(line), 0);
      if (drawn.length > 1) expect(total).toBeLessThanOrEqual(8);
    }
    const lone = drawLines({ rep: wide, tree, region: tree.root, index, lean: 'popular', count: MAX_LINES, budget: 1, rand: mulberry32(2) });
    expect(lone).toHaveLength(1);
    expect(LINE_BUDGET).toBe(15);
  });

  it('groups the lines closest to the first one', () => {
    for (let seed = 1; seed < 20; seed += 1) {
      const [first, ...rest] = drawLines({ rep: wide, tree, region: tree.root, index, lean: 'popular', count: 2, similar: true, rand: mulberry32(seed) });
      const best = Math.max(
        ...drillableLines(wide, tree, tree.root)
          .filter((line) => line.tipId !== first.tipId)
          .map((line) => sharedMoves(line.sans, first.sans)),
      );
      expect(sharedMoves(rest[0].sans, first.sans)).toBe(best);
    }
  });

  it('starts the next group away from the one just played', () => {
    const lines = drillableLines(wide, tree, tree.root);
    const avoid = new Set(lines.slice(0, 4).map((line) => line.tipId));
    const [first] = drawLines({ rep: wide, tree, region: tree.root, index, lean: 'popular', count: 1, avoid, rand: mulberry32(5) });
    expect(first.tipId).toBe(lines[4].tipId);
    // With nothing else in reach, the avoided lines still play.
    const all = new Set(lines.map((line) => line.tipId));
    expect(drawLines({ rep: wide, tree, region: tree.root, index, lean: 'popular', count: 1, avoid: all, rand: mulberry32(5) })).toHaveLength(1);
  });
});
