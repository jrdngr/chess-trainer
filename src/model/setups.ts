import type { Color } from '../chess/core';

/**
 * Setups: plans that are several moves, with names players use.
 *
 * A habit is one exact move, but a player thinks in plans: g3 means a
 * fianchetto, and so does Bg2. Counted move by move, a line that has played
 * g3 but not yet Bg2 only half shows the plan, and a fianchetto on move four
 * looks unrelated to one on move seven.
 *
 * Like the kin sets, this is chess knowledge written down rather than worked
 * out. Moves every opening plays (Nf3, d4, O-O) are in no setup, so they
 * cannot make two unrelated setups look alike. Moves are written as
 * `sameMove` writes them: no check or capture marks.
 */
export interface Setup {
  id: string;
  color: Color;
  /** How a reason says you use it: "You fianchetto in 3 Slav lines". */
  doing: string;
  /** Every move of the setup. */
  moves: string[];
  /** The moves a line has to play to be using the setup. */
  core: string[];
  /**
   * The moves that make it this setup rather than a common move: one of the
   * setup's moves only counts toward it once the line has these. e3 is the
   * London only beside Bf4.
   */
  sign: string[];
}

export const SETUPS: Setup[] = [
  { id: 'w-kingside-fianchetto', color: 'w', doing: 'fianchetto', moves: ['g3', 'Bg2'], core: ['g3'], sign: ['g3'] },
  { id: 'w-queenside-fianchetto', color: 'w', doing: 'fianchetto queenside', moves: ['b3', 'Bb2'], core: ['b3'], sign: ['b3'] },
  { id: 'w-london', color: 'w', doing: 'play the London setup', moves: ['Bf4', 'e3', 'c3'], core: ['Bf4', 'e3'], sign: ['Bf4'] },
  { id: 'w-colle', color: 'w', doing: 'play the Colle setup', moves: ['e3', 'Bd3', 'c3'], core: ['e3', 'Bd3', 'c3'], sign: ['c3'] },
  { id: 'w-stonewall', color: 'w', doing: 'play the Stonewall', moves: ['f4', 'e3', 'c3'], core: ['f4', 'e3'], sign: ['f4'] },
  { id: 'w-kia', color: 'w', doing: "play the King's Indian Attack", moves: ['g3', 'Bg2', 'd3'], core: ['g3', 'd3'], sign: ['g3', 'd3'] },

  { id: 'b-kingside-fianchetto', color: 'b', doing: 'fianchetto', moves: ['g6', 'Bg7'], core: ['g6'], sign: ['g6'] },
  { id: 'b-queenside-fianchetto', color: 'b', doing: 'fianchetto queenside', moves: ['b6', 'Bb7'], core: ['b6'], sign: ['b6'] },
  { id: 'b-kid', color: 'b', doing: "play the King's Indian setup", moves: ['g6', 'Bg7', 'd6'], core: ['g6', 'd6'], sign: ['g6', 'd6'] },
  { id: 'b-stonewall', color: 'b', doing: 'play the Stonewall', moves: ['f5', 'e6', 'd5', 'c6'], core: ['f5', 'e6', 'd5'], sign: ['f5'] },
  { id: 'b-slav', color: 'b', doing: 'play the Slav setup', moves: ['c6', 'd5', 'Bf5'], core: ['c6', 'd5', 'Bf5'], sign: ['c6', 'd5'] },
  { id: 'b-hedgehog', color: 'b', doing: 'play the Hedgehog', moves: ['b6', 'Bb7', 'e6', 'd6', 'a6'], core: ['b6', 'e6', 'd6'], sign: ['b6', 'd6'] },
];

/** Whether a line with these moves of yours (as `sameMove` writes them) is using a setup. */
export function usesSetup(setup: Setup, moves: ReadonlySet<string>): boolean {
  return setup.core.every((move) => moves.has(move));
}

/** Whether a move of the setup, added to these, counts toward it: the line has its sign. */
export function signsSetup(setup: Setup, moves: ReadonlySet<string>, move: string): boolean {
  return setup.moves.includes(move) && setup.sign.every((sign) => sign === move || moves.has(sign));
}

const byMove = new Map<string, Setup[]>();
for (const setup of SETUPS) {
  for (const move of setup.moves) {
    const key = `${setup.color}|${move}`;
    byMove.set(key, [...(byMove.get(key) ?? []), setup]);
  }
}

/** The setups a move (as `sameMove` writes it) belongs to, for a side. */
export function setupsWith(color: Color, move: string): Setup[] {
  return byMove.get(`${color}|${move}`) ?? [];
}

export function setupsFor(color: Color): Setup[] {
  return SETUPS.filter((setup) => setup.color === color);
}
