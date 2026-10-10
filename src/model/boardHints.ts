import {
  coordsToSquare,
  legalMoves,
  piecesFromFen,
  PIECE_VALUES,
  squareToCoords,
  type Color,
  type PieceType,
  type Square,
} from '../chess/core';

/**
 * Reading a middlegame position for the lenses: the pawns, the pieces, who
 * controls which squares, the kings, and what is hanging.
 *
 * Everything here is counted from the board alone, with no engine: attacks are
 * worked out square by square, the way you would count them yourself. That
 * keeps a lens instant to show, and every mark is something you can check by
 * looking. The one thing the engine adds — which pawn break is worth playing —
 * is asked for separately (see `engine/pawnBreaks.ts`).
 *
 * Colors are "mine" and "theirs" from the side you play, never white and black.
 */

export type LensKind = 'pawns' | 'pieces' | 'space' | 'kings' | 'threats';

export const LENSES: { kind: LensKind; label: string }[] = [
  { kind: 'pawns', label: 'Pawns' },
  { kind: 'pieces', label: 'Pieces' },
  { kind: 'space', label: 'Space' },
  { kind: 'kings', label: 'Kings' },
  { kind: 'threats', label: 'Threats' },
];

export type TintColor = 'blue' | 'red' | 'purple' | 'purple-blue' | 'purple-red' | 'green' | 'amber';
export type KingGrade = 'safe' | 'exposed' | 'attacked';
export type Side = 'mine' | 'theirs';

/** What a lens draws. Every field is optional: a lens fills in what it shows. */
export interface LensMarks {
  /** Fade every piece but the pawns. */
  ghost?: boolean;
  tints?: { square: Square; color: TintColor; strength: 1 | 2 | 3 }[];
  /** A small tag on a pawn: weak (bad) or passed (good). */
  tags?: { square: Square; tone: 'good' | 'bad' }[];
  /** Holes: squares no pawn of their owner can ever guard again. */
  dots?: Square[];
  rings?: { square: Square; tone: 'bad' | 'warn' | Side }[];
  stars?: { square: Square; side: Side }[];
  /** Squares outlined as a king's zone. */
  zone?: Square[];
  pips?: { square: Square; attackers: number; defenders: number }[];
  shields?: { square: Square; grade: KingGrade }[];
  /** Where a shield pawn is missing in front of a king. */
  emptyPawns?: Square[];
  /** Faint lines, no arrowhead: open files and diagonals toward a king. */
  lines?: { from: Square; to: Square }[];
  arrows?: { from: Square; to: Square; tone: Side | 'route' | 'threat' }[];
  /** One line of what the lens found, shown over the board. */
  caption?: string;
}

/* ── the board as a grid ───────────────────────────────────────────────── */

interface Man {
  square: Square;
  type: PieceType;
  color: Color;
  file: number;
  rank: number;
}

interface Grid {
  men: Man[];
  at: (file: number, rank: number) => Man | null | undefined;
}

function gridOf(fen: string): Grid {
  const cells: (Man | null)[] = new Array(64).fill(null);
  const men: Man[] = [];
  for (const piece of piecesFromFen(fen)) {
    const { file, rank } = squareToCoords(piece.square);
    const man = { ...piece, file, rank };
    cells[rank * 8 + file] = man;
    men.push(man);
  }
  return {
    men,
    at: (file, rank) => (file < 0 || file > 7 || rank < 0 || rank > 7 ? undefined : cells[rank * 8 + file]),
  };
}

const other = (color: Color): Color => (color === 'w' ? 'b' : 'w');
/** A rank counted from a side's own back rank, 0..7. */
const rel = (color: Color, rank: number) => (color === 'w' ? rank : 7 - rank);
const forward = (color: Color) => (color === 'w' ? 1 : -1);
const sq = (file: number, rank: number) => coordsToSquare(file, rank);

const KNIGHT = [[1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]];
const KING = [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]];
const DIAG = [[1, 1], [1, -1], [-1, 1], [-1, -1]];
const ORTHO = [[1, 0], [-1, 0], [0, 1], [0, -1]];

/**
 * Every square a man attacks, a blocked line stopping on the blocker. With
 * `xray`, a line runs on through a piece of the same side that moves along
 * it, so two rooks doubled on a file both count on the squares ahead.
 */
