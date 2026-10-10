import { piecesFromFen, squareToCoords, type Color, type PieceType, type Square } from '../chess/core';

/**
 * Named pawn structures and the plans that go with them.
 *
 * A structure is recognized from the pawns alone, and most are lopsided: one
 * side (`a`) owns the isolated pawn, the chain, the bind. Each template gives
 * a few plain-words plans for each side, written as if `a` were White; when
 * `a` is Black every square is mirrored. In the text, `{c5}` is a move by the
 * side the step is for and `<c5>` one by its opponent, so each can take
 * Black's "..." once the colors are known. A plan step can name a pawn break or
 * a piece and the square it wants, which the plan card turns into arrows from
 * wherever those pieces stand.
 *
 * These are rules of thumb, the kind a coach says before a game, not engine
 * lines: where the engine disagrees in a given position, the engine is right.
 */

export interface PlanStep {
  text: string;
  /** A pawn push or a piece heading for a square, drawn from the current position. */
  goal?: { piece: PieceType; to: Square };
}

export interface StructureTemplate {
  id: string;
  name: string;
  /** Named for one side, as in "Isolated queen pawn (White)". */
  sided?: boolean;
  /** Plans for the side the structure is named after, then for its opponent. */
  a: PlanStep[];
  b: PlanStep[];
}

export interface Structure {
  template: StructureTemplate;
  /** Which color is side `a`. */
  a: Color;
}

const FILES = 'abcdefgh';

interface Pawns {
  /** A pawn of this color on this file, on this rank counted from its own side (1..8). */
  has: (color: Color, file: string, relRank: number) => boolean;
  none: (color: Color, file: string) => boolean;
}

function pawnsOf(fen: string): Pawns {
  const pawns = piecesFromFen(fen)
    .filter((p) => p.type === 'p')
    .map((p) => ({ color: p.color, ...squareToCoords(p.square) }));
  return {
    has: (color, file, relRank) =>
      pawns.some(
        (p) => p.color === color && p.file === FILES.indexOf(file) && p.rank === (color === 'w' ? relRank - 1 : 8 - relRank),
      ),
    none: (color, file) => !pawns.some((p) => p.color === color && p.file === FILES.indexOf(file)),
  };
}

const step = (text: string, piece?: PieceType, to?: Square): PlanStep =>
  piece && to ? { text, goal: { piece, to } } : { text };

/**
 * The templates, most specific first: the first whose test passes names the
 * position. `test(p, a, b)` is asked with each color in turn as `a`.
 */
