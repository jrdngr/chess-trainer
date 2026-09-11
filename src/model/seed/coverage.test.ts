import { describe, expect, it } from 'vitest';
import { positionKey, sansToMoveText, type Color } from '../../chess/core';
import { lookup, totalGamesAt } from '../reference';
import { referenceIndex } from '../referenceIndex';
import { childrenOf, fenAt } from '../repertoire';
import type { Repertoire } from '../types';
import { buildSeedRepertoires } from '../../store/seed';

/**
 * "All variations" is a claim, so it gets checked rather than asserted.
 *
 * For every position a repertoire reaches where the opponent is to move and we
 * already have an answer prepared, every reply the reference database calls
 * mainstream must have a prepared answer too. Positions where a line simply
 * ends are not holes — that is prep running out, not prep disagreeing with
 * itself.
 *
 * Positions are merged by key first, exactly as training does, so a line
 * covered through one move order counts as covered through all of them.
 *
 * The opening position is checked per colour rather than per repertoire: a
 * Black repertoire is allowed to answer only 1.d4 as long as a sibling
 * repertoire answers 1.e4.
 */
const MIN_SHARE = 3;
const MAX_PLY = 18;

interface Gap {
  line: string;
  san: string;
  share: number;
  ply: number;
  have: string[];
}

/** Every position the repertoire reaches, with the union of its answers. */
function answersByPosition(rep: Repertoire) {
  const answers = new Map<string, Set<string>>();
  const shortest = new Map<string, string[]>();
  const walk = (nodeId: string | null, path: string[]) => {
    const key = positionKey(fenAt(rep, nodeId));
    const kids = childrenOf(rep, nodeId);
    const set = answers.get(key) ?? new Set<string>();
    for (const kid of kids) set.add(kid.san);
    answers.set(key, set);
    const prev = shortest.get(key);
    if (!prev || path.length < prev.length) shortest.set(key, path);
    for (const kid of kids) walk(kid.id, [...path, kid.san]);
  };
  walk(null, []);
  return { answers, shortest };
}

function findGaps(rep: Repertoire): Gap[] {
  const index = referenceIndex();
  const { answers, shortest } = answersByPosition(rep);
  const gaps: Gap[] = [];

  for (const [key, prepared] of answers) {
    const path = shortest.get(key)!;
    // The opening position is a per-colour question, checked separately.
    if (path.length === 0) continue;
    if (path.length > MAX_PLY) continue;
    if (prepared.size === 0) continue;
    // Only positions where the opponent chooses.
    const turn: Color = path.length % 2 === 0 ? 'w' : 'b';
    if (turn === rep.color) continue;

    const entry = index.entries.get(key);
    if (!entry) continue;
    const total = totalGamesAt(entry);
    if (total === 0) continue;

    for (const move of entry.moves) {
      const share = (move.games / total) * 100;
      if (share < MIN_SHARE) continue;
      if (prepared.has(move.san)) continue;
      gaps.push({
        line: sansToMoveText(path),
        san: move.san,
        share: Math.round(share),
        ply: path.length,
        have: [...prepared],
      });
    }
  }

  return gaps.sort((a, b) => a.ply - b.ply || b.share - a.share);
}

describe('repertoire coverage', () => {
  const reps = buildSeedRepertoires();

  for (const rep of reps) {
    it(`${rep.name} answers every reply played in at least ${MIN_SHARE}% of games`, () => {
      const gaps = findGaps(rep).map(
        (g) => `after ${g.line}: no answer to ${g.san} (${g.share}% of games, have ${g.have.join('/')})`,
      );
      expect(gaps).toEqual([]);
    });
  }

  it('meets every mainstream first move across the Black repertoires', () => {
    const index = referenceIndex();
    const start = lookup(index, reps[0].rootFen)!;
    const total = totalGamesAt(start);
    const answered = new Set(
      reps.filter((r) => r.color === 'b').flatMap((r) => childrenOf(r, null).map((m) => m.san)),
    );
    const missing = start.moves
      .filter((m) => (m.games / total) * 100 >= MIN_SHARE)
      .filter((m) => !answered.has(m.san))
      .map((m) => `${m.san} (${Math.round((m.games / total) * 100)}%)`);
    expect(missing).toEqual([]);
  });

  it('gives White a single first move, since White chooses', () => {
    for (const rep of reps.filter((r) => r.color === 'w')) {
      expect(childrenOf(rep, null).map((m) => m.san)).toEqual(['d4']);
    }
  });

  it('reaches deep into the main lines of every opening', () => {
    const deepest = (rep: Repertoire) => {
      let best = 0;
      const walk = (id: string | null, depth: number) => {
        best = Math.max(best, depth);
        for (const kid of childrenOf(rep, id)) walk(kid.id, depth + 1);
      };
      walk(null, 0);
      return best;
    };
    expect(reps.map((r) => [r.name, deepest(r) >= 24])).toEqual([
      ["White — Queen's Gambit", true],
      ["Black — King's Indian", true],
      ['Black — Sicilian Dragon', true],
    ]);
  });
});
