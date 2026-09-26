import {
  applySan,
  fenTurn,
  START_FEN,
  legalMoves,
  legalSans,
  positionKey,
  walkSan,
  type Color,
  type LegalMove,
  type Square,
} from '../chess/core';
import { popularReplies } from './growth';
import { kinOf, shortFamily } from './kin';
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
  /** The repertoire node. */
  id: string;
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
        id: kid.id,
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
  return familyAlong(index, pathKeys(line, START_FEN));
}

/** `openingOf`, for a line already given as its positions. */
function familyAlong(index: ReferenceIndex, keys: string[]): string | null {
  for (let i = keys.length - 1; i >= 1; i--) {
    const named = index.names.get(keys[i]);
    if (named) return familyName(index, named.name);
  }
  return null;
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
  /**
   * The share of replies after which one more move of yours lands on one of
   * your positions: the move order converges a move later.
   */
  heads: number;
  headsInto: string[] | null;
  /** Times you choose this move elsewhere in the opening and its kin. */
  habit: number;
  /** The families those times come from, most first. */
  habitFrom: string[];
  /** Positions in the opening whose pawns of yours this move reaches. */
  pawns: number;
  /** Lines in the opening this move makes unreachable. */
  closes: number;
  closesFrom: string[];
  /** Times it was a book option in the opening and you chose otherwise. */
  passed: number;
  passedFrom: string[];
}

/** The families a tally came from, most first. */
function ranked(counts: Map<string, number> | undefined): string[] {
  if (!counts) return [];
  return [...counts].filter(([, n]) => n > 0).sort((a, b) => b[1] - a[1]).map(([family]) => family);
}

function sum(counts: Map<string, number> | undefined): number {
  let n = 0;
  for (const v of counts?.values() ?? []) n += v;
  return n;
}

/**
 * How far apart, in plies, a choice can be and still count as the same habit.
 * ...h5 on move ten is not a habit of playing ...h5 on move three, and 1...d6
 * is not what you do because you play ...d6 in your King's Indian on move
 * three — near enough, and the move means the same thing; far, and it is a
 * different move with the same name.
 */
export const HABIT_PLIES = 4;

/** One place you chose, or passed on, a move. */
interface Seen {
  key: string;
  ply: number;
  family: string;
}

/**
 * What one opening (with its kin) looks like, counted once: the places you
 * chose and what, the book moves you passed on there, and the lines that end
 * in it. Each arrow then reads the entries near its own depth, skipping the
 * positions the line so far — or a subtree being weighed — takes out.
 */
interface Context {
  scope: ProfileNode[];
  /** Every move you chose, by where. */
  habits: Map<string, Seen[]>;
  /** Every book move you passed on, by where. */
  passedOn: Map<string, Seen[]>;
  /** How many times each move was chosen, and passed on, at each ply, to list likely habits quickly. */
  byPly: Map<number, Map<string, number>>;
  passedByPly: Map<number, Map<string, number>>;
  leaves: ProfileNode[];
}

const contexts = new WeakMap<Profile, Map<string, Context>>();
const repliesCache = new WeakMap<ReferenceIndex, Map<string, string[]>>();

/** The book's moves at a position above a share, cached: the same positions are asked about again and again. */
function bookMovesAt(index: ReferenceIndex, fen: string, minShare: number): string[] {
  const cache = repliesCache.get(index) ?? new Map<string, string[]>();
  repliesCache.set(index, cache);
  const key = `${positionKey(fen)}|${minShare}`;
  let moves = cache.get(key);
  if (!moves) {
    moves = popularReplies(index, fen, minShare).map((move) => move.san);
    if (cache.size > 20_000) cache.clear();
    cache.set(key, moves);
  }
  return moves;
}

