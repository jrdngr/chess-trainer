import { describe, expect, it } from 'vitest';
import {
  chooseMove,
  importedOnly,
  levelById,
  LEVELS,
  mergeGames,
  openingLine,
  PLAY_GAME_PLIES,
  PLAY_GAMES_CAP,
  playedGame,
  playGames,
  withPlayGame,
} from './play';
import type { ImportedGame } from './types';
import { mulberry32 } from './session';
import type { EngineLine } from '../engine/types';

function line(multipv: number, first: string): EngineLine {
  return { multipv, depth: 10, cp: 0, mate: null, pv: [first, 'e7e5'] };
}

const CANDIDATES = [line(1, 'e2e4'), line(2, 'd2d4'), line(3, 'g1f3'), line(4, 'c2c4')];

describe('levels', () => {
  it('gets harder all the way down the list', () => {
    for (let i = 1; i < LEVELS.length; i += 1) {
      expect(LEVELS[i].depth).toBeGreaterThan(LEVELS[i - 1].depth);
      expect(LEVELS[i].slip).toBeLessThan(LEVELS[i - 1].slip);
    }
  });

  it('falls back to a middling level for an unknown id', () => {
    expect(levelById('nonsense').id).toBe('club');
    expect(levelById('full').id).toBe('full');
  });

  it('never handicaps the top level', () => {
    expect(LEVELS[LEVELS.length - 1].slip).toBe(0);
  });
});

describe('choosing a move', () => {
  it('always takes the best line when it cannot slip', () => {
    const level = { ...levelById('club'), slip: 0 };
    for (let seed = 1; seed < 20; seed += 1) {
      expect(chooseMove(CANDIDATES, level, mulberry32(seed))).toBe('e2e4');
    }
  });

  it('returns null when there is nothing to play', () => {
    expect(chooseMove([], levelById('club'), Math.random)).toBeNull();
    expect(
      chooseMove([{ multipv: 1, depth: 1, cp: 0, mate: null, pv: [] }], levelById('club'), Math.random),
    ).toBeNull();
  });

  it('takes the only move on offer however weak it is', () => {
    const weak = levelById('casual');
    expect(chooseMove([line(1, 'a2a3')], weak, mulberry32(3))).toBe('a2a3');
  });

  it('plays the best move most of the time even at the weakest level', () => {
    const weak = levelById('casual');
    let best = 0;
    const runs = 400;
    for (let seed = 0; seed < runs; seed += 1) {
      if (chooseMove(CANDIDATES, weak, mulberry32(seed)) === 'e2e4') best += 1;
    }
    // Weights are 0.35 for the best and 0.325/0.1625/0.08 for the rest, so the
    // best move is still the single most likely — it just is not a certainty.
    expect(best / runs).toBeGreaterThan(0.2);
    expect(best / runs).toBeLessThan(0.6);
  });

  it('slips less as the level rises', () => {
    const rate = (id: string) => {
      let best = 0;
      for (let seed = 0; seed < 400; seed += 1) {
        if (chooseMove(CANDIDATES, levelById(id), mulberry32(seed)) === 'e2e4') best += 1;
      }
      return best / 400;
    };
    expect(rate('strong')).toBeGreaterThan(rate('club'));
    expect(rate('club')).toBeGreaterThan(rate('casual'));
  });

  it('ignores the order the engine reported lines in', () => {
    const shuffled = [CANDIDATES[2], CANDIDATES[0], CANDIDATES[3], CANDIDATES[1]];
    const level = { ...levelById('club'), slip: 0 };
    expect(chooseMove(shuffled, level, mulberry32(1))).toBe('e2e4');
  });
});

describe('keeping the opening', () => {
  const moves = ['e4', 'c5', 'Nf3', 'd6', 'd4', 'cxd4', 'Nxd4', 'Nf6', 'Nc3', 'a6'];

  it('ends a White line on a White move', () => {
    const line = openingLine(moves, 'w', 6);
    expect(line).toEqual(['e4', 'c5', 'Nf3', 'd6', 'd4']);
  });

  it('ends a Black line on a Black move', () => {
    const line = openingLine(moves, 'b', 5);
    expect(line).toEqual(['e4', 'c5', 'Nf3', 'd6']);
  });

  it('keeps the whole game when it is shorter than the cut', () => {
    expect(openingLine(['e4', 'e5', 'Nf3'], 'w', 16)).toEqual(['e4', 'e5', 'Nf3']);
  });

  it('gives back nothing for a game with no moves', () => {
    expect(openingLine([], 'w')).toEqual([]);
    expect(openingLine([], 'b')).toEqual([]);
  });

  it('drops a lone White move when Black is the one saving it', () => {
    expect(openingLine(['e4'], 'b')).toEqual([]);
  });
});

describe('games played here', () => {
  const club = levelById('club');
  const played = (over: Partial<Parameters<typeof playedGame>[0]> = {}) =>
    playedGame({ id: 'g1', color: 'w', moves: ['e4', 'e5', 'Nf3'], result: 'win', level: club, at: 1_700_000_000_000, ...over });

  it('records a finished game as a game, with the result from your side', () => {
    const game = played();
    expect(game).toMatchObject({ id: 'g1', source: 'play', userColor: 'w', result: '1-0', white: 'You', date: '2023-11-14' });
    expect(game?.black).toContain('Club');
    expect(played({ color: 'b', result: 'win' })?.result).toBe('0-1');
    expect(played({ color: 'b', result: 'loss' })?.result).toBe('1-0');
    expect(played({ result: 'draw' })?.result).toBe('1/2-1/2');
  });

  it('keeps the opening, not the whole game, and nothing of a game that never started', () => {
    const long = Array.from({ length: 120 }, (_, i) => (i % 2 === 0 ? 'Nf3' : 'Nf6'));
    expect(played({ moves: long })?.moves).toHaveLength(PLAY_GAME_PLIES);
    expect(played({ result: 'unfinished' })).toBeNull();
    expect(played({ moves: ['e4'] })).toBeNull();
  });

  it('sits with the imports without replacing them, newest first and capped', () => {
    const lichess: ImportedGame = { id: 'l1', source: 'lichess', white: 'a', black: 'b', result: '1-0', userColor: 'w', moves: ['e4'] };
    let games = withPlayGame([lichess], played()!);
    expect(games.map((g) => g.id)).toEqual(['g1', 'l1']);
    // The same game ended twice is one game.
    games = withPlayGame(games, played({ result: 'loss' })!);
    expect(games).toHaveLength(2);
    expect(games[0].result).toBe('0-1');
    for (let i = 0; i < PLAY_GAMES_CAP + 5; i += 1) games = withPlayGame(games, played({ id: `p${i}` })!);
    expect(playGames(games)).toHaveLength(PLAY_GAMES_CAP);
    expect(importedOnly(games)).toEqual([lichess]);
    expect(games[0].id).toBe(`p${PLAY_GAMES_CAP + 4}`);
  });

  it('merges the games of two devices: local imports, and both sides’ play', () => {
    const lichess: ImportedGame = { id: 'l1', source: 'lichess', white: 'a', black: 'b', result: '1-0', userColor: 'w', moves: ['e4'] };
    const here = played({ id: 'here', at: 1_700_000_000_000 })!;
    const there = played({ id: 'there', at: 1_700_500_000_000 })!;
    const merged = mergeGames([here, lichess], [there, here, { ...lichess, id: 'l2' }]);
    expect(merged.map((g) => g.id)).toEqual(['there', 'here', 'l1']);
  });
});
