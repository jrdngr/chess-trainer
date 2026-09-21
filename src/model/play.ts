import type { EngineLine } from '../engine/types';
import type { Color } from '../chess/core';
import type { ImportedGame } from './types';

/**
 * Play: a game against the engine, with the opening kept.
 *
 * The engine wrapper only offers analysis — a ranked list of lines at a given
 * depth — and the asm.js build has no Skill Level option to set, so strength is
 * made here instead: a weak level thinks briefly, looks at more candidates, and
 * often takes one that is not the best. That has the same shape as a weaker
 * opponent (it sees less, and it picks wrong) and it works identically on the
 * heuristic fallback, which matters because some sandboxes never get a worker.
 */

export interface Level {
  id: string;
  name: string;
  depth: number;
  multiPv: number;
  /**
   * How often it declines the best line, 0..1. The rest of the distribution is
   * spread over the remaining candidates, nearest first.
   */
  slip: number;
}

export const LEVELS: Level[] = [
  {
    id: 'casual',
    name: 'Casual',
    depth: 1,
    multiPv: 5,
    slip: 0.65,
  },
  {
    id: 'club',
    name: 'Club',
    depth: 5,
    multiPv: 4,
    slip: 0.3,
  },
  {
    id: 'strong',
    name: 'Strong',
    depth: 11,
    multiPv: 3,
    slip: 0.08,
  },
  {
    id: 'full',
    name: 'Full',
    depth: 16,
    multiPv: 1,
    slip: 0,
  },
];

export const DEFAULT_LEVEL = 'club';

export function levelById(id: string): Level {
  return LEVELS.find((l) => l.id === id) ?? LEVELS[1];
}

/**
 * Which of the engine's candidate lines to play.
 *
 * Weights fall off geometrically from the best, so a slip usually costs one
 * place rather than dropping to the worst move on the board. Returns the UCI
 * move, or null when there is nothing to play.
 */
export function chooseMove(lines: EngineLine[], level: Level, rand: () => number): string | null {
  const usable = lines
    .filter((line) => line.pv.length > 0)
    .sort((a, b) => a.multipv - b.multipv);
  if (!usable.length) return null;
  if (usable.length === 1 || level.slip <= 0) return usable[0].pv[0];

  const weights = usable.map((_, i) => (i === 0 ? 1 - level.slip : level.slip / 2 ** i));
  const total = weights.reduce((sum, w) => sum + w, 0);
  let ticket = rand() * total;
  for (let i = 0; i < usable.length; i += 1) {
    ticket -= weights[i];
    if (ticket <= 0) return usable[i].pv[0];
  }
  return usable[usable.length - 1].pv[0];
}

/** How long a game's opening is worth keeping, in plies. */
export const OPENING_PLIES = 16;

/**
 * The opening of a game, as the line to write into a repertoire.
 *
 * Only your own moves need to be prepared, but the line has to include the
 * opponent's to reach them, so it is simply the first N plies — trimmed to end
 * on your move, since a line ending on the opponent's says nothing.
 */
export function openingLine(moves: string[], color: 'w' | 'b', plies = OPENING_PLIES): string[] {
  const cut = moves.slice(0, plies);
  // A White line has odd length (ends on White's move); a Black line, even.
  const wantsOdd = color === 'w';
  if (cut.length === 0) return cut;
  const isOdd = cut.length % 2 === 1;
  return isOdd === wantsOdd ? cut : cut.slice(0, -1);
}

export type GameResult = 'win' | 'loss' | 'draw' | 'unfinished';

export function resultLabel(result: GameResult, reason: string): string {
  switch (result) {
    case 'win':
      return `You won by ${reason}`;
    case 'loss':
      return `You lost by ${reason}`;
    case 'draw':
      return `Drawn by ${reason}`;
    default:
      return 'Game abandoned';
  }
}

/* ── games played here ──────────────────────────────────────────────────── */

/** How many Play games are kept. Older ones fall off the end. */
export const PLAY_GAMES_CAP = 200;

/**
 * How much of a Play game is kept: the opening, which is what the game is
 * data for. Coverage and Repair read the first couple of dozen plies, and
 * the whole game would make two hundred of them too big to sync.
 */
export const PLAY_GAME_PLIES = 40;

/**
 * A game played in Play, as a game — the same shape as an import, so Repair,
 * coverage and the recommendation engine read it the way they read one from
 * Lichess. Only a finished game is recorded: one that ended in mate, a draw
 * or a resignation, and had an opening in it at all.
 */
export function playedGame(game: {
  id: string;
  color: Color;
  moves: string[];
  result: GameResult;
  level: Level;
  at: number;
}): ImportedGame | null {
  if (game.result === 'unfinished' || game.moves.length < 2) return null;
  const result = game.result === 'draw' ? '1/2-1/2' : (game.result === 'win') === (game.color === 'w') ? '1-0' : '0-1';
  const engine = `Engine (${game.level.name})`;
  return {
    id: game.id,
    source: 'play',
    white: game.color === 'w' ? 'You' : engine,
    black: game.color === 'b' ? 'You' : engine,
    result,
    userColor: game.color,
    date: new Date(game.at).toISOString().slice(0, 10),
    moves: game.moves.slice(0, PLAY_GAME_PLIES),
  };
}

/** The games that were imported, leaving out the ones played here. */
export function importedOnly(games: ImportedGame[]): ImportedGame[] {
  return games.filter((game) => game.source !== 'play');
}

/** The games played here, newest first. */
export function playGames(games: ImportedGame[]): ImportedGame[] {
  return games.filter((game) => game.source === 'play');
}

/**
 * Add a Play game to the games, or replace it when the same game is recorded
 * again — a take-back after a resignation ends the same game twice. Play
 * games sit newest first ahead of the imports, and only the newest
 * `PLAY_GAMES_CAP` are kept.
 */
export function withPlayGame(games: ImportedGame[], game: ImportedGame): ImportedGame[] {
  const played = [game, ...playGames(games).filter((g) => g.id !== game.id)].slice(0, PLAY_GAMES_CAP);
  return [...played, ...importedOnly(games)];
}

/**
 * Games from two devices: the imports this device has, and the Play games
 * of both. Imports are not synced, so the local ones are the only ones;
 * Play games are, so the two sets are merged by id, newest first.
 */
export function mergeGames(local: ImportedGame[], remote: ImportedGame[]): ImportedGame[] {
  const seen = new Set<string>();
  const played = [...playGames(local), ...playGames(remote)]
    .filter((game) => (seen.has(game.id) ? false : (seen.add(game.id), true)))
    .sort((a, b) => (b.date ?? '').localeCompare(a.date ?? ''))
    .slice(0, PLAY_GAMES_CAP);
  return [...played, ...importedOnly(local)];
}