function contextOf(profile: Profile, index: ReferenceIndex, fam: string | null, minShare: number): Context {
  const byKey = contexts.get(profile) ?? new Map<string, Context>();
  contexts.set(profile, byKey);
  const cacheKey = `${fam ?? ''}|${minShare}`;
  const cached = byKey.get(cacheKey);
  if (cached) return cached;

  // The opening and its kin: habits carry across openings that share them,
  // so a new Catalan already knows your English's g3.
  const kin = fam ? kinOf(fam) : null;
  const scope = profile.nodes.filter((node) => !kin || (node.family !== null && kin.has(node.family)));
  const fenBefore = new Map<string, string>([[positionKey(profile.rootFen), profile.rootFen]]);
  for (const node of profile.nodes) {
    if (!fenBefore.has(node.after)) fenBefore.set(node.after, node.fenAfter);
  }
  // Where you have already chosen, and what: one entry per position, so a
  // transposition met twice is one choice rather than two.
  const chosen = new Map<string, { moves: Set<string>; family: string; ply: number }>();
  for (const node of scope) {
    if (!node.mine) continue;
    const at = chosen.get(node.before) ?? { moves: new Set<string>(), family: node.family ?? fam ?? '', ply: node.depth - 1 };
    at.moves.add(sameMove(node.san));
    chosen.set(node.before, at);
  }
  const habits = new Map<string, Seen[]>();
  const passedOn = new Map<string, Seen[]>();
  const add = (map: Map<string, Seen[]>, move: string, seen: Seen) => {
    const list = map.get(move) ?? [];
    list.push(seen);
    map.set(move, list);
  };
  const byPly = new Map<number, Map<string, number>>();
  const passedByPly = new Map<number, Map<string, number>>();
  for (const [key, at] of chosen) {
    const seen = { key, ply: at.ply, family: at.family };
    const counts = byPly.get(at.ply) ?? new Map<string, number>();
    byPly.set(at.ply, counts);
    for (const move of at.moves) {
      add(habits, move, seen);
      counts.set(move, (counts.get(move) ?? 0) + 1);
    }
    // What else the book offered there, for "you keep passing on it".
    const fen = fenBefore.get(key);
    if (!fen) continue;
    const passed = passedByPly.get(at.ply) ?? new Map<string, number>();
    passedByPly.set(at.ply, passed);
    for (const san of bookMovesAt(index, fen, minShare)) {
      const move = sameMove(san);
      if (at.moves.has(move)) continue;
      add(passedOn, move, seen);
      passed.set(move, (passed.get(move) ?? 0) + 1);
    }
  }
  const leaves = uniqueBy(
    scope.filter((node) => node.leaf),
    (node) => node.after,
  );
  const context = { scope, habits, passedOn, byPly, passedByPly, leaves };
  byKey.set(cacheKey, context);
  return context;
}

/** The entries near a depth, off the removed positions, by family. */
function near(list: Seen[] | undefined, ply: number, removed: ReadonlySet<string>): Map<string, number> {
  const out = new Map<string, number>();
  for (const seen of list ?? []) {
    if (Math.abs(seen.ply - ply) > HABIT_PLIES || removed.has(seen.key)) continue;
    out.set(seen.family, (out.get(seen.family) ?? 0) + 1);
  }
  return out;
}

const pathCache = new Map<string, string[]>();

/** The positions along a line, cached: a scan asks about the same lines many times. */
function pathKeys(path: string[], rootFen: string): string[] {
  const key = `${rootFen}|${path.join(' ')}`;
  let keys = pathCache.get(key);
  if (!keys) {
    keys = walkSan(path, rootFen).fens.map(positionKey);
    if (pathCache.size > 5000) pathCache.clear();
    pathCache.set(key, keys);
  }
  return keys;
}

/** What asking about a move leaves out: positions behind you, or going with a subtree. */
export interface SignalOptions {
  /** Positions to treat as gone, as if their lines were not in the repertoire. */
  gone?: ReadonlySet<string>;
  /** Count the lines each move closes off (red), which costs the most. Default true. */
  away?: boolean;
  /**
   * The positions along the line, root first, when the caller already has
   * them — a scan reads them off the tree rather than replaying every line.
   */
  pathKeys?: string[];
}

/**
 * Everything the arrows are coloured by, for one position and the moves
 * asked about there — book moves or not.
 */
