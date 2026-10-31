import { fenTurn, positionKey, walkSan, type Color } from '../chess/core';
import { playerOf } from './onboarding';

/**
 * Starter sets: a ready-made Playbook for a new player, by style.
 *
 * A set answers the three questions every first run asks: what you play as
 * White, and what you play as Black against 1.e4 and against 1.d4. Each slot
 * is one or more openings from the book, named by the move order the book
 * names them at.
 *
 * Each opening goes in as exactly its own moves and nothing past them: a
 * new player is never tested on a move they have not seen. Runs carry on
 * past the prep in the book phase, and the end screen's offer to grow the
 * line is how the rest comes in, one move you choose at a time.
 */

export type SetSlot = 'w' | 'e4' | 'd4';

export interface StarterOpening {
  /** The book's move order for it, which is also its id in the opening tree. */
  id: string;
  /** What the set calls it, where the book's name is not what a beginner should read. */
  label?: string;
}

export interface StarterSet {
  id: string;
  name: string;
  description: string;
  slots: Record<SetSlot, StarterOpening[]>;
}

export const SLOT_LABELS: Record<SetSlot, string> = {
  w: 'As White',
  e4: 'Against 1.e4',
  d4: 'Against 1.d4',
};

export const SLOT_COLOR: Record<SetSlot, Color> = { w: 'w', e4: 'b', d4: 'b' };

export const STARTER_SETS: StarterSet[] = [
  {
    id: 'classical',
    name: 'Classical',
    description: 'Grab the center, develop, castle. Where most coaches start.',
    slots: {
      w: [{ id: 'e4 e5 Nf3 Nc6 Bc4' }],
      e4: [{ id: 'e4 e5', label: '1...e5' }],
      d4: [{ id: 'd4 d5 c4 e6' }],
    },
  },
  {
    id: 'system',
    name: 'System',
    description: "The same setup nearly every game, so there's little to memorize.",
    slots: {
      w: [{ id: 'd4 d5 Bf4', label: 'London System' }, { id: 'd4 Nf6 Bf4', label: 'London System' }],
      e4: [{ id: 'e4 c6' }],
      d4: [{ id: 'd4 d5 c4 c6' }],
    },
  },
  {
    id: 'solid',
    name: 'Solid',
    description: 'Hard to crack. Fewer early fights, more long games.',
    slots: {
      w: [{ id: 'd4 d5 c4' }],
      e4: [{ id: 'e4 e5', label: '1...e5' }, { id: 'e4 e5 Nf3 Nc6 Bb5 Nf6', label: 'Berlin' }],
      d4: [{ id: 'd4 Nf6 c4 e6 Nc3 Bb4' }],
    },
  },
  {
    id: 'aggressive',
    name: 'Aggressive',
    description: 'Unbalanced positions where you go after the king.',
    slots: {
      w: [{ id: 'e4 e5 Nf3 Nc6 d4 exd4' }],
      e4: [{ id: 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6', label: 'Sicilian Dragon' }],
      d4: [{ id: 'd4 Nf6 c4 g6 Nc3 d5' }],
    },
  },
  {
    id: 'fianchetto',
    name: 'Fianchetto',
    description: 'Bishops on the long diagonals, same setup whatever they play.',
    slots: {
      w: [{ id: 'Nf3 d5 g3' }, { id: 'Nf3 Nf6 g3 g6', label: "King's Indian Attack" }],
      e4: [{ id: 'e4 d6' }],
      d4: [{ id: 'd4 Nf6 c4 g6 Nc3' }],
    },
  },
  {
    id: 'mirror',
    name: 'Mirror',
    description: 'The c-pawn first with both colors, so White and Black share ideas.',
    slots: {
      w: [{ id: 'c4' }],
      e4: [{ id: 'e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 g6', label: 'Accelerated Dragon' }],
      d4: [{ id: 'd4 Nf6 c4 c5 d5 e6' }],
    },
  },
];

/** Every opening a set holds, with the side that plays it. */
export function setOpenings(set: StarterSet): { id: string; color: Color; slot: SetSlot; label?: string }[] {
  return (Object.keys(set.slots) as SetSlot[]).flatMap((slot) =>
    set.slots[slot].map((opening) => ({ ...opening, slot, color: SLOT_COLOR[slot] })),
  );
}

export interface SeedOpening {
  sans: string[];
  color: Color;
}

/** A line to add to a side's Playbook, from the start of the game. */
export type SeedLine = SeedOpening;

/** Whose an opening is, read from its move order — for openings picked one by one. */
export function seedFor(sans: string[], color?: Color): SeedOpening {
  return { sans, color: color ?? playerOf(sans) };
}

/** How many of your own moves a set of lines holds: one a position a side answers. */
export function countOwnMoves(lines: SeedLine[]): number {
  const own = new Set<string>();
  for (const line of lines) {
    const { fens } = walkSan(line.sans);
    line.sans.forEach((_, i) => {
      if (fenTurn(fens[i]) === line.color) own.add(`${line.color} ${positionKey(fens[i])}`);
    });
  }
  return own.size;
}
