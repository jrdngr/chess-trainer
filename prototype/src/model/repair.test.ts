import { describe, expect, it } from 'vitest';
import {
  buildRepairs,
  costOf,
} from './repair';
import { generateSampleArchive } from './seed/sampleGames';
import { buildSeedRepertoires } from '../test/fixtures/seed';
import { applySan, positionKey } from '../chess/core';
import type { ImportedGame, Repertoire } from './types';

const reps = buildSeedRepertoires();
const games = generateSampleArchive({ username: 'tester', count: 80, seed: 7 });

describe('building repairs from your own games', () => {
  const items = buildRepairs(games, reps);

  it('finds something to repair in a real archive', () => {
    expect(items.length).toBeGreaterThan(0);
  });

  it('only ever asks about positions the player actually reached', () => {
    // Every item must correspond to a position some game of the right colour
    // passed through, on that player's turn.
    const seen = new Map<string, Set<string>>();
    for (const rep of reps) seen.set(rep.id, keysPlayed(games, rep));
    for (const item of items) {
      expect(seen.get(item.repertoireId)!.has(item.key)).toBe(true);
    }
  });

  it('always has something the player actually played there', () => {
    for (const item of items) {
      expect(item.played.length).toBeGreaterThan(0);
      for (const choice of item.played) expect(choice.count).toBeGreaterThan(0);
    }
  });

  it('gives off-prep items an expected move and unprepared items none', () => {
    for (const item of items) {
      if (item.kind === 'offprep') expect(item.expected.length).toBeGreaterThan(0);
      else expect(item.expected).toEqual([]);
    }
  });

  it('never lists a move the player played as their own prep', () => {
    for (const item of items.filter((i) => i.kind === 'offprep')) {
      for (const choice of item.played) {
        expect(item.expected).not.toContain(choice.san);
      }
    }
  });

  it('gives every item a stable, unique id', () => {
    const ids = new Set(items.map((i) => i.id));
    expect(ids.size).toBe(items.length);
    expect(buildRepairs(games, reps).map((i) => i.id)).toEqual(items.map((i) => i.id));
  });
});

describe('narrowing', () => {
  it('respects the games threshold', () => {
    const loose = buildRepairs(games, reps, { minGames: 1 });
    const tight = buildRepairs(games, reps, { minGames: 3 });
    expect(tight.length).toBeLessThanOrEqual(loose.length);
    for (const item of tight) expect(item.games).toBeGreaterThanOrEqual(3);
  });

  it('filters to one kind', () => {
    for (const item of buildRepairs(games, reps, { kinds: 'offprep' })) {
      expect(item.kind).toBe('offprep');
    }
    for (const item of buildRepairs(games, reps, { kinds: 'unprepared' })) {
      expect(item.kind).toBe('unprepared');
    }
  });

  it('filters to one repertoire', () => {
    const target = reps[0];
    for (const item of buildRepairs(games, reps, { repertoireId: target.id })) {
      expect(item.repertoireId).toBe(target.id);
    }
  });

  it('drops positions from games that were never lost when asked to', () => {
    for (const item of buildRepairs(games, reps, { lossesOnly: true })) {
      expect(item.results.losses).toBeGreaterThan(0);
    }
  });

  it('orders by cost when asked, and by weight otherwise', () => {
    const costly = buildRepairs(games, reps, { sort: 'costly' });
    for (let i = 1; i < costly.length; i += 1) {
      expect(costOf(costly[i - 1])).toBeGreaterThanOrEqual(costOf(costly[i]));
    }
    const common = buildRepairs(games, reps, { sort: 'common' });
    for (let i = 1; i < common.length; i += 1) {
      expect(common[i - 1].weight).toBeGreaterThanOrEqual(common[i].weight);
    }
  });

  it('returns nothing at all when there are no games', () => {
    expect(buildRepairs([], reps)).toEqual([]);
  });
});

describe('cost', () => {
  it('counts a draw as half a loss', () => {
    expect(costOf({ games: 4, results: { wins: 2, draws: 0, losses: 2 } })).toBe(0.5);
    expect(costOf({ games: 4, results: { wins: 2, draws: 4, losses: 0 } })).toBe(1 / 3);
  });

  it('is zero for a position that has never been played', () => {
    expect(costOf({ games: 0, results: { wins: 0, draws: 0, losses: 0 } })).toBe(0);
  });
});

/** Position keys this player's games reached, on their own turn. */
function keysPlayed(archive: ImportedGame[], rep: Repertoire): Set<string> {
  const out = new Set<string>();
  for (const game of archive) {
    if (game.userColor !== rep.color) continue;
    let fen = rep.rootFen;
    out.add(positionKey(fen));
    for (const san of game.moves) {
      const move = applySan(fen, san);
      if (!move) break;
      fen = move.after;
      out.add(positionKey(fen));
    }
  }
  return out;
}