function signalsFor(
  profile: Profile,
  index: ReferenceIndex,
  path: string[],
  fen: string,
  sans: string[],
  prefs: NudgePrefs,
  minShare: number,
  opts: SignalOptions = {},
): { signals: Signals[]; family: string | null } {
  const keys = opts.pathKeys ?? pathKeys(path, profile.rootFen);
  const fam = familyAlong(index, keys);
  const context = contextOf(profile, index, fam, minShare);
  const familyOf = (node: ProfileNode) => node.family ?? fam ?? '';

  // The line so far: a move back into it is not a transposition, and a line
  // that ends on it is behind you rather than closed off. Nor is a choice made
  // on it a habit, or a move passed over: those are about your *other* lines.
  // Counted here, a repertoire of one line nudged against its own moves.
  const removed = new Set(keys);
  removed.add(positionKey(fen));
  for (const key of opts.gone ?? []) removed.add(key);

  const away = opts.away ?? true;
  const openBefore = away
    ? context.leaves.filter(
        (leaf) => leaf.depth > path.length && !removed.has(leaf.after) && reachable(fen, leaf.fenAfter),
      )
    : [];
  // Lines another move you keep here still reaches are not closed off by
  // this one: you chose to branch, and those lines stay yours. Worked out
  // per leaf, so the move being asked about can leave out its own line.
  const here = positionKey(fen);
  const kept = away
    ? uniqueBy(
        profile.nodes.filter((node) => node.mine && node.before === here && !removed.has(node.after)),
        (node) => node.san,
      )
    : [];
  const keptReach = new Map<string, string[]>();
  for (const leaf of openBefore) {
    keptReach.set(
      leaf.after,
      kept.filter((node) => reachable(node.fenAfter, leaf.fenAfter)).map((node) => sameMove(node.san)),
    );
  }
  const myPawnsNow = pawnsOf(fen, profile.color);
  const usualPawns = new Map<string, number>();
  if (prefs.pawns) {
    for (const node of uniqueBy(context.scope, (n) => n.after)) {
      if (removed.has(node.after)) continue;
      const pawns = pawnsOf(node.fenAfter, profile.color);
      usualPawns.set(pawns, (usualPawns.get(pawns) ?? 0) + 1);
    }
  }
  /** One of your positions, off the line so far. */
  const yours = (key: string) => (removed.has(key) ? null : (profile.positions.get(key) ?? null));

  const signals: Signals[] = [];
  for (const san of sans) {
    const move = applied(fen, san);
    if (!move) continue;
    const key = positionKey(move.after);
    let transposes = 0;
    let transposesInto: string[] | null = null;
    let transposesNow = false;
    let heads = 0;
    let headsInto: string[] | null = null;
    if (yours(key)) {
      transposes = 1;
      transposesInto = yours(key);
      transposesNow = true;
    } else {
      // Their reply, and then one move of yours, both read off the book's
      // links rather than replayed: this runs for every move asked about.
      const entry = index.entries.get(key);
      const total = entry ? entry.moves.reduce((acc, m) => acc + m.games, 0) : 0;
      for (const reply of entry?.moves ?? []) {
        const share = total ? reply.games / total : 0;
        if (share * 100 < minShare) continue;
        const replyKey = reply.next ?? keyAfter(move.after, reply.san);
        if (!replyKey) continue;
        const line = yours(replyKey);
        if (line) {
          transposes += share;
          transposesInto ??= line;
          continue;
        }
        for (const next of index.entries.get(replyKey)?.moves ?? []) {
          const later = next.next ? yours(next.next) : null;
          if (!later) continue;
          heads += share;
          headsInto ??= later;
          break;
        }
      }
      if (transposes < VIA_REPLY_MIN) {
        transposes = 0;
        transposesInto = null;
      }
      if (heads < VIA_REPLY_MIN) {
        heads = 0;
        headsInto = null;
      }
    }
    const same = sameMove(san);
    const myPawns = pawnsOf(move.after, profile.color);
    const closedFrom = new Map<string, number>();
    let closes = 0;
    for (const leaf of openBefore) {
      if (reachable(move.after, leaf.fenAfter)) continue;
      if (keptReach.get(leaf.after)?.some((other) => other !== same)) continue;
      closes += 1;
      closedFrom.set(familyOf(leaf), (closedFrom.get(familyOf(leaf)) ?? 0) + 1);
    }
    const habitCounts = near(context.habits.get(same), path.length, removed);
    const passedCounts = near(context.passedOn.get(same), path.length, removed);
    signals.push({
      san,
      transposes,
      transposesInto,
      transposesNow,
      heads,
      headsInto,
      habit: sum(habitCounts),
      habitFrom: ranked(habitCounts),
      pawns: prefs.pawns && myPawns !== myPawnsNow ? (usualPawns.get(myPawns) ?? 0) : 0,
      closes,
      closesFrom: ranked(closedFrom),
      passed: sum(passedCounts),
      passedFrom: ranked(passedCounts),
    });
  }
  return { signals, family: fam };
}

const appliedCache = new Map<string, LegalMove | null>();