function attacksOf(grid: Grid, man: Man, xray = false): { file: number; rank: number }[] {
  const out: { file: number; rank: number }[] = [];
  const step = (df: number, dr: number) => {
    const f = man.file + df;
    const r = man.rank + dr;
    if (f >= 0 && f < 8 && r >= 0 && r < 8) out.push({ file: f, rank: r });
  };
  const ride = (dirs: number[][]) => {
    for (const [df, dr] of dirs) {
      const diagonal = df !== 0 && dr !== 0;
      let f = man.file + df;
      let r = man.rank + dr;
      while (f >= 0 && f < 8 && r >= 0 && r < 8) {
        out.push({ file: f, rank: r });
        const there = grid.at(f, r);
        const along =
          xray &&
          !!there &&
          there.color === man.color &&
          (there.type === 'q' || there.type === (diagonal ? 'b' : 'r'));
        if (there && !along) break;
        f += df;
        r += dr;
      }
    }
  };
  switch (man.type) {
    case 'p':
      step(-1, forward(man.color));
      step(1, forward(man.color));
      break;
    case 'n':
      for (const [df, dr] of KNIGHT) step(df, dr);
      break;
    case 'k':
      for (const [df, dr] of KING) step(df, dr);
      break;
    case 'b':
      ride(DIAG);
      break;
    case 'r':
      ride(ORTHO);
      break;
    case 'q':
      ride(DIAG);
      ride(ORTHO);
      break;
  }
  return out;
}

/** Who attacks each square: index rank * 8 + file. */
function attackMap(grid: Grid): Man[][] {
  const map: Man[][] = Array.from({ length: 64 }, () => []);
  for (const man of grid.men) {
    for (const { file, rank } of attacksOf(grid, man, true)) map[rank * 8 + file].push(man);
  }
  return map;
}

const by = (list: Man[], color: Color) => list.filter((man) => man.color === color);
const cheapest = (list: Man[]) => Math.min(...list.map((man) => (man.type === 'k' ? 100 : PIECE_VALUES[man.type])));

/* ── pawns ─────────────────────────────────────────────────────────────── */

export interface PawnInfo {
  square: Square;
  color: Color;
  isolated: boolean;
  doubled: boolean;
  backward: boolean;
  passed: boolean;
}

function pawnsOf(grid: Grid, color: Color): Man[] {
  return grid.men.filter((man) => man.type === 'p' && man.color === color);
}

export function pawnFeatures(fen: string): PawnInfo[] {
  const grid = gridOf(fen);
  const out: PawnInfo[] = [];
  for (const color of ['w', 'b'] as Color[]) {
    const mine = pawnsOf(grid, color);
    const theirs = pawnsOf(grid, other(color));
    for (const pawn of mine) {
      const here = rel(color, pawn.rank);
      const neighbours = mine.filter((p) => Math.abs(p.file - pawn.file) === 1);
      const isolated = neighbours.length === 0;
      const doubled = mine.some((p) => p !== pawn && p.file === pawn.file);
      const passed = !theirs.some((p) => Math.abs(p.file - pawn.file) <= 1 && rel(color, p.rank) > here);
      // Every neighbour has gone past it, and an enemy pawn guards the square in front.
      const stop = { file: pawn.file, rank: pawn.rank + forward(color) };
      const stopGuarded = theirs.some(
        (p) => Math.abs(p.file - stop.file) === 1 && p.rank + forward(other(color)) === stop.rank,
      );
      const backward =
        !isolated && !passed && neighbours.every((p) => rel(color, p.rank) > here) && stopGuarded;
      out.push({ square: pawn.square, color, isolated, doubled, backward, passed });
    }
  }
  return out;
}

/**
 * Holes in one side's camp: squares on its third and fourth ranks, b to g
 * files, that none of its pawns can ever attack again, because every pawn
 * that could has moved past or gone.
 */
export function holes(fen: string, color: Color): Square[] {
  const grid = gridOf(fen);
  const mine = pawnsOf(grid, color);
  const out: Square[] = [];
  for (let file = 1; file <= 6; file += 1) {
    for (const r of [2, 3]) {
      const rank = color === 'w' ? r : 7 - r;
      const man = grid.at(file, rank);
      if (man && man.type === 'p' && man.color === color) continue;
      const guardable = mine.some((p) => Math.abs(p.file - file) === 1 && rel(color, p.rank) < r);
      if (!guardable) out.push(sq(file, rank));
    }
  }
  return out;
}

