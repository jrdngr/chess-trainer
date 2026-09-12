import type { EngineLine } from '../engine/types';

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
  /** What it plays like, in a few words. */
  blurb: string;
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
    blurb: 'Sees one move ahead and often takes the second-best. Good for trying a line out.',
    depth: 1,
    multiPv: 5,
    slip: 0.65,
  },
  {
    id: 'club',
    name: 'Club',
    blurb: 'Punishes a hanging piece and little else. A real game without much pressure.',
    depth: 5,
    multiPv: 4,
    slip: 0.3,
  },
  {
    id: 'strong',
    name: 'Strong',
    blurb: 'Plays the best move nearly always. Your opening has to be sound.',
    depth: 11,
    multiPv: 3,
    slip: 0.08,
  },
  {
    id: 'full',
    name: 'Full',
    blurb: 'No handicap at all. It will find everything you missed.',
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
