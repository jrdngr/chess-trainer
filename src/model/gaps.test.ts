import { describe, expect, it } from 'vitest';
import { applySan, fenTurn, walkSan } from '../chess/core';
import { candidateAnswers, findGaps, gapColor } from './gaps';
import { referenceIndex } from './referenceIndex';
import { addLine, childrenOf, createRepertoire } from './repertoire';
import { buildSeedRepertoires, COVER_MIN_SHARE } from '../store/seed';

const index = referenceIndex();

/** A Sicilian that meets only the Open, so its gaps are known in advance. */
function thin() {
  let rep = createRepertoire('Black — thin', 'b', 'rep_thin');
  return addLine(rep, ['e4', 'c5', 'Nf3', 'd6', 'd4', 'cxd4', 'Nxd4', 'Nf6'], 'manual').rep;
}

describe('finding gaps', () => {
  it('finds the replies a thin repertoire cannot meet', () => {
    const gaps = findGaps(thin(), index, { minShare: 3 });
    const second = gaps.filter((g) => g.path.join(' ') === 'e4 c5').map((g) => g.san);
    // The Alapin and the Closed are both mainstream and both unanswered.
    expect(second).toContain('c3');
    expect(second).toContain('Nc3');
    expect(second).not.toContain('Nf3');
  });

  it('describes a gap well enough to fix it', () => {
    const gap = findGaps(thin(), index, { minShare: 3 }).find((g) => g.san === 'c3')!;
    expect(gap.path).toEqual(['e4', 'c5']);
    expect(gap.have).toContain('Nf3');
    expect(gap.share).toBeGreaterThan(3);
    expect(gap.games).toBeGreaterThan(0);
    // The position it names really is the one their move leads to.
    expect(applySan(gap.fen, gap.san)?.after).toBe(gap.after);
    expect(fenTurn(gap.fen)).toBe('w');
    expect(gapColor(gap)).toBe('b');
  });

  it('only counts positions where preparation exists and stops short', () => {
    for (const gap of findGaps(thin(), index, { minShare: 1 })) {
      expect(gap.have.length).toBeGreaterThan(0);
      expect(gap.have).not.toContain(gap.san);
      // A position the repertoire never reaches cannot be a gap in it.
      expect(walkSan(gap.path).fens[gap.path.length]).toBe(gap.fen);
    }
  });

  it('reports nothing for a repertoire that answers everything', () => {
    // The seeded repertoires are completed from the book at COVER_MIN_SHARE,
    // and `coverage.test.ts` holds them to exactly that bar. Asking here for a
    // lower one would test a promise nothing makes: below it the book is a long
    // tail of moves played a handful of times in 280k games.
    for (const rep of buildSeedRepertoires()) {
      expect(findGaps(rep, index, { minShare: COVER_MIN_SHARE }), rep.name).toEqual([]);
    }
  });

  it('finds more as the bar is lowered, never fewer', () => {
    const rep = thin();
    const counts = [5, 3, 1, 0.2].map((minShare) => findGaps(rep, index, { minShare }).length);
    for (let i = 1; i < counts.length; i += 1) {
      expect(counts[i]).toBeGreaterThanOrEqual(counts[i - 1]);
    }
  });

  it('opens a gap when a prepared branch is removed', () => {
    const rep = buildSeedRepertoires().find((r) => r.name.includes('King'))!;
    expect(findGaps(rep, index, { minShare: COVER_MIN_SHARE })).toEqual([]);
    // Drop one of the answers and the reply it met becomes unanswered.
    const d4 = childrenOf(rep, null).find((k) => k.san === 'd4')!;
    const nf6 = childrenOf(rep, d4.id)[0];
    const replies = childrenOf(rep, nf6.id);
    expect(replies.length).toBeGreaterThan(1);
    const without = {
      ...rep,
      nodes: { ...rep.nodes, [nf6.id]: { ...nf6, children: [replies[0].id] } },
    };
    const gaps = findGaps(without, index, { minShare: COVER_MIN_SHARE });
    expect(gaps.length).toBeGreaterThan(0);
    expect(gaps.every((g) => g.repertoireId === rep.id)).toBe(true);
  });

  it('stops looking past the depth it is given', () => {
    const deep = findGaps(thin(), index, { minShare: 1, maxPly: 40 }).length;
    const shallow = findGaps(thin(), index, { minShare: 1, maxPly: 4 }).length;
    expect(shallow).toBeLessThanOrEqual(deep);
    for (const gap of findGaps(thin(), index, { minShare: 1, maxPly: 4 })) {
      expect(gap.path.length).toBeLessThanOrEqual(4);
    }
  });

  it('puts the shallowest and most played first', () => {
    const gaps = findGaps(thin(), index, { minShare: 1 });
    for (let i = 1; i < gaps.length; i += 1) {
      const a = gaps[i - 1];
      const b = gaps[i];
      expect(a.path.length <= b.path.length).toBe(true);
      if (a.path.length === b.path.length) expect(a.share >= b.share).toBe(true);
    }
  });
});

describe('answers to choose from', () => {
  it('offers what the database plays, most played first', () => {
    const gap = findGaps(thin(), index, { minShare: 3 }).find((g) => g.san === 'c3')!;
    const answers = candidateAnswers(index, gap.after, 4);
    expect(answers.length).toBeGreaterThan(0);
    for (const answer of answers) {
      expect(applySan(gap.after, answer.san), answer.san).not.toBeNull();
    }
    for (let i = 1; i < answers.length; i += 1) {
      expect(answers[i - 1].games).toBeGreaterThanOrEqual(answers[i].games);
    }
  });

  it('comes back empty rather than guessing where the book ends', () => {
    expect(candidateAnswers(index, walkSan(['a3', 'a6', 'b3', 'b6']).fens[4])).toEqual([]);
  });
});