/** A named pawn structure, when the pawns match one. */
export function structureName(fen: string): string | null {
  const grid = gridOf(fen);
  const FILES = 'abcdefgh';
  /** A pawn of this color on this file, on this rank counted from its own side (1..8). */
  const has = (color: Color, file: string, relRank: number) => {
    const man = grid.at(FILES.indexOf(file), color === 'w' ? relRank - 1 : 8 - relRank);
    return !!man && man.type === 'p' && man.color === color;
  };
  const none = (color: Color, file: string) =>
    !pawnsOf(grid, color).some((p) => p.file === FILES.indexOf(file));
  const sideName = (color: Color) => (color === 'w' ? 'White' : 'Black');

  for (const a of ['w', 'b'] as Color[]) {
    const b = other(a);
    if (has(a, 'c', 3) && has(a, 'd', 4) && has(a, 'e', 3) && has(a, 'f', 4)) return `Stonewall (${sideName(a)})`;
    if (has(a, 'd', 4) && none(a, 'c') && has(b, 'd', 4) && has(b, 'c', 3) && none(b, 'e')) return 'Carlsbad';
    if (has(a, 'd', 4) && has(a, 'e', 5) && has(b, 'd', 4) && has(b, 'e', 3)) return 'French chain';
    if (has(a, 'd', 5) && has(a, 'e', 4) && has(b, 'd', 3) && has(b, 'e', 4)) return "King's Indian chain";
    if (has(a, 'd', 5) && none(a, 'c') && has(b, 'c', 4) && has(b, 'd', 3) && none(b, 'e')) return 'Benoni';
    if (has(a, 'c', 4) && has(a, 'e', 4) && none(a, 'd') && none(b, 'c') && has(b, 'd', 3)) {
      return has(b, 'b', 3) && has(b, 'e', 3) ? 'Hedgehog' : 'Maróczy bind';
    }
    if (none(a, 'd') && has(a, 'e', 4) && none(b, 'c') && has(b, 'd', 3) && has(b, 'e', 3)) return 'Scheveningen';
    if (none(a, 'd') && has(a, 'e', 4) && none(b, 'c') && has(b, 'd', 3) && has(b, 'e', 4)) return 'Sicilian ...e5 (d5 hole)';
    if ((has(a, 'c', 4) && has(a, 'd', 4)) && none(a, 'b') && none(a, 'e')) return `Hanging pawns (${sideName(a)})`;
    const isolatedD = pawnsOf(grid, a).some((p) => p.file === 3) && none(a, 'c') && none(a, 'e');
    if (isolatedD) return `Isolated queen pawn (${sideName(a)})`;
  }
  if (none('w', 'd') && none('w', 'e') && none('b', 'd') && none('b', 'e')) return 'Open center';
  return null;
}

/**
 * The same position with this side to move, for asking what it would play
 * here. Null when that cannot be a real position: the other side in check.
 */
export function asMover(fen: string, color: Color): string | null {
  const parts = fen.split(' ');
  if (parts[1] === color) return fen;
  const flipped = [parts[0], color, parts[2], '-', '0', parts[5] ?? '1'].join(' ');
  // With the turn handed over, the side that was to move must not be left in check.
  const grid = gridOf(flipped);
  const map = attackMap(grid);
  const king = grid.men.find((man) => man.type === 'k' && man.color === other(color));
  if (!king) return null;
  if (by(map[king.rank * 8 + king.file], color).length) return null;
  return flipped;
}

/**
 * The pawn moves that are breaks: a capture of a pawn, or a push that
 * attacks one. UCI, from a position with `color` to move.
 */
export function breakCandidates(fen: string, color: Color): string[] {
  const grid = gridOf(fen);
  return legalMoves(fen)
    .filter((move) => {
      const man = grid.at(squareToCoords(move.from).file, squareToCoords(move.from).rank);
      if (!man || man.type !== 'p' || man.color !== color) return false;
      const { file, rank } = squareToCoords(move.to);
      const victim = grid.at(file, rank);
      if (victim && victim.type === 'p') return true;
      const ahead = rank + forward(color);
      return [file - 1, file + 1].some((f) => {
        const target = grid.at(f, ahead);
        return !!target && target.type === 'p' && target.color !== color;
      });
    })
    .map((move) => `${move.from}${move.to}${move.promotion ?? ''}`);
}

