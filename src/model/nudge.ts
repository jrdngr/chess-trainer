import {
  applySan,
  fenTurn,
  positionKey,
  walkSan,
  type Color,
  type Square,
} from '../chess/core';
import { popularReplies } from './growth';
import { familyName, namesAlong, type ReferenceIndex } from './reference';
import { childrenOf } from './repertoire';
import type { ExplorerMove, Repertoire } from './types';

/**
 * Nudges: keeping a repertoire narrow while it grows.
 *
 * Every move Growth or Run adds is a choice between book moves, and most of
 * those choices are not about which move is better — the book plays them all.
 * They are about how much there is to remember. A move that lands in a
 * position you already know, or one you already play in the same opening,
 * costs almost nothing to learn; one that shuts off the lines you have costs
 * a new line of its own.
 *
 * So the arrows are coloured. Green is the familiar move; yellow is the same,
 * for a familiar move the book ranks too low to draw, which is pulled onto the
 * board in place of the third arrow. Red is the reverse signal and stands on
 * its own: the move that closes off lines you have, or that you keep passing
 * on. Each coloured arrow says why, in a line under the board.
 */

/** Which kind of familiarity wins when both are on offer. */
export type NudgePriority = 'transposition' | 'habit';

export interface NudgePrefs {
  priority: NudgePriority;
  /** Count reaching your usual pawns as a (weaker) habit. */
  pawns: boolean;
}

export type NudgeTone = 'toward' | 'toward-far' | 'away';

export interface DrawnMove {
  san: string;
  from: Square;
  to: Square;
}

export interface NudgedMove extends DrawnMove {
  tone?: NudgeTone;
  reason?: string;
}

/** A move you have played this often in the opening is a habit. */
export const HABIT_MIN = 2;
/**
 * The share of games, 0..1, that have to reach one of your positions after
 * their reply for a move to count as transposing on the way. A rare reply
 * that happens to transpose is luck, not a route.
 */
export const VIA_REPLY_MIN = 0.25;

/* ── the profile ───────────────────────────────────────────────────────── */

interface ProfileNode {
  /** Positions before and after, as position keys. */
  before: string;
  after: string;
  fenAfter: string;
  san: string;
  /** Whether the move is yours. */
  mine: boolean;
  /** The opening the line is filed under, or null before the book names one. */
  family: string | null;
  depth: number;
  leaf: boolean;
}

/**
 * What a repertoire looks like from the point of view of a move being added:
 * every move in it, the opening each one belongs to, and every position it
 * can reach. Built once per repertoire and reused for every arrow.
 */
export interface Profile {
  color: Color;
  rootFen: string;
  nodes: ProfileNode[];
  /** Every position in the repertoire, with the line that reaches it first. */
  positions: Map<string, string[]>;
}

const profiles = new WeakMap<Repertoire, WeakMap<ReferenceIndex, Profile>>();

export function profileOf(rep: Repertoire, index: ReferenceIndex): Profile {
  const byIndex = profiles.get(rep) ?? new WeakMap<ReferenceIndex, Profile>();
  profiles.set(rep, byIndex);
  const cached = byIndex.get(index);
  if (cached) return cached;

  const nodes: ProfileNode[] = [];
  const positions = new Map<string, string[]>();
  positions.set(positionKey(rep.rootFen), []);
  // The deepest name so far is carried down rather than looked up per line:
  // the book names positions, and each node already knows its own.
  const walk = (nodeId: string | null, path: string[], named: string | null) => {
    for (const kid of childrenOf(rep, nodeId)) {
      const line = [...path, kid.san];
      const after = positionKey(kid.fenAfter);
      const name = index.names.get(after)?.name ?? named;
      if (!positions.has(after)) positions.set(after, line);
      nodes.push({
        before: kid.key,
        after,
        fenAfter: kid.fenAfter,
        san: kid.san,
        mine: fenTurn(kid.fenBefore) === rep.color,
        family: name ? familyName(index, name) : null,
        depth: line.length,
        leaf: kid.children.length === 0,
      });
      walk(kid.id, line, name);
    }
  };
  walk(null, [], null);

  const profile = { color: rep.color, rootFen: rep.rootFen, nodes, positions };
  byIndex.set(index, profile);
  return profile;
}

/**
 * The opening a line is in, for scoping habits: the family of the deepest name
 * the book gives it. Growth's rows are filed by the first name instead, which
 * for 1.d4 Nf6 is "Indian Defence" — true, and wide enough to count a
 * Nimzo-Indian move as a King's Indian habit.
 */
export function openingOf(index: ReferenceIndex, line: string[]): string | null {
  const names = namesAlong(index, line);
  const deepest = names[names.length - 1];
  return deepest ? familyName(index, deepest.name) : null;
}

