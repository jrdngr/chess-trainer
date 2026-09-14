import { describe, expect, it } from 'vitest';
import { openingsAcross, openingsIn } from './openings';
import { referenceIndex } from './referenceIndex';
import { nameAt } from './reference';
import { addLine, createRepertoire, pruneCount, pruneLine, repertoireName } from './repertoire';
import { walkSan } from '../chess/core';
import type { Repertoire } from './types';

const index = referenceIndex();

function build(color: 'w' | 'b', lines: string[]): Repertoire {
  let rep = createRepertoire(repertoireName(color), color, `r_${color}`);
  for (const line of lines) rep = addLine(rep, line.split(' '), 'reference').rep;
  return rep;
}

const KID = 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6';

describe('naming the stored tree', () => {
  it('names it for the side, never for an opening', () => {
    expect(repertoireName('w')).toBe('White repertoire');
    expect(repertoireName('b')).toBe('Black repertoire');
  });
});

describe('deriving openings', () => {
  it('finds nothing in an empty tree', () => {
    expect(openingsIn(createRepertoire('Black repertoire', 'b', 'e'), index)).toEqual([]);
  });

  it('names a Black opening after what Black did, not what White did', () => {
    // The bug this exists for: 1.d4 is the Queen's Pawn Opening, so a Black
    // King's Indian saved under the first named position it passed through was
    // filed as an opening the player never chose.
    const openings = openingsIn(build('b', [KID]), index);
    expect(openings).toHaveLength(1);
    expect(openings[0].name).toMatch(/^King's Indian Defence/);
    expect(openings[0].path).toEqual(['d4', 'Nf6', 'c4', 'g6', 'Nc3', 'Bg7', 'e4']);
  });

  it('splits one first move into the openings it answers', () => {
    // 1.e4 is one move but three openings. Listing "King's Pawn Game" with
    // everything inside it is the same mistake in the other direction.
    const names = openingsIn(
      build('w', ['e4 c5 Nf3 d6', 'e4 e5 Nf3 Nc6 Bb5 a6', 'e4 e6 d4 d5 Nc3']),
      index,
    ).map((o) => o.name);
    expect(names).toHaveLength(3);
    expect(names).toEqual(expect.arrayContaining([expect.stringMatching(/^French Defence/)]));
    expect(names).toEqual(expect.arrayContaining([expect.stringMatching(/^Sicilian Defence/)]));
    expect(names).not.toContain("King's Pawn Game");
  });

  it('keeps a waypoint that has lines of its own', () => {
    // 1.e4 c5 2.Nf3 stops inside the Sicilian, so the Sicilian is a real row
    // here rather than a name on the way to a deeper one.
    const openings = openingsIn(build('w', ['e4 c5 Nf3']), index);
    expect(openings.map((o) => o.name)).toEqual(['Sicilian Defence']);
  });

  it('nests a deeper name as a variation of the opening it sits in', () => {
    // Two King's Indians that part company at move nine: the heading is what
    // they have in common and each continuation is a variation under it.
    const openings = openingsIn(build('b', [`${KID} f3 O-O`, `${KID} Nf3 O-O`]), index);
    expect(openings).toHaveLength(1);
    expect(openings[0].name).toMatch(/^King's Indian Defence/);
    expect(openings[0].variations).toHaveLength(2);
    expect(openings[0].variations.map((v) => v.name)).toEqual(
      expect.arrayContaining([expect.stringMatching(/Sämisch/)]),
    );
  });

  it('drops a heading that holds one variation and nothing of its own', () => {
    // A lone Sämisch is listed as a Sämisch. The King's Indian above it holds
    // no lines and offers no choice — every line under it is the Sämisch — so
    // it is a step on the way rather than an opening that was chosen.
    const openings = openingsIn(build('b', [`${KID} f3 O-O`]), index);
    expect(openings).toHaveLength(1);
    expect(openings[0].name).toMatch(/Sämisch/);
    expect(openings[0].variations).toEqual([]);
  });

  it('names an opening after the move itself when the book cannot name it', () => {
    // The book names every first move it holds, so this is the invariant rather
    // than a worked example: a region is named for a position, or for its own
    // move — never for the repertoire it happens to sit in.
    const openings = openingsIn(build('w', ['b3 e5 Bb2 Nc6']), index);
    expect(openings).toHaveLength(1);
    expect(openings[0].lines).toBe(1);
    const named = nameAt(index, walkSan(openings[0].path).fens.at(-1)!);
    if (named) expect(openings[0].name).toBe(named.name);
    else expect(openings[0].name).toMatch(/^\d+\.{1,3}/);
  });

  it('accounts for every line exactly once', () => {
    const rep = build('b', [`${KID} f3 O-O`, `${KID} Nf3 O-O`, 'e4 c5 Nf3 d6', 'b4 e5']);
    const total = (os: ReturnType<typeof openingsIn>): number =>
      os.reduce((sum, o) => sum + o.lines, 0);
    // Lines counted at the top level already include those in variations, so a
    // top-level sum is the whole tree's leaf count.
    expect(total(openingsIn(rep, index))).toBe(4);
  });

  it('measures an opening by what exists only for it', () => {
    // The heading lands at the seventh move, so its own subtree is two nodes —
    // but eight moves exist only to reach it, and that is its size.
    const openings = openingsIn(build('b', [KID]), index);
    expect(openings[0].moves).toBe(2);
    expect(openings[0].removes).toBe(8);
    expect(openings[0].depth).toBe(8);
  });

  it('puts the biggest opening first', () => {
    const openings = openingsIn(
      build('w', ['e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3', 'e4 e6 d4 d5']),
      index,
    );
    for (let i = 1; i < openings.length; i += 1) {
      expect(openings[i - 1].removes).toBeGreaterThanOrEqual(openings[i].removes);
    }
  });

  it('keeps each opening pointing at the tree it came from', () => {
    const openings = openingsAcross([build('w', ['e4 e6 d4 d5']), build('b', [KID])], index);
    expect(openings.map((o) => o.color).sort()).toEqual(['b', 'w']);
    for (const opening of openings) expect(opening.repertoireId).toBe(`r_${opening.color}`);
  });
});

describe('deleting an opening', () => {
  it('takes the move order that only led there', () => {
    const rep = build('b', [KID]);
    const kid = openingsIn(rep, index)[0];
    const after = pruneLine(rep, kid.rootId);
    // Nothing left dangling: six moves of Indian setup would otherwise stand
    // with nothing under them.
    expect(Object.keys(after.nodes)).toHaveLength(0);
    expect(after.rootChildren).toEqual([]);
  });

  it('stops at a move another opening also needs', () => {
    const rep = build('w', ['e4 c5 Nf3 d6', 'e4 e6 d4 d5']);
    const french = openingsIn(rep, index).find((o) => /^French Defence/.test(o.name))!;
    const after = pruneLine(rep, french.rootId);
    // 1.e4 survives, because the Sicilian still needs it.
    expect(after.rootChildren).toHaveLength(1);
    expect(after.nodes[after.rootChildren[0]].san).toBe('e4');
    expect(openingsIn(after, index).map((o) => o.name)).toEqual([
      expect.stringMatching(/^Sicilian Defence/),
    ]);
  });

  it('counts the cost before paying it', () => {
    const rep = build('b', [KID]);
    const kid = openingsIn(rep, index)[0];
    expect(pruneCount(rep, kid.rootId)).toBe(kid.removes);
    expect(Object.keys(pruneLine(rep, kid.rootId).nodes)).toHaveLength(
      Object.keys(rep.nodes).length - kid.removes,
    );
  });

  it('leaves a repertoire it was never in alone', () => {
    const rep = build('w', ['e4 e5']);
    expect(pruneLine(rep, 'nope')).toBe(rep);
    expect(pruneCount(rep, 'nope')).toBe(0);
  });
});