export function pawnsLens(fen: string): LensMarks {
  const features = pawnFeatures(fen);
  const tags: NonNullable<LensMarks['tags']> = [];
  for (const pawn of features) {
    if (pawn.passed) tags.push({ square: pawn.square, tone: 'good' });
    else if (pawn.isolated || pawn.doubled || pawn.backward) tags.push({ square: pawn.square, tone: 'bad' });
  }
  return {
    ghost: true,
    tags,
    dots: [...holes(fen, 'w'), ...holes(fen, 'b')],
    caption: structureName(fen) ?? undefined,
  };
}

/* ── pieces ────────────────────────────────────────────────────────────── */

/** About how many safe squares a piece has when it is doing its job. */
const TYPICAL_MOBILITY: Partial<Record<PieceType, number>> = { n: 5, b: 6, r: 7, q: 13 };

export interface Activity {
  square: Square;
  color: Color;
  type: PieceType;
  /** Safe squares reached over what is typical for the piece: 1 is normal. */
  ratio: number;
}

/** How active each knight, bishop, rook and queen is. */
export function activity(fen: string): Activity[] {
  const grid = gridOf(fen);
  const out: Activity[] = [];
  const pawnAttacks = (color: Color) => {
    const set = new Set<number>();
    for (const pawn of pawnsOf(grid, color)) {
      for (const { file, rank } of attacksOf(grid, pawn)) set.add(rank * 8 + file);
    }
    return set;
  };
  const guardedBy = { w: pawnAttacks('w'), b: pawnAttacks('b') };
  for (const man of grid.men) {
    const typical = TYPICAL_MOBILITY[man.type];
    if (!typical) continue;
    const reach = attacksOf(grid, man).filter(({ file, rank }) => {
      const there = grid.at(file, rank);
      if (there && there.color === man.color) return false;
      return !guardedBy[other(man.color)].has(rank * 8 + file);
    }).length;
    out.push({ square: man.square, color: man.color, type: man.type, ratio: reach / typical });
  }
  return out;
}

/**
 * Outposts for one side: squares on its fourth to sixth ranks, b to g files,
 * that no enemy pawn can ever attack and one of its own pawns guards.
 */
export function outposts(fen: string, color: Color): Square[] {
  const grid = gridOf(fen);
  const theirs = pawnsOf(grid, other(color));
  const out: Square[] = [];
  for (let file = 1; file <= 6; file += 1) {
    for (const r of [3, 4, 5]) {
      const rank = color === 'w' ? r : 7 - r;
      const man = grid.at(file, rank);
      if (man && man.type === 'p') continue;
      const attackable = theirs.some((p) => Math.abs(p.file - file) === 1 && rel(color, p.rank) > r);
      if (attackable) continue;
      const guarded = pawnsOf(grid, color).some(
        (p) => Math.abs(p.file - file) === 1 && p.rank + forward(color) === rank,
      );
      if (guarded) out.push(sq(file, rank));
    }
  }
  return out;
}

/** The shortest knight route from one of your knights to a square, at most three hops. */
function knightRoute(grid: Grid, color: Color, target: Square): Square[] | null {
  const goal = squareToCoords(target);
  const knights = grid.men.filter((man) => man.type === 'n' && man.color === color);
  let best: Square[] | null = null;
  for (const knight of knights) {
    if (knight.file === goal.file && knight.rank === goal.rank) return null;
    const seen = new Map<number, number>();
    const start = knight.rank * 8 + knight.file;
    seen.set(start, -1);
    let frontier = [start];
    for (let hop = 0; hop < 3 && frontier.length; hop += 1) {
      const next: number[] = [];
      for (const at of frontier) {
        const f0 = at % 8;
        const r0 = Math.floor(at / 8);
        for (const [df, dr] of KNIGHT) {
          const f = f0 + df;
          const r = r0 + dr;
          const there = grid.at(f, r);
          if (there === undefined || (there && there.color === color)) continue;
          const key = r * 8 + f;
          if (seen.has(key)) continue;
          seen.set(key, at);
          next.push(key);
        }
      }
      const goalKey = goal.rank * 8 + goal.file;
      if (seen.has(goalKey)) {
        const path: Square[] = [];
        for (let k = goalKey; k !== -1; k = seen.get(k)!) path.unshift(sq(k % 8, Math.floor(k / 8)));
        if (!best || path.length < best.length) best = path;
        break;
      }
      frontier = next;
    }
  }
  return best;
}