const TEMPLATES: { template: StructureTemplate; test: (p: Pawns, a: Color, b: Color) => boolean }[] = [
  {
    test: (p, a) => p.has(a, 'c', 3) && p.has(a, 'd', 4) && p.has(a, 'e', 3) && p.has(a, 'f', 4),
    template: {
      id: 'stonewall',
      sided: true,
      name: 'Stonewall',
      a: [
        step('Plant a knight on e5, the square the wall was built for', 'n', 'e5'),
        step('Attack the king: rook lift to the third rank, or {g4–g5}', 'p', 'g4'),
        step('Keep the light-squared bishop pointed at the king'),
      ],
      b: [
        step('Use the hole on e4: a knight lands there for good', 'n', 'e4'),
        step('Trade the dark-squared bishops: the wall leaves those squares weak'),
        step('Break with {c5} to open the queenside', 'p', 'c5'),
      ],
    },
  },
  {
    test: (p, a, b) => p.has(a, 'd', 4) && p.none(a, 'c') && p.has(b, 'd', 4) && p.has(b, 'c', 3) && p.none(b, 'e'),
    template: {
      id: 'carlsbad',
      name: 'Carlsbad',
      a: [
        step('Minority attack: {b4–b5} to hit c6 and leave a weak pawn', 'p', 'b5'),
        step('Or play in the center with {f3} and {e4}'),
        step('A knight on e5 supports either plan', 'n', 'e5'),
      ],
      b: [
        step('Play on the kingside: {Ne4} and {f5}', 'n', 'e4'),
        step('Meet <b5> by taking or by {c5} at the right moment'),
        step('Trade the light-squared bishop that has no good square'),
      ],
    },
  },
  {
    test: (p, a, b) => p.has(a, 'd', 4) && p.has(a, 'e', 5) && p.has(b, 'd', 4) && p.has(b, 'e', 3),
    template: {
      id: 'french-chain',
      name: 'French chain',
      a: [
        step('Hold d4: it is the base of the chain', 'n', 'f3'),
        step('Use the kingside space: {f4–f5} to attack', 'p', 'f5'),
        step('Keep the dark-squared bishop; it guards the holes'),
      ],
      b: [
        step('Hit the base with {c5}', 'p', 'c5'),
        step('Then hit the head with {f6}', 'p', 'f6'),
        step('Trade off or free the light-squared bishop, the bad one'),
      ],
    },
  },
  {
    test: (p, a, b) => p.has(a, 'd', 4) && p.has(a, 'e', 5) && p.has(b, 'c', 3) && p.has(b, 'd', 4) && !p.has(b, 'e', 3),
    template: {
      id: 'caro-advance',
      name: 'Caro-Kann Advance',
      a: [
        step('Use the kingside space; chase the bishop with {g4} or {h4}'),
        step('Keep d4 solid against <c5>'),
        step('Knight to f4 or e5 when it fits', 'n', 'f4'),
      ],
      b: [
        step('Get the light-squared bishop out before {e6}'),
        step('Hit d4 with {c5}', 'p', 'c5'),
        step('Then {e6} and pressure on d4 with the knights'),
      ],
    },
  },
  {
    test: (p, a, b) => p.has(a, 'c', 4) && p.has(a, 'd', 5) && p.has(a, 'e', 4) && p.has(b, 'c', 4) && p.has(b, 'd', 3) && p.has(b, 'e', 4),
    template: {
      id: 'czech-benoni',
      name: 'Czech Benoni',
      a: [
        step('Queenside: {a3} and {b4} to open lines', 'p', 'b4'),
        step('Kingside space with {g3} and {f4}'),
        step('Knight to b5 or d3', 'n', 'd3'),
      ],
      b: [
        step('Break with {f5}', 'p', 'f5'),
        step('Knight to f4 if it can stay', 'n', 'f4'),
        step('Keep the queenside shut with {a6} and {b6}'),
      ],
    },
  },
  {
    test: (p, a, b) => p.has(a, 'd', 5) && p.has(a, 'e', 4) && p.has(b, 'd', 3) && p.has(b, 'e', 4),
    template: {
      id: 'kid-chain',
      name: "King's Indian chain",
      a: [
        step('Attack on the queenside: {c4–c5} to break', 'p', 'c5'),
        step('Knights toward c5 via d3 or b3', 'n', 'd3'),
        step('Answer <f5> calmly; keep the king safe first'),
      ],
      b: [
        step('Storm the kingside: {f5}, {f4}, then {g5}', 'p', 'f5'),
        step('Bring the knight round via {Ne8} or {Nh5}', 'n', 'e8'),
        step('Race: your attack must land before theirs on the queenside'),
      ],
    },
  },
  {
    test: (p, a, b) => p.has(a, 'd', 5) && p.none(a, 'c') && p.has(b, 'c', 4) && p.has(b, 'd', 3) && p.none(b, 'e'),
    template: {
      id: 'benoni',
      name: 'Benoni',
      a: [
        step('Push {e4–e5} when it can be supported', 'p', 'e5'),
        step('Knight to c4, hitting d6', 'n', 'c4'),
        step('Stop <b5> with {a4}'),
      ],
      b: [
        step('Queenside majority: {b5}', 'p', 'b5'),
        step('Knight to e5, the outpost', 'n', 'e5'),
        step('The long-diagonal bishop is your best piece; keep it'),
      ],
    },
  },
  {
    test: (p, a, b) =>
      p.has(a, 'c', 4) && p.has(a, 'e', 4) && p.none(a, 'd') && p.none(b, 'c') && p.has(b, 'd', 3) && p.has(b, 'b', 3) && p.has(b, 'e', 3),
    template: {
      id: 'hedgehog',
      name: 'Hedgehog',
      a: [
        step('Keep the space; stop <b5> and <d5> before anything else'),
        step('Knight to d5 only when it cannot be taken', 'n', 'd5'),
        step('Kingside expansion with {g4–g5} can work'),
      ],
      b: [
        step('Wait behind the pawns, pieces ready'),
        step('Break with {b5} or {d5} at the right moment', 'p', 'd5'),
        step('A knight on e5 or c5 hits the pawns', 'n', 'e5'),
      ],
    },
  },
  {
    test: (p, a) => p.has(a, 'c', 4) && p.has(a, 'd', 3) && p.has(a, 'e', 4),
    template: {
      id: 'botvinnik',
      name: 'Botvinnik setup',
      a: [
        step('Knight to d5, held by c4 and e4', 'n', 'd5'),
        step('Kingside: {f4–f5} when ready', 'p', 'f5'),
        step('Keep the long-diagonal bishop'),
      ],
      b: [
        step('Hit the hole on d4', 'n', 'd4'),
        step('Break with {b5} or {f5}', 'p', 'f5'),
        step('Trade the knight that wants d5'),
      ],
    },
  },
  {
    test: (p, a, b) => p.has(a, 'c', 4) && p.has(a, 'e', 4) && p.none(a, 'd') && p.none(b, 'c') && p.has(b, 'd', 3),
    template: {
      id: 'maroczy',
      name: 'Maróczy bind',
      a: [
        step('Squeeze: keep c4 and e4, knight on d5', 'n', 'd5'),
        step('Expand on the queenside with {b4} and {c5}'),
        step('Avoid trades: the side with less space wants them'),
      ],
      b: [
        step('Trade pieces to ease the cramp'),
        step('Break with {b5} or {f5}', 'p', 'b5'),
        step('Dark squares are yours: c5 and e5', 'n', 'c5'),
      ],
    },
  },
  {
    test: (p, a, b) => p.none(a, 'd') && p.has(a, 'e', 4) && p.none(b, 'c') && p.has(b, 'd', 3) && p.has(b, 'g', 3),
    template: {
      id: 'dragon',
      name: 'Dragon',
      a: [
        step('Open the h-file: {h4–h5} and trade the dark-squared bishop', 'p', 'h5'),
        step('Castle long and race'),
        step('Knight to d5 trades a key defender', 'n', 'd5'),
      ],
      b: [
        step('Rook to c8 and the c-file; {Rxc3} is a common sacrifice'),
        step('Knight to c4 or e5', 'n', 'c4'),
        step('Push {b5} to open lines on their king'),
      ],
    },
  },
  {
    test: (p, a, b) => p.none(a, 'd') && p.has(a, 'e', 4) && p.none(b, 'c') && p.has(b, 'd', 3) && p.has(b, 'e', 3),
    template: {
      id: 'scheveningen',
      name: 'Scheveningen',
      a: [
        step('Kingside pawn storm: {g4–g5} against the knight', 'p', 'g4'),
        step('Keep pressure on d6'),
        step('Watch for <d5> and <e5> breaks'),
      ],
      b: [
        step('Break in the center with {d5} or {e5}', 'p', 'd5'),
        step('Queenside counterplay: {b5} and the c-file', 'p', 'b5'),
        step('Keep d6 defended'),
      ],
    },
  },
  {
    test: (p, a, b) => p.none(a, 'd') && p.has(a, 'e', 4) && p.none(b, 'c') && p.has(b, 'd', 3) && p.has(b, 'e', 4),
    template: {
      id: 'sicilian-e5',
      name: 'Sicilian ...e5 (d5 hole)',
      a: [
        step('Knight to d5, the hole', 'n', 'd5'),
        step('Trade the knight that guards d5'),
        step('Queenside space with {a4} or {c4}'),
      ],
      b: [
        step('Free your game with {d5}', 'p', 'd5'),
        step('Guard d5 with pieces until you can'),
        step('Kingside space with {f5} sometimes', 'p', 'f5'),
      ],
    },
  },
  {
    test: (p, a) => p.has(a, 'c', 4) && p.has(a, 'd', 4) && p.none(a, 'b') && p.none(a, 'e'),
    template: {
      id: 'hanging-pawns',
      sided: true,
      name: 'Hanging pawns',
      a: [
        step('Push {c5} or {d5} at the right moment to free your pieces', 'p', 'd5'),
        step('Keep the pawns side by side; use the half-open files'),
        step('Rooks behind the pawns'),
      ],
      b: [
        step('Pressure c4 and d4 with your pieces'),
        step('Make one advance, then blockade the square in front'),
        step('Trades help you: the pawns grow weaker as pieces come off'),
      ],
    },
  },
  {
    test: (p, a) => !p.none(a, 'd') && p.none(a, 'c') && p.none(a, 'e'),
    template: {
      id: 'iqp',
      sided: true,
      name: 'Isolated queen pawn',
      a: [
        step('Attack: pieces at the king, knight to e5', 'n', 'e5'),
        step('Push {d4–d5} to open lines when it works', 'p', 'd5'),
        step('Avoid trades: the endgame favors the other side'),
      ],
      b: [
        step('Blockade d5 with a knight', 'n', 'd5'),
        step('Trade pieces: the pawn gets weaker as they come off'),
        step('Pressure d4 with rooks on the d-file'),
      ],
    },
  },
  {
    test: (p, a, b) => p.has(a, 'd', 4) && p.has(a, 'e', 4) && p.none(b, 'd') && !p.has(b, 'e', 4),
    template: {
      id: 'big-center',
      name: 'Big center',
      a: [
        step('Support the center; push {d5} or {e5} when it gains space', 'p', 'd5'),
        step('Develop behind the pawns'),
        step('Do not let the center be undermined by <c5>'),
      ],
      b: [
        step('Hit the center: {c5}, and the long-diagonal bishop', 'p', 'c5'),
        step('Pressure d4 with knights'),
        step('Provoke an advance, then blockade'),
      ],
    },
  },
  {
    test: (p, a, b) => p.has(a, 'd', 4) && p.has(a, 'e', 4) && p.has(b, 'd', 3) && p.has(b, 'e', 4),
    template: {
      id: 'central-tension',
      name: 'Central tension',
      a: [
        step('Keep the tension; {d4–d5} closes the center for good', 'p', 'd5'),
        step('Knight route to f5 via d2 and f1', 'n', 'f5'),
        step('Queenside space with {a4} or {c4}'),
      ],
      b: [
        step('Hold e5; {exd4} gives up the center for activity'),
        step('Kingside: {f5} if the center closes', 'p', 'f5'),
        step('Knight to f4 if you get there', 'n', 'f4'),
      ],
    },
  },
  {
    test: (p, a, b) => p.has(a, 'd', 4) && p.has(b, 'd', 4) && p.none(a, 'e') && p.none(b, 'e'),
    template: {
      id: 'symmetrical',
      name: 'Symmetrical center',
      a: [
        step('Outposts on e5 and e4 are the fight', 'n', 'e5'),
        step('The open e-file: rooks there first'),
        step('A minority attack or {c4} break makes the imbalance', 'p', 'c4'),
      ],
      b: [
        step('Same fight from the other side: e4 for your knight', 'n', 'e4'),
        step('Rooks to the e-file'),
        step('{c5} breaks the symmetry', 'p', 'c5'),
      ],
    },
  },
  {
    test: (p) => p.none('w', 'd') && p.none('w', 'e') && p.none('b', 'd') && p.none('b', 'e'),
    template: {
      id: 'open-center',
      name: 'Open center',
      a: [
        step('Develop fast and get rooks to the open files'),
        step('Pieces beat pawns here: activity first'),
        step('Trade into an ending if your pawns are better'),
      ],
      b: [
        step('Develop fast and get rooks to the open files'),
        step('Pieces beat pawns here: activity first'),
        step('Trade into an ending if your pawns are better'),
      ],
    },
  },
];

