import { describe, expect, it } from 'vitest';
import { fenTurn, positionKey, sansToMoveText } from '../../chess/core';
import { lookup, totalGamesAt } from '../reference';
import { referenceIndex } from '../referenceIndex';
import { childrenOf, fenAt } from '../repertoire';
import type { Repertoire } from '../types';
import { buildSeedRepertoires } from '../../store/seed';

/**
 * "All variations" is a claim, so it gets checked rather than asserted.
 *
 * For every position the repertoire reaches where the opponent is to move and
 * we already have an answer prepared, every reply the reference database calls
 * mainstream must have a prepared answer too. Positions where a line simply
 * ends are not holes — that is prep running out, not prep disagreeing with
 * itself.
 *
 * Positions are merged by key first, exactly as training does, so a line
 * covered through one move order counts as covered through all of them.
 */
const MIN_SHARE = 3;
const MAX_PLY = 18;

/** Replies we have consciously decided not to cover, and why. */
const ACCEPTED_GAPS: Record<string, { san: string; because: string }[]> = {
  "Black — King's Indian": [
    {
      san: 'e4',
      because:
        'The King’s Indian is a defence to 1.d4. What to meet 1.e4 with is a separate ' +
        'decision the user has not made yet, and seeding a guess would put moves they do ' +
        'not play into the review queue.',
    },
  ],
};

interface Gap {
  line: string;
  san: string;
  share: number;
  ply: number;
  have: string[];
}

function findGaps(rep: Repertoire): Gap[] {
  const index = referenceIndex();
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

  const accepted = new Set((ACCEPTED_GAPS[rep.name] ?? []).map((g) => g.san));
  const gaps: Gap[] = [];

  for (const [key, prepared] of answers) {
    const path = shortest.get(key)!;
    if (path.length > MAX_PLY) continue;
    if (prepared.size === 0) continue;
    const fen = fenAt(rep, null);
    void fen;
    const entry = index.entries.get(key);
    if (!entry) continue;
    const total = totalGamesAt(entry);
    if (total === 0) continue;
    // Only positions where the opponent chooses.
    const turn = path.length % 2 === 0 ? 'w' : 'b';
    if (turn === rep.color) continue;

    for (const move of entry.moves) {
      const share = (move.games / total) * 100;
      if (share < MIN_SHARE) continue;
      if (prepared.has(move.san)) continue;
      if (path.length === 0 && accepted.has(move.san)) continue;
      gaps.push({
        line: sansToMoveText(path) || 'the starting position',
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
    describe(rep.name, () => {
      it(`answers every reply played in at least ${MIN_SHARE}% of games`, () => {
        const gaps = findGaps(rep).map(
          (g) => `after ${g.line}: no answer to ${g.san} (${g.share}% of games, have ${g.have.join('/')})`,
        );
        expect(gaps).toEqual([]);
      });

      it('covers the opponent replies at move one', () => {
        const accepted = new Set((ACCEPTED_GAPS[rep.name] ?? []).map((g) => g.san));
        const index = referenceIndex();
        const start = lookup(index, rep.rootFen)!;
        const total = totalGamesAt(start);
        const first = new Set(
          rep.color === 'w'
            ? childrenOf(rep, null).map((m) => m.san)
            : childrenOf(rep, null).map((m) => m.san),
        );
        const missing = start.moves
          .filter((m) => (m.games / total) * 100 >= MIN_SHARE)
          .filter((m) => !first.has(m.san) && !accepted.has(m.san))
          .map((m) => m.san);
        // A White repertoire chooses its own first move, so there is nothing
        // to cover; a Black one must meet everything.
        expect(rep.color === 'w' ? [] : missing).toEqual([]);
      });

      it('states why any accepted gap is accepted', () => {
        for (const gap of ACCEPTED_GAPS[rep.name] ?? []) {
          expect(gap.because.length).toBeGreaterThan(40);
        }
      });
    });
  }

  it('reaches deep into the main lines of both openings', () => {
    const [white, black] = reps;
    const deepest = (rep: Repertoire) => {
      let best = 0;
      const walk = (id: string | null, depth: number) => {
        best = Math.max(best, depth);
        for (const kid of childrenOf(rep, id)) walk(kid.id, depth + 1);
      };
      walk(null, 0);
      return best;
    };
    expect(deepest(white)).toBeGreaterThanOrEqual(24);
    expect(deepest(black)).toBeGreaterThanOrEqual(30);
    expect(fenTurn(white.rootFen)).toBe('w');
  });
});