export function piecesLens(fen: string, me: Color): LensMarks {
  const grid = gridOf(fen);
  const acts = activity(fen);
  const tints: NonNullable<LensMarks['tints']> = acts.map((a) => ({
    square: a.square,
    color: a.ratio >= 0.9 ? 'green' : a.ratio >= 0.45 ? 'amber' : 'red',
    strength: 2,
  }));
  const rings: NonNullable<LensMarks['rings']> = [];
  for (const color of ['w', 'b'] as Color[]) {
    const own = acts.filter((a) => a.color === color);
    if (!own.length) continue;
    const worst = own.reduce((low, a) => (a.ratio < low.ratio ? a : low));
    rings.push({ square: worst.square, tone: color === me ? 'mine' : 'theirs' });
  }
  const stars: NonNullable<LensMarks['stars']> = [];
  const arrows: NonNullable<LensMarks['arrows']> = [];
  for (const color of ['w', 'b'] as Color[]) {
    for (const square of outposts(fen, color)) {
      stars.push({ square, side: color === me ? 'mine' : 'theirs' });
    }
  }
  // Routes for your own knights only, to the two nearest outposts: more is clutter.
  const routes = outposts(fen, me)
    .map((square) => knightRoute(grid, me, square))
    .filter((path): path is Square[] => !!path && path.length > 1)
    .sort((a, b) => a.length - b.length)
    .slice(0, 2);
  for (const path of routes) {
    for (let i = 1; i < path.length; i += 1) arrows.push({ from: path[i - 1], to: path[i], tone: 'route' });
  }
  return { tints, rings, stars, arrows };
}

/* ── space ─────────────────────────────────────────────────────────────── */

export interface Control {
  square: Square;
  /** Who holds the square, from your side. */
  holder: Side | 'both' | null;
  /** Attackers over the other side's, 0 when even. */
  margin: number;
  /** In an even fight, whose cheaper piece wins it. */
  lean: Side | null;
}

export function control(fen: string, me: Color): Control[] {
  const grid = gridOf(fen);
  const map = attackMap(grid);
  const out: Control[] = [];
  for (let rank = 0; rank < 8; rank += 1) {
    for (let file = 0; file < 8; file += 1) {
      const all = map[rank * 8 + file];
      const mine = by(all, me);
      const theirs = by(all, other(me));
      const square = sq(file, rank);
      if (!mine.length && !theirs.length) {
        out.push({ square, holder: null, margin: 0, lean: null });
      } else if (mine.length !== theirs.length) {
        out.push({
          square,
          holder: mine.length > theirs.length ? 'mine' : 'theirs',
          margin: Math.abs(mine.length - theirs.length),
          lean: null,
        });
      } else {
        const a = cheapest(mine);
        const b = cheapest(theirs);
        out.push({ square, holder: 'both', margin: 0, lean: a < b ? 'mine' : b < a ? 'theirs' : null });
      }
    }
  }
  return out;
}

/** Squares each side holds outright in the other's half. */
export function spaceCount(fen: string, me: Color): { mine: number; theirs: number } {
  let mine = 0;
  let theirs = 0;
  for (const c of control(fen, me)) {
    const { rank } = squareToCoords(c.square);
    if (c.holder === 'mine' && rel(me, rank) >= 4) mine += 1;
    if (c.holder === 'theirs' && rel(other(me), rank) >= 4) theirs += 1;
  }
  return { mine, theirs };
}

export function spaceLens(fen: string, me: Color): LensMarks {
  const tints: NonNullable<LensMarks['tints']> = [];
  for (const c of control(fen, me)) {
    if (!c.holder) continue;
    if (c.holder === 'both') {
      tints.push({ square: c.square, color: c.lean === 'mine' ? 'purple-blue' : c.lean === 'theirs' ? 'purple-red' : 'purple', strength: 1 });
    } else {
      tints.push({
        square: c.square,
        color: c.holder === 'mine' ? 'blue' : 'red',
        strength: Math.min(3, c.margin) as 1 | 2 | 3,
      });
    }
  }
  const count = spaceCount(fen, me);
  return { tints, caption: `Space · you ${count.mine} – ${count.theirs} them` };
}

