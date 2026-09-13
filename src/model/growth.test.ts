import { describe, expect, it } from 'vitest';
import { positionKey } from '../chess/core';
import {
  advance,
  atHole,
  enterHole,
  findHoles,
  growthRows,
  isUsersTurn,
  lineFor,
  optionsAt,
  preparedHere,
  startGrowth,
  steer,
} from './growth';
import { referenceIndex } from './referenceIndex';
import { addLine, createRepertoire, hasLine } from './repertoire';
import type { Repertoire } from './types';

const index = referenceIndex();

/** The shape a real user ends up with: one line saved from a run or a game. */
function thin(color: 'w' | 'b', line: string, name = 'Test'): Repertoire {
  const rep = createRepertoire(name, color, `r_${color}`);
  return addLine(rep, line.split(' '), 'reference').rep;
}

const white = thin('w', 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3');
const black = thin('b', 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6');

describe('finding holes', () => {
  it('finds the unanswered replies in a thin repertoire', () => {
    expect(findHoles(white, index).length).toBeGreaterThan(0);
    expect(findHoles(black, index).length).toBeGreaterThan(0);
  });

  it('counts a line that simply ends, which findGaps deliberately does not', () => {
    // 1.e4 c5 2.Nf3 d6 3.d4 cxd4 4.Nxd4 Nf6 5.Nc3 ends on White's move, so
    // Black is to move with nothing prepared. Every popular reply is a hole.
    const deep = findHoles(white, index).filter((hole) => hole.path.length === 9);
    expect(deep.length).toBeGreaterThan(0);
  });

  it('only ever asks about positions where the opponent is to move', () => {
    for (const rep of [white, black]) {
      for (const hole of findHoles(rep, index)) {
        const turn = hole.path.length % 2 === 0 ? 'w' : 'b';
        expect(turn).not.toBe(rep.color);
      }
    }
  });

  it('never reports a reply the repertoire already answers', () => {
    for (const hole of findHoles(white, index)) {
      expect(hasLine(white, [...hole.path, hole.san])).toBe(false);
    }
  });

  it('respects the popularity threshold', () => {
    const loose = findHoles(white, index, { minShare: 0.2 });
    const tight = findHoles(white, index, { minShare: 3 });
    expect(tight.length).toBeLessThanOrEqual(loose.length);
    for (const hole of tight) expect(hole.share).toBeGreaterThanOrEqual(3);
  });

  it('respects the depth limit', () => {
    for (const hole of findHoles(white, index, { maxPly: 4 })) {
      expect(hole.path.length).toBeLessThan(4);
    }
  });

  it('orders shallowest and most popular first', () => {
    const holes = findHoles(white, index);
    for (let i = 1; i < holes.length; i += 1) {
      const a = holes[i - 1];
      const b = holes[i];
      expect(a.path.length <= b.path.length).toBe(true);
      if (a.path.length === b.path.length) expect(a.share).toBeGreaterThanOrEqual(b.share);
    }
  });

  it('finds nothing in an empty White repertoire, whose first move answers nothing', () => {
    expect(findHoles(createRepertoire('Empty', 'w', 'e'), index)).toEqual([]);
  });
});

describe('the lobby', () => {
  it('puts the shallowest opening at the top', () => {
    const rows = growthRows([white], index);
    expect(rows.length).toBeGreaterThan(1);
    for (let i = 1; i < rows.length; i += 1) {
      expect(rows[i - 1].depth).toBeLessThanOrEqual(rows[i].depth);
    }
  });

  it('gives every hole exactly one row', () => {
    const rows = growthRows([white], index);
    const total = rows.reduce((sum, row) => sum + row.holes.length, 0);
    expect(total).toBe(findHoles(white, index).length);
  });

  it('files holes too shallow to have a name under the repertoire itself', () => {
    // A Black repertoire that meets 1.d4 but not 1.e4 has its most urgent hole
    // at ply 0, above any opening name. That must still be reachable.
    const rows = growthRows([black], index);
    const root = rows.find((row) => row.depth === 0);
    expect(root).toBeDefined();
    expect(root!.name).toBe('Test');
  });

  it('names a row after the opening when there is one', () => {
    const names = growthRows([white], index).map((row) => row.name);
    expect(names.some((name) => /Sicilian/.test(name))).toBe(true);
  });

  it('offers an empty Black repertoire every first move it cannot meet', () => {
    const rows = growthRows([createRepertoire('Empty', 'b', 'e')], index);
    expect(rows).toHaveLength(1);
    expect(rows[0].depth).toBe(0);
    expect(rows[0].holes.length).toBeGreaterThan(1);
  });

  it('offers an empty White repertoire nothing, because there is nothing to answer', () => {
    // A hole is a reply you cannot meet, and White's first move answers
    // nothing. An empty White repertoire has to be seeded elsewhere — the
    // lobby says so rather than showing an empty list.
    expect(growthRows([createRepertoire('Empty', 'w', 'e')], index)).toEqual([]);
  });
});

describe('walking a run', () => {
  it('starts at the root with the player to move for White', () => {
    const row = growthRows([white], index)[0];
    const run = startGrowth(white, row);
    expect(run.path).toEqual([]);
    expect(isUsersTurn(run)).toBe(true);
    expect(run.hole).toBeNull();
  });

  it('accepts a prepared move and refuses anything else', () => {
    const row = growthRows([white], index)[0];
    const run = startGrowth(white, row);
    expect(advance(white, run, 'e4')).not.toBeNull();
    expect(advance(white, run, 'd4')).toBeNull();
    expect(advance(white, run, 'Nf3')).toBeNull();
  });

  it('steers to a hole and stops there', () => {
    const row = growthRows([white], index)[0];
    let run = startGrowth(white, row);
    for (let i = 0; i < 24 && !atHole(white, run); i += 1) {
      if (isUsersTurn(run)) {
        const mine = preparedHere(white, run);
        if (!mine.length) break;
        run = advance(white, run, mine[0].san)!;
      } else {
        const reply = steer(white, index, run);
        expect(reply).not.toBeNull();
        if (reply!.hole) {
          run = enterHole(run, reply!.hole);
          break;
        }
        run = advance(white, run, reply!.san)!;
      }
    }
    expect(atHole(white, run)).toBe(true);
    expect(isUsersTurn(run)).toBe(true);
  });

  it('lands on a hole the chosen row was actually aiming at', () => {
    const row = growthRows([white], index)[0];
    let run = startGrowth(white, row);
    run = advance(white, run, 'e4')!;
    const reply = steer(white, index, run);
    expect(reply!.hole).not.toBeNull();
    expect(run.targets.has(positionKey(run.fen))).toBe(true);
  });

  it('offers the book its replies at the hole, most played first', () => {
    const row = growthRows([white], index)[0];
    let run = startGrowth(white, row);
    run = advance(white, run, 'e4')!;
    const reply = steer(white, index, run)!;
    run = enterHole(run, reply.hole!);
    const options = optionsAt(index, run.fen);
    expect(options.length).toBeGreaterThan(0);
    for (let i = 1; i < options.length; i += 1) {
      expect(options[i - 1].games).toBeGreaterThanOrEqual(options[i].games);
    }
  });

  it('writes the opponent reply and your answer together', () => {
    const row = growthRows([white], index)[0];
    let run = startGrowth(white, row);
    run = advance(white, run, 'e4')!;
    const reply = steer(white, index, run)!;
    run = enterHole(run, reply.hole!);
    const line = lineFor(run, 'Nf3');
    // Their move has to be stored too, or the answer has no parent.
    expect(line).toEqual(['e4', reply.hole!.san, 'Nf3']);
  });
});