/* ── the signals ───────────────────────────────────────────────────────── */

/** Check and capture marks do not make a different habit: Nxe5 is Ne5. */
export function sameMove(san: string): string {
  return san.replace(/[+#!?]/g, '').replace('x', '');
}

interface Signals {
  san: string;
  /** Lands on one of your positions: 1, or the share of replies that take it there. */
  transposes: number;
  transposesInto: string[] | null;
  transposesNow: boolean;
  /** Times you play this move elsewhere in the opening. */
  habit: number;
  /** Positions in the opening whose pawns of yours this move reaches. */
  pawns: number;
  /** Lines in the opening this move makes unreachable. */
  closes: number;
  /** Times it was a book option in the opening and you chose otherwise. */
  passed: number;
}

/**
 * Everything the arrows are coloured by, for one position and the book's
 * moves there.
 */
function signalsFor(
  profile: Profile,
  index: ReferenceIndex,
  path: string[],
  fen: string,
  sans: string[],
  prefs: NudgePrefs,
  minShare: number,
): { signals: Signals[]; family: string | null } {
  const fam = openingOf(index, path);
  const inOpening = profile.nodes.filter((node) => !fam || node.family === fam);
  const mineInOpening = inOpening.filter((node) => node.mine);

  // Where you have already chosen, and what: one entry per position, so a
  // transposition met twice is one choice rather than two.
  const chosen = new Map<string, Set<string>>();
  for (const node of mineInOpening) {
    const at = chosen.get(node.before) ?? new Set<string>();
    at.add(sameMove(node.san));
    chosen.set(node.before, at);
  }
  const habits = new Map<string, number>();
  for (const moves of chosen.values()) {
    for (const move of moves) habits.set(move, (habits.get(move) ?? 0) + 1);
  }
  // What else the book offered there, for "you keep passing on it".
  const passedOn = new Map<string, number>();
  const fenBefore = new Map<string, string>([[positionKey(profile.rootFen), profile.rootFen]]);
  for (const node of profile.nodes) {
    if (!fenBefore.has(node.after)) fenBefore.set(node.after, node.fenAfter);
  }
  for (const [key, moves] of chosen) {
    const at = fenBefore.get(key);
    if (!at) continue;
    for (const option of popularReplies(index, at, minShare)) {
      const move = sameMove(option.san);
      if (!moves.has(move)) passedOn.set(move, (passedOn.get(move) ?? 0) + 1);
    }
  }

  // The line so far: a move back into it is not a transposition, and a line
  // that ends on it is behind you rather than closed off.
  const onPath = new Set(walkSan(path, profile.rootFen).fens.map(positionKey));
  onPath.add(positionKey(fen));

  const leaves = uniqueBy(
    inOpening.filter((node) => node.leaf && node.depth > path.length && !onPath.has(node.after)),
    (node) => node.after,
  );
  const openBefore = leaves.filter((leaf) => reachable(fen, leaf.fenAfter));
  const myPawnsNow = pawnsOf(fen, profile.color);
  const usualPawns = new Map<string, number>();
  if (prefs.pawns) {
    for (const node of uniqueBy(inOpening, (n) => n.after)) {
      if (onPath.has(node.after)) continue;
      const pawns = pawnsOf(node.fenAfter, profile.color);
      usualPawns.set(pawns, (usualPawns.get(pawns) ?? 0) + 1);
    }
  }

  const signals: Signals[] = [];
  for (const san of sans) {
    const move = applySan(fen, san);
    if (!move) continue;
    const key = positionKey(move.after);
    let transposes = 0;
    let transposesInto: string[] | null = null;
    let transposesNow = false;
    if (!onPath.has(key) && profile.positions.has(key)) {
      transposes = 1;
      transposesInto = profile.positions.get(key)!;
      transposesNow = true;
    } else {
      for (const reply of popularReplies(index, move.after, minShare)) {
        const next = applySan(move.after, reply.san);
        if (!next) continue;
        const line = profile.positions.get(positionKey(next.after));
        if (!line) continue;
        transposes += reply.share / 100;
        transposesInto ??= line;
      }
      if (transposes < VIA_REPLY_MIN) {
        transposes = 0;
        transposesInto = null;
      }
    }
    const same = sameMove(san);
    const myPawns = pawnsOf(move.after, profile.color);
    signals.push({
      san,
      transposes,
      transposesInto,
      transposesNow,
      habit: habits.get(same) ?? 0,
      pawns: prefs.pawns && myPawns !== myPawnsNow ? (usualPawns.get(myPawns) ?? 0) : 0,
      closes: openBefore.filter((leaf) => !reachable(move.after, leaf.fenAfter)).length,
      passed: passedOn.get(same) ?? 0,
    });
  }
  return { signals, family: fam };
}

function uniqueBy<T>(items: T[], key: (item: T) => string): T[] {
  const seen = new Set<string>();
  return items.filter((item) => {
    const k = key(item);
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
}

/* ── reachability ──────────────────────────────────────────────────────── */

interface Placed {
  square: Square;
  type: string;
  color: Color;
}

const placedCache = new Map<string, Placed[]>();

/** The pieces on a FEN's board, read straight from the text: this runs thousands of times. */
function placed(fen: string): Placed[] {
  const board = fen.split(' ')[0];
  const cached = placedCache.get(board);
  if (cached) return cached;
  const out: Placed[] = [];
  board.split('/').forEach((row, i) => {
    let file = 0;
    for (const ch of row) {
      if (ch >= '1' && ch <= '8') {
        file += Number(ch);
        continue;
      }
      const lower = ch.toLowerCase();
      out.push({
        square: `${String.fromCharCode(97 + file)}${8 - i}` as Square,
        type: lower,
        color: ch === lower ? 'b' : 'w',
      });
      file += 1;
    }
  });
  if (placedCache.size > 5000) placedCache.clear();
  placedCache.set(board, out);
  return out;
}

/** One side's pawns as a stable string, for comparing structures. */
function pawnsOf(fen: string, color: Color): string {
  return placed(fen)
    .filter((piece) => piece.type === 'p' && piece.color === color)
    .map((piece) => piece.square)
    .sort()
    .join(',');
}

/**
 * Could a game standing at `from` still arrive at `to`?
 *
 * Only what cannot be undone is checked: pawns go forward and sideways only by
 * capturing, pieces once taken stay taken, castling once lost is lost. Pieces
 * can wander anywhere, so they are only counted. That is enough to say which
 * of your lines a pawn push shuts, and it errs toward "still reachable", so a
 * move is never marked red for closing a line it has not actually closed.
 */
export function reachable(from: string, to: string): boolean {
  const a = placed(from);
  const b = placed(to);
  const rights = (fen: string) => fen.split(' ')[2] ?? '-';
  const had = rights(from);
  for (const right of rights(to)) {
    if (right !== '-' && !had.includes(right)) return false;
  }
  for (const color of ['w', 'b'] as const) {
    for (const type of ['n', 'b', 'r', 'q'] as const) {
      const count = (pieces: typeof a) =>
        pieces.filter((piece) => piece.color === color && piece.type === type).length;
      if (count(b) > count(a)) return false;
    }
    const pawnsA = a.filter((piece) => piece.color === color && piece.type === 'p').map(coords);
    const pawnsB = b.filter((piece) => piece.color === color && piece.type === 'p').map(coords);
    if (!pawnsCanBecome(pawnsA, pawnsB, color)) return false;
  }
  return true;
}

function coords(piece: { square: Square }): [number, number] {
  return [piece.square.charCodeAt(0) - 97, Number(piece.square[1])];
}

/**
 * Can every pawn in the target come from its own pawn in the source? A pawn
 * moves up its file, or across one file per rank it gains by capturing.
 */
function pawnsCanBecome(from: [number, number][], to: [number, number][], color: Color): boolean {
  if (to.length > from.length) return false;
  const ahead = (src: [number, number], dst: [number, number]) =>
    color === 'w' ? dst[1] - src[1] : src[1] - dst[1];
  const can = (src: [number, number], dst: [number, number]) => {
    const gain = ahead(src, dst);
    return gain >= 0 && Math.abs(dst[0] - src[0]) <= gain;
  };
  const owner = new Array<number>(from.length).fill(-1);
  const assign = (t: number, seen: boolean[]): boolean => {
    for (let s = 0; s < from.length; s++) {
      if (seen[s] || !can(from[s], to[t])) continue;
      seen[s] = true;
      if (owner[s] < 0 || assign(owner[s], seen)) {
        owner[s] = t;
        return true;
      }
    }
    return false;
  };
  return to.every((_, t) => assign(t, new Array<boolean>(from.length).fill(false)));
}

/* ── choosing the colours ──────────────────────────────────────────────── */

type Candidate = Pick<ExplorerMove, 'san'> & { share: number };

/**
 * The arrows to draw at a position you are adding a move in, coloured.
 *
 * `drawn` is what the board would show without nudges, `candidates` every
 * book move you may choose there (already filtered to what the mode allows),
 * most played first. The familiar move is always on the board: in its own
 * arrow's place when it is already drawn, else in place of the arrow leaving
 * the same square, else in place of the third.
 */
export function nudgeArrows(
  rep: Repertoire | null | undefined,
  index: ReferenceIndex,
  path: string[],
  fen: string,
  drawn: DrawnMove[],
  candidates: Candidate[],
  prefs: NudgePrefs,
  minShare: number,
): NudgedMove[] {
  const out: NudgedMove[] = drawn.map((move) => ({ ...move }));
  if (!rep || !candidates.length) return out;
  const profile = profileOf(rep, index);
  if (!profile.nodes.length) return out;

  const { signals, family: fam } = signalsFor(
    profile,
    index,
    path,
    fen,
    candidates.map((c) => c.san),
    prefs,
    minShare,
  );
  const share = new Map(candidates.map((c) => [c.san, c.share]));
  const lines = fam ? `${fam} lines` : 'lines';

  const green = pickToward(signals, prefs.priority, share);
  if (green) {
    const reason = towardReason(green.signal, green.kind, index, lines, fam);
    const at = out.findIndex((move) => move.san === green.signal.san);
    if (at >= 0) {
      out[at] = { ...out[at], tone: 'toward', reason };
    } else {
      const move = applySan(fen, green.signal.san);
      if (move) {
        const nudged: NudgedMove = {
          san: move.san,
          from: move.from,
          to: move.to,
          tone: 'toward-far',
          reason,
        };
        const samePiece = out.findIndex((drawnMove) => drawnMove.from === move.from);
        if (samePiece >= 0) out[samePiece] = nudged;
        else if (out.length < 3) out.push(nudged);
        else out[out.length - 1] = nudged;
      }
    }
  }

  const onBoard = signals.filter(
    (signal) => out.some((move) => move.san === signal.san && !move.tone),
  );
  const red = pickAway(onBoard, prefs.priority, share);
  if (red) {
    const at = out.findIndex((move) => move.san === red.signal.san);
    out[at] = {
      ...out[at],
      tone: 'away',
      reason:
        red.kind === 'closes'
          ? `${red.signal.san} closes off ${countOf(red.signal.closes)} of your ${lines}`
          : `You've chosen another move over ${red.signal.san} ${red.signal.passed} times in your ${lines}`,
    };
  }
  return out;
}

type TowardKind = 'transposes' | 'habit' | 'pawns';
type AwayKind = 'closes' | 'passed';

function pickToward(
  signals: Signals[],
  priority: NudgePriority,
  share: Map<string, number>,
): { signal: Signals; kind: TowardKind } | null {
  const order: TowardKind[] =
    priority === 'transposition' ? ['transposes', 'habit', 'pawns'] : ['habit', 'pawns', 'transposes'];
  for (const kind of order) {
    const strength = (s: Signals) =>
      kind === 'transposes' ? s.transposes : kind === 'habit' ? (s.habit >= HABIT_MIN ? s.habit : 0) : s.pawns;
    const best = signals
      .filter((s) => strength(s) > 0)
      // Strongest first; the more popular move on a tie.
      .sort((a, b) => strength(b) - strength(a) || (share.get(b.san) ?? 0) - (share.get(a.san) ?? 0))[0];
    if (best) return { signal: best, kind };
  }
  return null;
}

function pickAway(
  signals: Signals[],
  priority: NudgePriority,
  share: Map<string, number>,
): { signal: Signals; kind: AwayKind } | null {
  const order: AwayKind[] = priority === 'transposition' ? ['closes', 'passed'] : ['passed', 'closes'];
  for (const kind of order) {
    const strength = (s: Signals) =>
      kind === 'closes' ? s.closes : s.passed >= HABIT_MIN ? s.passed : 0;
    const worst = signals
      .filter((s) => strength(s) > 0)
      // Strongest first; the less popular move on a tie.
      .sort((a, b) => strength(b) - strength(a) || (share.get(a.san) ?? 0) - (share.get(b.san) ?? 0))[0];
    if (worst) return { signal: worst, kind };
  }
  return null;
}

function towardReason(
  signal: Signals,
  kind: TowardKind,
  index: ReferenceIndex,
  lines: string,
  fam: string | null,
): string {
  if (kind === 'transposes') {
    const into = lineName(index, signal.transposesInto ?? []);
    return `${signal.san} ${signal.transposesNow ? 'transposes' : 'can transpose'} into your ${into}`;
  }
  if (kind === 'habit') return `You play ${signal.san} in ${signal.habit} ${lines}`;
  return `${signal.san} reaches your usual ${fam ? `${fam} ` : ''}pawns`;
}

/** The name of one of your lines, as short as it can be and still say which. */
function lineName(index: ReferenceIndex, line: string[]): string {
  const names = namesAlong(index, line);
  const deepest = names[names.length - 1]?.name;
  if (!deepest) return 'prep';
  const at = deepest.indexOf(': ');
  const variation = at < 0 ? deepest : deepest.slice(at + 2);
  return `${variation} line`;
}

function countOf(n: number): string {
  return n === 1 ? 'one' : String(n);
}