/* ── kings ─────────────────────────────────────────────────────────────── */

export interface KingReport {
  color: Color;
  square: Square;
  zone: Square[];
  pips: { square: Square; attackers: number; defenders: number }[];
  missingShield: Square[];
  lines: { from: Square; to: Square }[];
  score: number;
  grade: KingGrade;
}

export const KING_GRADE_TEXT: Record<KingGrade, string> = {
  safe: 'Safe',
  exposed: 'Exposed',
  attacked: 'Under attack',
};

export function kingReport(fen: string, color: Color): KingReport | null {
  const grid = gridOf(fen);
  const map = attackMap(grid);
  const king = grid.men.find((man) => man.type === 'k' && man.color === color);
  if (!king) return null;
  const enemy = other(color);
  const dir = forward(color);

  const zoneCells: { file: number; rank: number }[] = [];
  for (let df = -1; df <= 1; df += 1) {
    for (let dr = -1; dr <= 2; dr += 1) {
      // Two ranks out only in front of the king.
      const r = king.rank + dr * dir;
      const f = king.file + df;
      if (f < 0 || f > 7 || r < 0 || r > 7) continue;
      zoneCells.push({ file: f, rank: r });
    }
  }
  const pips: KingReport['pips'] = [];
  let attacks = 0;
  let defence = 0;
  for (const { file, rank } of zoneCells) {
    const here = map[rank * 8 + file];
    const attackers = by(here, enemy).length;
    const defenders = by(here, color).filter((man) => man.type !== 'k').length;
    attacks += attackers;
    defence += defenders;
    if (attackers) pips.push({ square: sq(file, rank), attackers, defenders });
  }

  const missingShield: Square[] = [];
  const pawns = pawnsOf(grid, color);
  if (rel(color, king.rank) <= 1) {
    for (let f = king.file - 1; f <= king.file + 1; f += 1) {
      if (f < 0 || f > 7) continue;
      const near = pawns.some(
        (p) => p.file === f && rel(color, p.rank) > rel(color, king.rank) && rel(color, p.rank) <= rel(color, king.rank) + 2,
      );
      if (!near) missingShield.push(sq(f, king.rank + dir));
    }
  }

  const lines: KingReport['lines'] = [];
  const heavy = grid.men.some((man) => man.color === enemy && (man.type === 'r' || man.type === 'q'));
  if (heavy) {
    for (let f = king.file - 1; f <= king.file + 1; f += 1) {
      if (f < 0 || f > 7) continue;
      const shut = pawns.some((p) => p.file === f && rel(color, p.rank) > rel(color, king.rank));
      if (!shut) lines.push({ from: sq(f, color === 'w' ? 7 : 0), to: sq(f, king.rank) });
    }
  }
  for (const [df, dr] of [[1, dir], [-1, dir]]) {
    let f = king.file + df;
    let r = king.rank + dr;
    while (f >= 0 && f < 8 && r >= 0 && r < 8) {
      const man = grid.at(f, r);
      if (man) {
        if (man.color === enemy && (man.type === 'b' || man.type === 'q')) lines.push({ from: man.square, to: king.square });
        break;
      }
      f += df;
      r += dr;
    }
  }

  const inCheck = by(map[king.rank * 8 + king.file], enemy).length > 0;
  const score = attacks + 2 * missingShield.length + 2 * lines.length - defence / 2;
  const grade: KingGrade = inCheck || score >= 7 ? 'attacked' : score >= 3 ? 'exposed' : 'safe';
  return {
    color,
    square: king.square,
    zone: zoneCells.map(({ file, rank }) => sq(file, rank)),
    pips,
    missingShield,
    lines,
    score,
    grade,
  };
}

export function kingsLens(fen: string, me: Color): LensMarks {
  const marks: LensMarks = { zone: [], pips: [], shields: [], emptyPawns: [], lines: [] };
  const grades: Partial<Record<Side, KingGrade>> = {};
  for (const color of ['w', 'b'] as Color[]) {
    const report = kingReport(fen, color);
    if (!report) continue;
    marks.zone!.push(...report.zone);
    marks.pips!.push(...report.pips);
    marks.shields!.push({ square: report.square, grade: report.grade });
    marks.emptyPawns!.push(...report.missingShield);
    marks.lines!.push(...report.lines);
    grades[color === me ? 'mine' : 'theirs'] = report.grade;
  }
  if (grades.mine && grades.theirs) {
    marks.caption = `You: ${KING_GRADE_TEXT[grades.mine]} · Them: ${KING_GRADE_TEXT[grades.theirs]}`;
  }
  return marks;
}