export const STRUCTURE_TEMPLATES: StructureTemplate[] = TEMPLATES.map((t) => t.template);

/** The structure the pawns form, if they match a named one. */
export function structureOf(fen: string): Structure | null {
  const p = pawnsOf(fen);
  for (const { template, test } of TEMPLATES) {
    for (const a of ['w', 'b'] as Color[]) {
      if (test(p, a, a === 'w' ? 'b' : 'w')) return { template, a };
    }
  }
  return null;
}

/** The structure's name as the Pawns lens shows it. */
export function structureLabel(structure: Structure): string {
  const { name, sided } = structure.template;
  return sided ? `${name} (${structure.a === 'w' ? 'White' : 'Black'})` : name;
}

/** A template square as it stands on the board: mirrored when side `a` is Black. */
export function placeSquare(square: Square, a: Color): Square {
  if (a === 'w') return square;
  return `${square[0]}${9 - Number(square[1])}` as Square;
}

/** Your side's plan in a structure: `a`'s steps when you are `a`, else the other side's. */
export function planFor(structure: Structure, me: Color): PlanStep[] {
  const steps = structure.a === me ? structure.template.a : structure.template.b;
  return steps.map((s) => ({
    text: stepText(s.text, structure.a, me),
    ...(s.goal ? { goal: { ...s.goal, to: placeSquare(s.goal.to, structure.a) } } : {}),
  }));
}

/** A step's words for the board: squares mirrored when `a` is Black, Black's moves given their "...". */
export function stepText(text: string, a: Color, me: Color): string {
  const placed = a === 'w' ? text : text.replace(/([a-h])([1-8])/g, (_, f: string, r: string) => `${f}${9 - Number(r)}`);
  return placed
    .replace(/\{([^}]+)\}/g, (_, move: string) => (me === 'b' ? `...${move}` : move))
    .replace(/<([^>]+)>/g, (_, move: string) => (me === 'w' ? `...${move}` : move));
}