/** `applySan`, remembered: a scan tries the same moves in the same positions many times over. */
function applied(fen: string, san: string): LegalMove | null {
  const key = `${fen}|${san}`;
  let move = appliedCache.get(key);
  if (move === undefined) {
    move = applySan(fen, san);
    if (appliedCache.size > 50_000) appliedCache.clear();
    appliedCache.set(key, move);
  }
  return move;
}

function keyAfter(fen: string, san: string): string | null {
  const move = applied(fen, san);
  return move ? positionKey(move.after) : null;
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
 * move you may choose there (already filtered to what the mode allows), most
 * played first. Moves the book does not have may be among them, when the
 * engine has passed them (see `familiarOffBook`); `offBook` names those, and
 * their reason says so. The familiar move is always on the board: in its own
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
  offBook: ReadonlySet<string> = new Set(),
): NudgedMove[] {
  const out: NudgedMove[] = drawn.map((move) => ({ ...move }));
  // Your first move of the game picks the opening: nothing about the rest of
  // your lines makes one more familiar than another, so it is left plain.
  if (!rep || !candidates.length || isFirstMove(path)) return out;
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

  const green = pickToward(signals, prefs.priority, share);
  if (green) {
    const reason =
      towardReason(green.signal, green.kind, index, fam) + (offBook.has(green.signal.san) ? NOT_IN_BOOK : '');
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
    out[at] = { ...out[at], tone: 'away', reason: awayReason(red.signal, red.kind, fam) };
  }
  return out;
}

/** Whether a move after `path` is the first one of its side in the game. */
export function isFirstMove(path: readonly string[]): boolean {
  return path.length < 2;
}

/** Appended to the reason of a move the book does not have. */
export const NOT_IN_BOOK = ' · not in the book';

export type TowardKind = 'transposes' | 'heads' | 'habit' | 'pawns';
type AwayKind = 'closes' | 'passed';

function towardOrder(priority: NudgePriority): TowardKind[] {
  return priority === 'transposition'
    ? ['transposes', 'heads', 'habit', 'pawns']
    : ['habit', 'pawns', 'transposes', 'heads'];
}

function towardStrength(s: Signals, kind: TowardKind): number {
  if (kind === 'transposes') return s.transposes;
  if (kind === 'heads') return s.heads;
  if (kind === 'habit') return isHabit(s) ? s.habit : 0;
  return s.pawns;
}

/** How familiar a move is: the first kind it scores in, and how strongly. Null when it is not. */
function familiarity(s: Signals, priority: NudgePriority): { kind: TowardKind; rank: number; strength: number } | null {
  const order = towardOrder(priority);
  for (let rank = 0; rank < order.length; rank++) {
    const strength = towardStrength(s, order[rank]);
    if (strength > 0) return { kind: order[rank], rank, strength };
  }
  return null;
}

function pickToward(
  signals: Signals[],
  priority: NudgePriority,
  share: Map<string, number>,
): { signal: Signals; kind: TowardKind } | null {
  for (const kind of towardOrder(priority)) {
    const best = signals
      .filter((s) => towardStrength(s, kind) > 0)
      // Strongest first; the more popular move on a tie.
      .sort(
        (a, b) =>
          towardStrength(b, kind) - towardStrength(a, kind) || (share.get(b.san) ?? 0) - (share.get(a.san) ?? 0),
      )[0];
    if (best) return { signal: best, kind };
  }
  return null;
}

function awayStrength(s: Signals, kind: AwayKind): number {
  return kind === 'closes' ? s.closes : s.passed >= HABIT_MIN && s.passed > s.habit ? s.passed : 0;
}

/**
 * A habit is a move you choose when you can: at least `HABIT_MIN` times, and
 * at least as often as you pass it over. Counted across kin, a move like Nf3
 * is chosen in dozens of places and passed over in dozens more; that is not
 * a habit, only a common move.
 */
function isHabit(s: Signals): boolean {
  return s.habit >= HABIT_MIN && s.habit >= s.passed;
}

function pickAway(
  signals: Signals[],
  priority: NudgePriority,
  share: Map<string, number>,
): { signal: Signals; kind: AwayKind } | null {
  const order: AwayKind[] = priority === 'transposition' ? ['closes', 'passed'] : ['passed', 'closes'];
  for (const kind of order) {
    const worst = signals
      .filter((s) => awayStrength(s, kind) > 0)
      // Strongest first; the less popular move on a tie.
      .sort(
        (a, b) => awayStrength(b, kind) - awayStrength(a, kind) || (share.get(a.san) ?? 0) - (share.get(b.san) ?? 0),
      )[0];
    if (worst) return { signal: worst, kind };
  }
  return null;
}

