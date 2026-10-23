import { applySan, fenTurn, positionKey, walkSan, type Color } from '../chess/core';
import { playerOf } from './onboarding';
import { lookup, totalGamesAt, type ReferenceIndex } from './reference';

/**
 * Starter sets: a ready-made Playbook for a new player, by style.
 *
 * A set answers the three questions every first run asks: what you play as
 * White, and what you play as Black against 1.e4 and against 1.d4. Each slot
 * is one or more openings from the book, named by the move order the book
 * names them at.
 *
 * An opening's name alone is a stub: the Sicilian is 1.e4 c5 and nothing
 * more, and Autopilot plays the moves up to the name for you, so a run on a
 * stub has nothing to drill. So each opening goes in `SEED_DEPTH` of your own
 * moves past its name, against every reply strong players choose at least
 * `SEED_SHARE` of the time. Your move is the book's most played one, unless
 * the set says otherwise in `plays`, which keeps a set on one plan (the
 * Berlin against the Ruy Lopez, in Solid).
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
  /** Your move at a position, by a move order that reaches it: [move order, move]. */
  plays?: [string, string][];
}

/** Your own moves each opening goes in past its name. */
export const SEED_DEPTH = 3;
/** The replies a seeded opening answers: at least this share of the book's games. */
export const SEED_SHARE = 0.2;

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
    plays: [['e4 e5 Nf3 Nc6 Bb5', 'Nf6']],
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

export function starterSet(id: string): StarterSet | null {
  return STARTER_SETS.find((set) => set.id === id) ?? null;
}

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
export interface SeedLine {
  color: Color;
  sans: string[];
}

/**
 * The lines the openings put into the Playbook: each opening's own move
 * order, then `SEED_DEPTH` of your moves past it against every common reply.
 *
 * One move a position per side: a move an earlier opening (or `plays`)
 * already chose there is the move every later one plays too, so two
 * openings never leave two answers at the same position. The openings' own
 * move orders choose first, since they are what was asked for.
 */
export function seedLines(
  index: ReferenceIndex,
  openings: SeedOpening[],
  plays: [string, string][] = [],
): SeedLine[] {
  const chosen: Record<Color, Map<string, string>> = { w: new Map(), b: new Map() };
  const choose = (color: Color, fen: string, san: string) => {
    const key = positionKey(fen);
    if (!chosen[color].has(key)) chosen[color].set(key, san);
  };

  // Only what the board can play: a move order that is not legal is not an opening.
  const valid = openings.filter(({ sans }) => walkSan(sans).fens.length === sans.length + 1);
  for (const { sans, color } of valid) {
    const { fens } = walkSan(sans);
    sans.forEach((san, i) => fenTurn(fens[i]) === color && choose(color, fens[i], san));
  }
  for (const [order, san] of plays) {
    const { fens } = walkSan(order.split(' '));
    const fen = fens[fens.length - 1];
    choose(fenTurn(fen), fen, san);
  }

  const lines: SeedLine[] = [];
  for (const { sans, color } of valid) {
    const { fens } = walkSan(sans);
    const seen = new Set<string>();
    const grow = (fen: string, path: string[], own: number) => {
      const key = positionKey(fen);
      if (own >= SEED_DEPTH || seen.has(key)) return lines.push({ color, sans: path });
      seen.add(key);
      const entry = lookup(index, fen);
      const total = totalGamesAt(entry);
      if (!entry || total <= 0) return lines.push({ color, sans: path });

      if (fenTurn(fen) === color) {
        const top = [...entry.moves].sort((a, b) => b.games - a.games)[0];
        const san = chosen[color].get(key) ?? top?.san;
        const next = san ? applySan(fen, san) : null;
        if (!san || !next) return lines.push({ color, sans: path });
        choose(color, fen, san);
        return grow(next.after, [...path, san], own + 1);
      }

      const replies = entry.moves.filter((move) => move.games / total >= SEED_SHARE);
      let went = false;
      for (const reply of replies) {
        const next = applySan(fen, reply.san);
        if (!next) continue;
        went = true;
        grow(next.after, [...path, reply.san], own);
      }
      if (!went) lines.push({ color, sans: path });
    };
    grow(fens[fens.length - 1], sans, 0);
  }
  return lines;
}

/** The openings of a set as `seedLines` takes them. */
export function setSeed(set: StarterSet): SeedOpening[] {
  return setOpenings(set).map(({ id, color }) => ({ sans: id.split(' '), color }));
}

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