/* ── threats ───────────────────────────────────────────────────────────── */

export interface Loose {
  square: Square;
  color: Color;
  /** Attacked and undefended (or a king in check), or only attacked by something cheaper. */
  kind: 'hanging' | 'cheaper';
}

/** Every piece that is hanging, or attacked by something worth less. */
export function loosePieces(fen: string): Loose[] {
  const grid = gridOf(fen);
  const map = attackMap(grid);
  const out: Loose[] = [];
  for (const man of grid.men) {
    const here = map[man.rank * 8 + man.file];
    const attackers = by(here, other(man.color));
    if (!attackers.length) continue;
    if (man.type === 'k') {
      out.push({ square: man.square, color: man.color, kind: 'hanging' });
      continue;
    }
    const defenders = by(here, man.color);
    if (!defenders.length) out.push({ square: man.square, color: man.color, kind: 'hanging' });
    else if (cheapest(attackers) < PIECE_VALUES[man.type]) out.push({ square: man.square, color: man.color, kind: 'cheaper' });
  }
  return out;
}

/** Each attack (attacker → target) by one side on the other's men. */
function attackPairs(fen: string, attacker: Color): { from: Square; to: Square }[] {
  const grid = gridOf(fen);
  const out: { from: Square; to: Square }[] = [];
  for (const man of grid.men) {
    if (man.color !== attacker) continue;
    for (const { file, rank } of attacksOf(grid, man)) {
      const target = grid.at(file, rank);
      if (target && target.color !== attacker) out.push({ from: man.square, to: target.square });
    }
  }
  return out;
}

/**
 * What the opponent's last move newly threatens: attacks on your loose men
 * (or your king) that were not there before it.
 */
export function newThreats(prevFen: string, fen: string, me: Color): { from: Square; to: Square }[] {
  const loose = new Set(loosePieces(fen).filter((l) => l.color === me).map((l) => l.square));
  const before = new Set(attackPairs(prevFen, other(me)).map((p) => `${p.from}${p.to}`));
  return attackPairs(fen, other(me)).filter((p) => loose.has(p.to) && !before.has(`${p.from}${p.to}`));
}

export function threatsLens(fen: string, me: Color, prevFen?: string | null): LensMarks {
  const loose = loosePieces(fen);
  const rings: NonNullable<LensMarks['rings']> = loose.map((l) => ({
    square: l.square,
    tone: l.kind === 'hanging' ? 'bad' : 'warn',
  }));
  const turn = fen.split(' ')[1];
  const arrows: NonNullable<LensMarks['arrows']> =
    prevFen && turn === me ? newThreats(prevFen, fen, me).map((p) => ({ ...p, tone: 'threat' as const })) : [];
  const mine = loose.filter((l) => l.color === me).length;
  const theirs = loose.length - mine;
  const caption = !loose.length ? 'Nothing hanging' : `Yours at risk ${mine} · theirs ${theirs}`;
  return { rings, arrows, caption };
}

/**
 * Your men a move leaves loose that were not loose before it: what the
 * Undefended flash shows. The piece that moved counts at its new square.
 */
export function newlyLoose(before: string, after: string, me: Color, moved: { from: Square; to: Square }): Square[] {
  const was = new Set(loosePieces(before).filter((l) => l.color === me).map((l) => l.square));
  return loosePieces(after)
    .filter((l) => l.color === me)
    .map((l) => l.square)
    .filter((square) => {
      if (square === moved.to) return !was.has(moved.from);
      return !was.has(square);
    });
}

/* ── one call for the bar ─────────────────────────────────────────────── */

export function lensMarks(kind: LensKind, fen: string, me: Color, prevFen?: string | null): LensMarks {
  switch (kind) {
    case 'pawns':
      return pawnsLens(fen);
    case 'pieces':
      return piecesLens(fen, me);
    case 'space':
      return spaceLens(fen, me);
    case 'kings':
      return kingsLens(fen, me);
    case 'threats':
      return threatsLens(fen, me, prevFen);
  }
}