function towardReason(signal: Signals, kind: TowardKind, index: ReferenceIndex, fam: string | null): string {
  if (kind === 'transposes') {
    const into = lineName(index, signal.transposesInto ?? []);
    return `${signal.san} ${signal.transposesNow ? 'transposes' : 'can transpose'} into your ${into}`;
  }
  if (kind === 'heads') return `${signal.san} heads toward your ${lineName(index, signal.headsInto ?? [])}`;
  if (kind === 'habit') return `You play ${signal.san} in ${signal.habit} ${linesOf(signal.habitFrom, fam)}`;
  return `${signal.san} reaches your usual ${fam ? `${shortFamily(fam)} ` : ''}pawns`;
}

function awayReason(signal: Signals, kind: AwayKind, fam: string | null): string {
  return kind === 'closes'
    ? `${signal.san} closes off ${countOf(signal.closes)} of your ${linesOf(signal.closesFrom, fam)}`
    : `You've chosen another move over ${signal.san} ${signal.passed} times in your ${linesOf(signal.passedFrom, fam)}`;
}

/**
 * "Catalan lines", or "English and Réti lines" when the count comes from kin:
 * the two families that gave most, named where the habit was learned.
 */
function linesOf(families: string[], fam: string | null): string {
  const named = families.filter(Boolean).slice(0, 2).map(shortFamily);
  if (!named.length) return fam ? `${shortFamily(fam)} lines` : 'lines';
  return `${named.join(' and ')} lines`;
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

/* ── moves the book does not have ──────────────────────────────────────── */

/**
 * Legal moves the book leaves out, or ranks under `minShare`, that are
 * familiar anyway: they transpose, head toward your lines, or are a habit.
 * Soundness is not judged here; the engine does that before any is shown.
 *
 * `habitsOnly` looks only at habits, which can be listed without trying every
 * legal move: what a scan of a whole repertoire can afford.
 */
export function familiarOffBook(
  rep: Repertoire | null | undefined,
  index: ReferenceIndex,
  path: string[],
  fen: string,
  prefs: NudgePrefs,
  minShare: number,
  opts: SignalOptions & { habitsOnly?: boolean } = {},
): string[] {
  if (!rep || isFirstMove(path)) return [];
  const profile = profileOf(rep, index);
  if (!profile.nodes.length) return [];
  const listed = new Set(bookMovesAt(index, fen, minShare));
  let sans: string[];
  if (opts.habitsOnly) {
    const context = contextOf(
      profile,
      index,
      familyAlong(index, opts.pathKeys ?? pathKeys(path, profile.rootFen)),
      minShare,
    );
    const counts = new Map<string, number>();
    const passed = new Map<string, number>();
    for (let ply = path.length - HABIT_PLIES; ply <= path.length + HABIT_PLIES; ply++) {
      for (const [move, n] of context.byPly.get(ply) ?? []) counts.set(move, (counts.get(move) ?? 0) + n);
      for (const [move, n] of context.passedByPly.get(ply) ?? []) passed.set(move, (passed.get(move) ?? 0) + n);
    }
    const listedMoves = new Set([...listed].map(sameMove));
    sans = [...counts]
      .filter(([move, n]) => n >= HABIT_MIN && n >= (passed.get(move) ?? 0) && !listedMoves.has(move))
      .map(([move]) => sanFor(fen, move))
      .filter((san): san is string => san !== null);
  } else {
    sans = legalMoves(fen)
      .map((move) => move.san)
      .filter((san) => !listed.has(san));
  }
  if (!sans.length) return [];
  const { signals } = signalsFor(profile, index, path, fen, sans, prefs, minShare, { ...opts, away: false });
  return signals
    .filter((s) => {
      const familiar = familiarity(s, prefs.priority);
      return familiar && (!opts.habitsOnly || familiar.kind === 'habit');
    })
    .map((s) => s.san);
}

const sansCache = new Map<string, Map<string, string>>();

/**
 * The move a habit names, as it is written in this position: "Ne5" may be
 * "Nxe5" here, which `sameMove` folded away. Null when it is not legal.
 */
function sanFor(fen: string, move: string): string | null {
  let bySame = sansCache.get(fen);
  if (!bySame) {
    bySame = new Map(legalSans(fen).map((san) => [sameMove(san), san]));
    if (sansCache.size > 5000) sansCache.clear();
    sansCache.set(fen, bySame);
  }
  return bySame.get(move) ?? null;
}

/* ── comparing moves ───────────────────────────────────────────────────── */

export interface Switch {
  san: string;
  /** What makes it familiar. */
  kind: TowardKind;
  /** Why it is familiar. */
  reason: string;
  /** Why your move works against your lines, when it does. */
  against: string | null;
}

/**
 * The move among `others` closest to the rest of your lines, if it is closer
 * than `mine`; null when `mine` is as familiar as any of them.
 *
 * `opts.gone` should hold the positions only `mine`'s subtree reaches, so that
 * neither move gets credit for the line `mine` already is. Familiarity is
 * compared kind first — in the priority order the arrows use — then
 * strength; ties go to the earlier of `others`.
 */
export function bestSwitch(
  rep: Repertoire,
  index: ReferenceIndex,
  path: string[],
  fen: string,
  mine: string,
  others: string[],
  prefs: NudgePrefs,
  minShare: number,
  opts: Omit<SignalOptions, 'away'> & { against?: boolean } = {},
): Switch | null {
  const profile = profileOf(rep, index);
  if (!profile.nodes.length) return null;
  const { signals, family: fam } = signalsFor(profile, index, path, fen, [mine, ...others], prefs, minShare, {
    ...opts,
    away: false,
  });
  const ours = signals.find((s) => s.san === mine);
  const bar = ours ? familiarity(ours, prefs.priority) : null;
  let best: { signal: Signals; kind: TowardKind; rank: number; strength: number } | null = null;
  for (const signal of signals) {
    if (signal.san === mine) continue;
    const f = familiarity(signal, prefs.priority);
    if (!f) continue;
    const above = (a: { rank: number; strength: number }, b: { rank: number; strength: number } | null) =>
      !b || a.rank < b.rank || (a.rank === b.rank && a.strength > b.strength);
    if (!above(f, bar)) continue;
    // A habit is only a reason to switch where your move is a one-off: you
    // play the other move in your other lines and never this one. Two moves
    // you both play elsewhere are a matter of taste, not a loose end.
    // Nor is a capture: taking back is what the position asks for, not a
    // choice between setups.
    if (f.kind === 'habit' && ((ours?.habit ?? 0) > 0 || mine.includes('x'))) continue;
    if (best && !above(f, best)) continue;
    best = { signal, ...f };
  }
  if (!best) return null;
  // Red for your move is worked out only now, for the one position shown:
  // counting closed lines is the dearest signal of all.
  return {
    san: best.signal.san,
    kind: best.kind,
    reason: towardReason(best.signal, best.kind, index, fam) + (best.kind === 'habit' ? `, ${mine} in none` : ''),
    against: opts.against === false ? null : againstReason(rep, index, path, fen, mine, prefs, minShare, opts),
  };
}

/**
 * Why a move of yours works against your other lines — it closes them off,
 * or you keep choosing otherwise — or null. Counting closed lines is the
 * dearest signal of all, so a scan leaves it to the cards it shows.
 */
export function againstReason(
  rep: Repertoire,
  index: ReferenceIndex,
  path: string[],
  fen: string,
  mine: string,
  prefs: NudgePrefs,
  minShare: number,
  opts: Omit<SignalOptions, 'away'> = {},
): string | null {
  const profile = profileOf(rep, index);
  const { signals, family: fam } = signalsFor(profile, index, path, fen, [mine], prefs, minShare, {
    ...opts,
    away: true,
  });
  const away = signals[0] ? pickAway([signals[0]], prefs.priority, new Map()) : null;
  return away ? awayReason(away.signal, away.kind, fam) : null;
}

/**
 * The positions only a subtree reaches: what goes if the move at its top is
 * switched away. A position another line also reaches stays.
 */
export function goneWith(rep: Repertoire, index: ReferenceIndex, nodeId: string): Set<string> {
  const profile = profileOf(rep, index);
  const inside = new Set<string>();
  const stack = [nodeId];
  while (stack.length) {
    const id = stack.pop()!;
    const node = rep.nodes[id];
    if (!node) continue;
    inside.add(id);
    stack.push(...node.children);
  }
  const outside = new Set<string>();
  for (const node of profile.nodes) if (!inside.has(node.id)) outside.add(node.after);
  const gone = new Set<string>();
  for (const node of profile.nodes) {
    if (inside.has(node.id) && !outside.has(node.after)) gone.add(node.after);
  }
  return gone;
}
