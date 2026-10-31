import { describe, expect, it } from 'vitest';
import { familiesIn, linesOf, openingsIn, tipsOf } from './openings';
import { referenceIndex } from './referenceIndex';
import { nameAt } from './reference';
import { addLine, createRepertoire, pruneCount, pruneLine, repertoireName } from './repertoire';
import { walkSan } from '../chess/core';
import type { Repertoire } from './types';

const index = referenceIndex();

function build(color: 'w' | 'b', lines: string[]): Repertoire {
  let rep = createRepertoire(repertoireName(color), color, `r_${color}`);
  for (const line of lines) rep = addLine(rep, line.split(' '), 'book').rep;
  return rep;
}

const KID = 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6';

describe('naming the stored tree', () => {
  it('names it for the side, never for an opening', () => {
    expect(repertoireName('w')).toBe('White Playbook');
    expect(repertoireName('b')).toBe('Black Playbook');
  });
});

describe('deriving openings', () => {
  it('finds nothing in an empty tree', () => {
    expect(openingsIn(createRepertoire('Black Playbook', 'b', 'e'), index)).toEqual([]);
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

  it("calls 1...e5 by Black's move when the book only names White's", () => {
    // 2...Nc6 is "King's Knight Opening: Normal Variation" in the book, which
    // is how the Classical starter set's 1...e5 was listed on the Playbook.
    const openings = openingsIn(build('b', ['e4 e5 Nf3 Nc6 Bc4 Bc5', 'e4 e5 Nf3 Nc6 Bb5 a6']), index);
    expect(openings.map((o) => o.name)).toEqual(['1...e5']);
    expect(openings[0].variations).toHaveLength(2);
  });

  it('keeps the book names when two would share one move label', () => {
    const openings = openingsIn(build('b', ['e4 e5 Nf3 Nc6 Bc4 Bc5', 'e4 e5 Nf3 Nc6 Bb5 a6', 'e4 e5 Qh5 Nc6']), index);
    expect(openings.map((o) => o.name)).not.toContain('1...e5');
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

describe('the lines of an opening', () => {
  const RUY = 'e4 e5 Nf3 Nc6 Bb5';
  const rep = build('w', [
    `${RUY} Nf6 O-O Nxe4 d4`,
    `${RUY} Nf6 O-O Nxe4 Re1`,
    `${RUY} a6 Ba4 Nf6 O-O Be7 Re1`,
  ]);
  const ruy = openingsIn(rep, index).find((o) => o.name === 'Ruy Lopez')!;
  const lines = linesOf(rep, ruy, index);

  it('lists every line, named without the opening in front', () => {
    expect(lines).toHaveLength(3);
    expect(lines.every((line) => !line.name.startsWith('Ruy Lopez'))).toBe(true);
  });

  it('tells lines with the same name apart by where they split', () => {
    const berlin = lines.filter((line) => line.path.includes('Nf6') && line.path[5] === 'Nf6');
    expect(berlin).toHaveLength(2);
    expect(berlin.map((line) => line.split)).toEqual(['5.d4', '5.Re1']);
    expect(lines.filter((line) => line.split)).toHaveLength(2);
  });

  it('counts the moves only that line owns', () => {
    expect(lines.map((line) => line.removes)).toEqual([1, 1, 6]);
  });

  it('takes the opening with its last line', () => {
    const one = build('w', [`${RUY} a6`]);
    const only = openingsIn(one, index)[0];
    const [line] = linesOf(one, only, index);
    expect(line.removes).toBe(6);
    expect(Object.keys(pruneLine(one, line.tipId).nodes)).toHaveLength(0);
  });
});

describe('the Playbook by family', () => {
  const NAJDORF = 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5 Nb3 Be6 f3 Nbd7 g4 Be7';

  it('lists a Sicilian as the Sicilian, however deep one line goes', () => {
    const rep = build('b', [NAJDORF]);
    expect(openingsIn(rep, index)[0].name).toMatch(/Najdorf/);
    const families = familiesIn(rep, index);
    expect(families.map((f) => f.name)).toEqual(['Sicilian Defence']);
    expect(families[0].path).toEqual(['e4', 'c5']);
    // Its lines are named after the family, so the variation still shows.
    expect(linesOf(rep, families[0], index)[0].name).toMatch(/^Najdorf/);
  });

  it('gives a family found inside another its own row, kept out of the outer one', () => {
    const rep = build('b', ['d4 Nf6 c3 g6 Nf3 Bg7', KID]);
    const families = familiesIn(rep, index);
    const names = families.map((f) => f.name);
    expect(names).toEqual(expect.arrayContaining(['Indian Defence', "King's Indian Defence"]));
    const indian = families.find((f) => f.name === 'Indian Defence')!;
    expect(indian.lines).toBe(1);
    expect(linesOf(rep, indian, index).map((l) => l.path.join(' '))).toEqual(['d4 Nf6 c3 g6 Nf3 Bg7']);
    // Deleting the Indian Defence leaves the King's Indian whole.
    let after = rep;
    for (const tip of tipsOf(rep, indian)) after = pruneLine(after, tip);
    expect(indian.removes).toBe(Object.keys(rep.nodes).length - Object.keys(after.nodes).length);
    expect(familiesIn(after, index).map((f) => f.name)).toEqual(["King's Indian Defence"]);
  });

  it('does not list the first move a family is reached by', () => {
    const names = familiesIn(build('w', ['e4 c5 Nf3 d6', 'e4 e6 d4 d5 Nc3']), index).map((f) => f.name);
    expect(names.sort()).toEqual(['French Defence', 'Sicilian Defence']);
  });
});
