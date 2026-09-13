import {
  applySan,
  fenTurn,
  positionKey,
  sansToMoveText,
  START_FEN,
  type Color,
  type Square,
} from '../chess/core';
import { findHoles, optionsAt, type Hole } from './growth';
import { deepestName, lookup, type ReferenceIndex } from './reference';
import { insideRegion, lineStatus, approachKeys, type OpeningNode, type OpeningTree } from './openingTree';
import type { RepairItem } from './repair';
import { childrenOf, fenAt, leafLines, pathTo } from './repertoire';
import { cardId, mulberry32 } from './session';
import type { Card, RepMove, Repertoire } from './types';

/**
 * Run: one secret line, played until the first mistake ends the run.
 *
 * A run lives inside a region of the opening tree — the whole book, one first
 * move, a family, or a single variation — and one rule decides every move:
 * inside the region, a move keeps you alive if it is prepared or it is theory.
 * The opponent replies in proportion to how often each move is played, but
 * only with moves that keep the game inside the region; on the way in, only
 * moves the book can still get there from. Past the end of the book your prep
 * is the only referee. At the end of the prep the run is complete — unless it
 * has moves left to add, in which case the book's replies are offered and the
 * one you choose becomes prep.
 *
 * A `LineSource` answers those questions about a position, and everything
 * else (judging, revealing, scoring) is shared.
 */
export interface LineSource {
  /** Named after the region the run was drawn from. */
  label: string;
  color: Color;
  node: OpeningNode;
  /** Moves that keep the run alive from this position, best first. */
  movesAt(fen: string, played: string[]): string[];
  /** Relative likelihood of each opponent reply. */
  weightsAt(fen: string, played: string[]): { san: string; weight: number }[];
  /** Your own prepared moves here, preferred first. Empty where prep says nothing. */
  prepAt(fen: string): string[];
}

export function other(color: Color): Color {
  return color === 'w' ? 'b' : 'w';
}

/* ── the region source ──────────────────────────────────────────────────── */

/** The least often a prepared sideline may be chosen, as a share of the position. */
const SIDELINE_FLOOR = 0.01;

/**
 * One repertoire, indexed by position so transpositions behave the way they do
 * in training: the same position reached two ways offers the same moves.
 *
 * Every position in the tree is indexed, the opponent's included — their
 * prepared replies are what keeps a run going once the book runs out.
 */
export function prepIndex(rep: Repertoire | null): Map<string, string[]> {
  const byPosition = new Map<string, string[]>();
  if (!rep) return byPosition;
  const visit = (nodeId: string | null) => {
    const key = positionKey(fenAt(rep, nodeId));
    const kids = childrenOf(rep, nodeId);
    const list = byPosition.get(key) ?? [];
    for (const kid of [...kids].sort((a, b) => Number(b.preferred) - Number(a.preferred))) {
      if (!list.includes(kid.san)) list.push(kid.san);
    }
    byPosition.set(key, list);
    for (const kid of kids) visit(kid.id);
  };
  visit(null);
  return byPosition;
}

/**
 * Prepared or theory, inside the region.
 *
 * `rep` is the tree for the side being played, or null when nothing has been
 * prepared for it — a run on an empty repertoire is a run through the book,
 * which is exactly what a new install should be handed.
 */
export function regionSource(
  tree: OpeningTree,
  node: OpeningNode,
  rep: Repertoire | null,
  color: Color,
): LineSource {
  const index = tree.index;
  const prep = prepIndex(rep);
  const approach = node.depth === 0 ? null : approachKeys(tree, node);

  /** Every move that can be played here at all, prep first, then the book by popularity. */
  const candidates = (fen: string, played: string[]) => {
    const status = lineStatus(tree, node, played);
    if (status === 'outside') return [] as { san: string; games: number; prepared: boolean }[];
    const key = positionKey(fen);
    const mine = prep.get(key) ?? [];
    const book = [...(lookup(index, fen)?.moves ?? [])].sort((a, b) => b.games - a.games);
    const total = book.reduce((sum, move) => sum + move.games, 0);
    const games = new Map(book.map((move) => [move.san, move.games]));
    // A prepared move nobody in the database plays still deserves a turn, just
    // a rare one: the floor keeps sidelines in the rotation without letting
    // them crowd out the move orders you will actually meet.
    const floor = Math.max(1, total * SIDELINE_FLOOR);
    const out: { san: string; games: number; prepared: boolean }[] = [];
    for (const san of mine) out.push({ san, games: Math.max(floor, games.get(san) ?? 0), prepared: true });
    for (const move of book) {
      if (!mine.includes(move.san)) out.push({ san: move.san, games: Math.max(1, move.games), prepared: false });
    }
    if (status === 'reached' || !approach) return out;
    // Still on the way in: only moves the book can reach the opening from.
    return out.filter((move) => {
      const applied = applySan(fen, move.san);
      if (!applied) return false;
      const after = positionKey(applied.after);
      return after === node.key || approach.has(after);
    });
  };

  return {
    label: node.name,
    color,
    node,
    movesAt: (fen, played) => candidates(fen, played).map((move) => move.san),
    weightsAt: (fen, played) => candidates(fen, played).map((move) => ({ san: move.san, weight: move.games })),
    prepAt: (fen) => prep.get(positionKey(fen)) ?? [],
  };
}

/**
 * How often each line of a repertoire should come up, as a weight per leaf.
 *
 * Walked top-down so the weights form a distribution rather than a score per
 * line. Two kinds of branching are told apart, which is the whole point:
 *
 * - Where the *opponent* chooses, the reference database says how often each
 *   move is actually played, so you meet the King's Indian through 2.c4 far
 *   more often than through 2.Bg5. A prepared move the database has never seen
 *   falls back to an even split, and every share has a floor, so a sideline
 *   stays in the rotation instead of vanishing.
 * - Where *you* choose between prepared alternatives, the split is even. This
 *   is what stops a heavily branched mainline from swamping everything else:
 *   your own alternatives multiply leaves without making the position any more
 *   likely to appear on the board.
 *
 * Returns an empty map without reference data: there is nothing to weight by,
 * and the caller should draw evenly rather than trust a walk that would just
 * favour whichever sideline branches least.
 */
export function lineOdds(
  rep: Repertoire,
  side: Color,
  index?: ReferenceIndex | null,
  eligible?: Set<string>,
): Map<string, number> {
  const odds = new Map<string, number>();
  if (!index) return odds;
  const wanted = (tipId: string) => !eligible || eligible.has(tipId);

  // Branches with no line this run could use are pruned before anything is
  // split, so their share goes to the lines that remain rather than being
  // dropped — otherwise filtering out short lines quietly drags the mainline
  // down and inflates whatever sideline happens to be all long lines.
  const reachable = new Map<string, boolean>();
  const leadsSomewhere = (nodeId: string | null): boolean => {
    const key = nodeId ?? '';
    const seen = reachable.get(key);
    if (seen !== undefined) return seen;
    const kids = childrenOf(rep, nodeId);
    const ok = kids.length
      ? kids.some((kid) => leadsSomewhere(kid.id))
      : nodeId !== null && wanted(nodeId);
    reachable.set(key, ok);
    return ok;
  };

  const splits = (fen: string, kids: RepMove[]): number[] => {
    const even = kids.map(() => 1 / kids.length);
    if (kids.length < 2 || fenTurn(fen) === side) return even;
    const entry = lookup(index, fen);
    if (!entry || entry.moves.length < 2) return even;
    const total = entry.moves.reduce((sum, m) => sum + m.games, 0);
    if (total <= 0) return even;
    const games = new Map(entry.moves.map((m) => [m.san, m.games]));
    return kids.map((kid) => Math.max(SIDELINE_FLOOR, (games.get(kid.san) ?? 0) / total));
  };

  const visit = (nodeId: string | null, weight: number) => {
    const kids = childrenOf(rep, nodeId).filter((kid) => leadsSomewhere(kid.id));
    if (!kids.length) {
      if (nodeId && wanted(nodeId)) odds.set(nodeId, weight);
      return;
    }
    const shares = splits(fenAt(rep, nodeId), kids);
    const total = shares.reduce((sum, n) => sum + n, 0) || 1;
    kids.forEach((kid, i) => visit(kid.id, (weight * shares[i]) / total));
  };
  if (leadsSomewhere(null)) visit(null, 1);
  return odds;
}

/* ── options ────────────────────────────────────────────────────────────── */

export type ColorChoice = Color | 'random';

/** How long you get for each of your own moves. */
export type ClockMode = 'off' | 'move10' | 'move30';

export const CLOCK_MODES: ClockMode[] = ['off', 'move10', 'move30'];

/** Seconds per move, or null with the clock off. */
export function clockSeconds(mode: ClockMode): number | null {
  switch (mode) {
    case 'move10':
      return 10;
    case 'move30':
      return 30;
    default:
      return null;
  }
}

export function clockLabel(mode: ClockMode): string {
  switch (mode) {
    case 'move10':
      return '10s';
    case 'move30':
      return '30s';
    default:
      return 'Off';
  }
}

export const HINT_BUDGETS = [0, 1, 3];

/**
 * What the opponent steers you toward: the line drawn up front.
 *
 *   popular — your lines by how often you would actually meet them.
 *   weak    — the same, tilted hard toward positions you answer badly, have
 *             let lapse, or got wrong in your own games.
 *   gaps    — a reply you have no answer to, so the run reaches the edge of
 *             the prep and offers the book.
 */
export type Steer = 'popular' | 'weak' | 'gaps';

export const STEERS: Steer[] = ['popular', 'weak', 'gaps'];

export function steerLabel(steer: Steer): string {
  switch (steer) {
    case 'weak':
      return 'Weak spots';
    case 'gaps':
      return 'Gaps';
    default:
      return 'Popular';
  }
}

/** How many moves a run may add at the edge of the prep. */
export const NEW_MOVE_BUDGETS = [0, 1, 2, 3, 4, 5, 6, 7, 8];

/**
 * How much a hole that widens the repertoire outweighs one that lengthens it,
 * on an opening with no breadth at all. Fades to nothing as breadth arrives.
 */
export const BREADTH_TILT = 3;

/**
 * What the setup screen decides. The colour and the opening are global and
 * live in the selection, not here.
 */
export interface OpeningRunOptions {
  steer: Steer;
  /**
   * Moves the run may add. Where your prep runs out — on your move, with the
   * book still going — the book's replies are offered and the one you choose
   * is written into the repertoire; with none left the run is complete there.
   */
  newMoves: number;
  clock: ClockMode;
  hints: number;
  /**
   * Carry on past the end of the prep, with the engine calling blunders.
   * A line that stops the moment the setup is done is anticlimactic; this turns
   * the rest of it into a game you can still lose.
   */
  extended: boolean;
}

export const DEFAULT_OPTIONS: OpeningRunOptions = {
  steer: 'popular',
  newMoves: 0,
  clock: 'off',
  hints: 0,
  extended: false,
};

export type OpeningRunPrefs = OpeningRunOptions;

export const DEFAULT_PREFS: OpeningRunPrefs = { ...DEFAULT_OPTIONS };

/* ── runs ───────────────────────────────────────────────────────────────── */

export interface Run {
  /** Distinguishes one run from the next, so a run can be amended in place. */
  id: string;
  sourceLabel: string;
  /** The region the run was drawn in — an opening tree node id. */
  openingId: string;
  /** The tree for the side played, when there is one. */
  repertoireId?: string;
  /**
   * True once the run has stepped outside its prep onto a real book move and
   * carried on. Everything after that is judged by the book, and the run is
   * graded as an out-of-prep one however it ends.
   */
  leftPrep: boolean;
  color: Color;
  fen: string;
  played: string[];
  /** The user's correct moves so far — the score. */
  survived: number;
  over: boolean;
  /** Remaining moves of the line chosen up front, driving opponent replies. */
  target: string[];
  /** Hints left to spend. */
  hints: number;
  /** Hints spent, shown on the reveal so a deep run stays honest. */
  hintsUsed: number;
  /** Moves the run may still add at the edge of the prep. */
  newMoves: number;
  /** Moves it has added. */
  added: number;
  /**
   * How many plies had been played when the prep ran out, or null while the run
   * is still inside the book. Set once and never cleared: everything after it
   * was judged by the engine rather than by the repertoire.
   */
  prepEnded: number | null;
}

/**
 * How a run ended. Leaving the prep is kept apart from the rest: it is the one
 * ending where the move you played was real theory.
 */
export type DeathCause = 'move' | 'time' | 'blunder' | 'offprep';

let runCounter = 0;

function newRunId(): string {
  runCounter += 1;
  return `run${runCounter}-${Date.now().toString(36)}`;
}

/** The moves of a line that are yours to find. */
function yourMoves(color: Color, path: RepMove[]): RepMove[] {
  return path.filter((node) => fenTurn(node.fenBefore) === color);
}

/* ── picking a line you are bad at ──────────────────────────────────────── */

/** How badly each position wants practice, keyed by repertoire and position. */
export type Weakness = (repertoireId: string, key: string) => number;

/**
 * Turn the review schedule into a practice appetite.
 *
 * A position you have lapsed on, answered wrong, or let go overdue is worth
 * more than one you have never seen, which in turn is worth more than one you
 * have answered right three times running. The numbers are only ever compared
 * against each other, so their scale does not matter.
 */
export function weaknessFromCards(
  cards: Record<string, Card>,
  /** Positions your own games got wrong, which want repeating whatever the schedule says. */
  slips: Pick<RepairItem, 'kind' | 'repertoireId' | 'key' | 'games'>[] = [],
  now = Date.now(),
): Weakness {
  const slipped = new Map<string, number>();
  for (const item of slips) {
    if (item.kind !== 'offprep') continue;
    const id = cardId(item.repertoireId, item.key);
    slipped.set(id, (slipped.get(id) ?? 0) + item.games);
  }
  return (repertoireId, key) => {
    const id = cardId(repertoireId, key);
    const card = cards[id];
    const evidence = 2 * Math.min(3, slipped.get(id) ?? 0);
    // Never studied: worth seeing, but not the emergency a lapse is.
    if (!card) return 1.5 + evidence;
    let score = 1 + evidence;
    score += card.lapses * 1.2;
    score += Math.max(0, 2.5 - card.ease) * 2;
    if (card.stage === 'learning') score += 1;
    if (card.due <= now) score += 1;
    const answered = card.correct + card.incorrect;
    if (answered > 0) score += (card.incorrect / answered) * 2;
    return score;
  };
}

/**
 * The mean appetite over the positions a line asks you about.
 *
 * Keys come straight off the repertoire tree, which already stores the position
 * key of every move — so weighting the whole repertoire costs no chess.
 */
export function lineWeakness(repertoireId: string, keys: string[], weakness: Weakness): number {
  if (!keys.length) return 1;
  let sum = 0;
  for (const key of keys) sum += weakness(repertoireId, key);
  return sum / keys.length;
}

function pickWeighted<T>(items: T[], weight: (item: T) => number, rand: () => number): T {
  const total = items.reduce((sum, item) => sum + Math.max(0, weight(item)), 0);
  if (total <= 0) return items[Math.floor(rand() * items.length)];
  let roll = rand() * total;
  for (const item of items) {
    roll -= Math.max(0, weight(item));
    if (roll <= 0) return item;
  }
  return items[items.length - 1];
}

/* ── starting ───────────────────────────────────────────────────────────── */

export interface BeginOptions extends Partial<OpeningRunOptions> {
  tree: OpeningTree;
  reps: Repertoire[];
  /** The region to run in. */
  node: OpeningNode;
  /**
   * An opening inside the region to walk toward, when something has decided
   * one. The rule for staying alive is still the region's; only the opponent's
   * choice of line is narrowed.
   */
  toward?: OpeningNode;
  color: ColorChoice;
  seed?: number;
  /** Skip lines that ask fewer than this many moves of the user. */
  minDecisions?: number;
  /** Positions you answer badly, scored — see `weaknessFromCards`. */
  weakness?: Weakness | null;
  /** What counts as a hole worth steering toward. */
  growth?: { minShare?: number; maxPly?: number };
  /**
   * How hard to tilt a gaps run toward widening the repertoire rather than
   * lengthening it, 0..1 — how bare the opening is, see `thinness`. Zero, the
   * default, draws holes on popularity and depth alone.
   */
  breadth?: number;
  /** How much more a hole is worth for the games you have lost in it — see `evidenceFor`. */
  holeWeight?: (hole: Hole) => number;
}

/**
 * A run in a region: the source, and the run with its line drawn.
 *
 * The line drawn up front only steers the opponent. It is one of your own
 * prepared lines through the region when you have any, drawn on how often you
 * would actually meet it (and on how badly you answer it, when asked); steered
 * at gaps, it is the way to a reply you have no answer to, drawn on how often
 * that reply is played and how early it comes. Failing either it is the
 * region's own move order, so the opponent still walks you into the opening
 * you asked for. Any move that stays inside the region is accepted at your own
 * turn whichever line was drawn.
 *
 * Null only when the book is empty, which it never is.
 */
export function beginRun(opts: BeginOptions): { source: LineSource; run: Run } | null {
  const rand = mulberry32(opts.seed ?? Math.floor(Math.random() * 2 ** 31));
  const side = resolveColor(opts.color, rand);
  const { tree, node } = opts;
  if (!lookup(tree.index, START_FEN)?.moves.length) return null;
  const rep = opts.reps.find((r) => r.color === side) ?? null;
  const source = regionSource(tree, node, rep, side);
  const aim = opts.toward ?? node;

  const steer = opts.steer ?? DEFAULT_OPTIONS.steer;
  let target = aim.sans;
  const gap = rep && steer === 'gaps' ? drawHole(rep, tree, aim, opts, rand) : null;
  if (gap) {
    target = [...gap.path, gap.san];
  } else if (rep) {
    const minDecisions = opts.minDecisions ?? 4;
    const weakness = steer === 'weak' ? (opts.weakness ?? null) : null;
    const inRegion = leafLines(rep)
      .filter((line) => lineStatus(tree, aim, line.sans) === 'reached')
      .map((line) => {
        const path = pathTo(rep, line.tipId);
        return { tipId: line.tipId, sans: line.sans, keys: yourMoves(side, path).map((n) => n.key) };
      });
    // Long enough to be a game where there are such lines; anything at all
    // where there are not — a thin region is still yours to play.
    const long = inRegion.filter((line) => line.keys.length >= minDecisions);
    const usable = long.length ? long : inRegion;
    if (usable.length) {
      const odds = lineOdds(rep, side, tree.index, new Set(usable.map((l) => l.tipId)));
      const even = odds.size === 0;
      const line = pickWeighted(
        usable,
        (l) => (even ? 1 : (odds.get(l.tipId) ?? 0)) * (weakness ? lineWeakness(rep.id, l.keys, weakness) : 1),
        rand,
      );
      target = line.sans;
    }
  }

  const run: Run = {
    id: newRunId(),
    sourceLabel: node.name,
    openingId: node.id,
    repertoireId: rep?.id,
    leftPrep: false,
    color: side,
    fen: START_FEN,
    played: [],
    survived: 0,
    over: false,
    target,
    hints: opts.hints ?? DEFAULT_OPTIONS.hints,
    hintsUsed: 0,
    newMoves: Math.max(0, opts.newMoves ?? DEFAULT_OPTIONS.newMoves),
    added: 0,
    prepEnded: null,
  };
  return { source, run };
}

/**
 * The hole to walk toward: drawn on how often its reply is played, how early
 * it comes, what your own games say about it, and — on a bare opening — on
 * whether answering it would make the repertoire wider or only longer. Null
 * where the prep has no holes in the region, and the run falls back to a line
 * through it.
 *
 * The tilt is what stops a thin repertoire being fed back to itself. Left to
 * popularity, the loudest hole is nearly always the tip of the one line you
 * have: the book's main move at every ply is the most played thing on the
 * board, so round after round walks the same opening and makes it one move
 * longer. A hole you already answer some other reply to is a junction —
 * answering it is a white reply you have never seen, which is the thing a
 * repertoire this bare is short of. Once the opening is broad the tilt is
 * zero and depth is worth having again.
 */
function drawHole(
  rep: Repertoire,
  tree: OpeningTree,
  aim: OpeningNode,
  opts: BeginOptions,
  rand: () => number,
): Hole | null {
  const holes = findHoles(rep, tree.index, { ...opts.growth, region: { tree, node: aim } });
  if (!holes.length) return null;
  const evidence = opts.holeWeight ?? (() => 1);
  const breadth = Math.max(0, Math.min(1, opts.breadth ?? 0));
  return pickWeighted(
    holes,
    (hole) => {
      const widen = hole.answered > 0 ? 1 + BREADTH_TILT * breadth : 1;
      return (Math.max(hole.share, 0.1) * evidence(hole) * widen) / (1 + hole.path.length / 3);
    },
    rand,
  );
}

/** Resolve "random" once, up front, so the rest of a run is deterministic. */
export function resolveColor(color: ColorChoice, rand: () => number): Color {
  return color === 'random' ? (rand() < 0.5 ? 'w' : 'b') : color;
}

export function isUsersTurn(run: Run): boolean {
  return fenTurn(run.fen) === run.color;
}

export function movesHere(source: LineSource, run: Run): string[] {
  return source.movesAt(run.fen, run.played);
}

/**
 * What a move is, before it is played: your own prep, real theory your prep
 * does not have, or a move that ends the run.
 *
 * Theory is only told apart from prep where prep has something to say. Where
 * it says nothing — the book past the end of your lines, or a region you have
 * never prepared — a theory move is simply the move, and a run never pauses
 * over it.
 */
export type MoveKind = 'prep' | 'theory' | 'miss';

export function classify(source: LineSource, run: Run, san: string): MoveKind {
  if (!movesHere(source, run).includes(san)) return 'miss';
  const prep = source.prepAt(run.fen);
  if (run.leftPrep || !prep.length || prep.includes(san)) return 'prep';
  return 'theory';
}

export type Judgement =
  | { ok: true; run: Run; san: string }
  | { ok: false; run: Run; played: string; expected: string[] };

/** Judge one move by the user. A move outside the source ends the run. */
export function play(source: LineSource, run: Run, san: string): Judgement {
  const options = movesHere(source, run);
  if (!options.includes(san)) {
    // The losing move is reported separately and deliberately kept out of
    // `played`, so the reveal shows the line rather than the mistake.
    return { ok: false, run: { ...run, over: true }, played: san, expected: options };
  }
  const move = applySan(run.fen, san);
  if (!move) return { ok: false, run: { ...run, over: true }, played: san, expected: options };

  // Stepping off the drawn line is fine; it just stops steering the opponent.
  const target = run.target[run.played.length] === san ? run.target : [];
  return {
    ok: true,
    san,
    run: {
      ...run,
      fen: move.after,
      played: [...run.played, san],
      survived: run.survived + 1,
      target,
    },
  };
}

/**
 * Spend a hint: the square the move starts from, never where it lands.
 *
 * Knowing the piece narrows a position without answering it — you still have to
 * know where it belongs, which is the part worth remembering.
 */
export function takeHint(
  source: LineSource,
  run: Run,
): { run: Run; from: Square; san: string } | null {
  if (run.hints <= 0) return null;
  const best = source.prepAt(run.fen)[0] ?? movesHere(source, run)[0];
  if (!best) return null;
  const move = applySan(run.fen, best);
  if (!move) return null;
  return {
    run: { ...run, hints: run.hints - 1, hintsUsed: run.hintsUsed + 1 },
    from: move.from,
    san: best,
  };
}

/** The opponent's reply: the drawn line where it still applies, else weighted. */
export function opponentReply(source: LineSource, run: Run, rand: () => number): Run {
  const onLine = run.target[run.played.length];
  const options = source.weightsAt(run.fen, run.played);
  if (!options.length) return { ...run, over: true };

  let san = onLine && options.some((o) => o.san === onLine) ? onLine : null;
  if (!san) {
    // Prefer replies the source can still answer, so a run does not dead-end
    // on the opponent's move when a real continuation exists.
    const live = options.filter((o) => {
      const move = applySan(run.fen, o.san);
      return move ? source.movesAt(move.after, [...run.played, o.san]).length > 0 : false;
    });
    const pool = live.length ? live : options;
    const total = pool.reduce((sum, o) => sum + o.weight, 0);
    let roll = rand() * total;
    san = pool[pool.length - 1].san;
    for (const option of pool) {
      roll -= option.weight;
      if (roll <= 0) {
        san = option.san;
        break;
      }
    }
  }

  const move = applySan(run.fen, san);
  if (!move) return { ...run, over: true };
  return { ...run, fen: move.after, played: [...run.played, san] };
}

/* ── stepping outside your prep ─────────────────────────────────────────── */

/**
 * How a run ended, in four flavours rather than two.
 *
 * Leaving your prep is not the same kind of failure as playing a move nobody
 * has ever played, and finishing a line after having left it is not the same
 * kind of success as finishing one you knew all the way through. Keeping them
 * apart is the difference between "learn this" and "you got that wrong".
 */
export type RunGrade = 'green' | 'yellow' | 'red' | 'purple';

export function gradeOf(run: Run, completed: boolean): RunGrade {
  if (completed) return run.leftPrep ? 'yellow' : 'green';
  return run.leftPrep ? 'purple' : 'red';
}

export const GRADES: RunGrade[] = ['green', 'yellow', 'red', 'purple'];

export function gradeLabel(grade: RunGrade): string {
  switch (grade) {
    case 'green':
      return 'Clean finish';
    case 'yellow':
      return 'Finished out of prep';
    case 'purple':
      return 'Left your prep';
    default:
      return 'Run over';
  }
}

/** Whether a move is real theory here, whatever your own prep says. */
export function bookHas(index: ReferenceIndex, fen: string, san: string): boolean {
  return (lookup(index, fen)?.moves ?? []).some((move) => move.san === san);
}

/** Is this line still inside the run's region? */
export function staysInside(tree: OpeningTree, run: Run, san: string): boolean {
  const node = tree.byId.get(run.openingId) ?? tree.root;
  return insideRegion(tree, node, [...run.played, san]);
}

/**
 * Step outside the prep and carry on.
 *
 * The move is played, it counts towards the score, and the drawn line stops
 * steering — from here the caller judges with the book instead of the prep.
 */
export function leavePrep(run: Run, san: string): Run {
  const move = applySan(run.fen, san);
  if (!move) return { ...run, over: true };
  return {
    ...run,
    fen: move.after,
    played: [...run.played, san],
    survived: run.survived + 1,
    leftPrep: true,
    target: [],
  };
}

/* ── extended mode ──────────────────────────────────────────────────────── */

/**
 * How much you may drop, in centipawns, before a move counts as a blunder.
 *
 * Generous on purpose. Past the prep there is no single right move, and a mode
 * that ends your run over a quarter of a pawn would be judging taste rather
 * than blunders.
 */
export const BLUNDER_LIMIT = 80;

/**
 * How much a move cost, in centipawns from your own point of view.
 *
 * Both scores come from the engine in White's frame: `before` is the position
 * you were about to move in, `after` the position you left behind. A positive
 * result means you gave something up.
 */
export function evalLoss(color: Color, before: number, after: number): number {
  return color === 'w' ? before - after : after - before;
}

export interface EvalVerdict {
  ok: boolean;
  /** Centipawns dropped. Never negative — finding better than the engine is not a loss. */
  lost: number;
}

/** Judge a move once the prep has run out. */
export function judgeByEval(
  color: Color,
  before: number,
  after: number,
  limit = BLUNDER_LIMIT,
): EvalVerdict {
  const lost = Math.max(0, evalLoss(color, before, after));
  return { ok: lost <= limit, lost };
}

/** Hand a run over to the engine: everything from here is judged on eval. */
export function extend(run: Run): Run {
  return run.prepEnded === null ? { ...run, prepEnded: run.played.length } : run;
}

/** True once the run is being judged by the engine rather than by the prep. */
export function isExtended(run: Run): boolean {
  return run.prepEnded !== null;
}

/**
 * Your own moves played past the end of the prep.
 *
 * Counted by whose ply each one is rather than from how many were played, since
 * the handover can happen on either side's turn: a line that ends on your move
 * leaves the opponent to move first, and their move is not one of yours.
 */
export function extendedMoves(run: Run): number {
  if (run.prepEnded === null) return 0;
  let mine = 0;
  for (let ply = run.prepEnded; ply < run.played.length; ply += 1) {
    if ((ply % 2 === 0) === (run.color === 'w')) mine += 1;
  }
  return mine;
}

/** Record one accepted move in extended play, with the opponent's reply. */
export function playExtended(run: Run, san: string, reply: string | null): Run {
  const sans = reply ? [san, reply] : [san];
  let fen = run.fen;
  for (const move of sans) {
    const applied = applySan(fen, move);
    if (!applied) return { ...run, over: true };
    fen = applied.after;
  }
  return {
    ...run,
    fen,
    played: [...run.played, ...sans],
    survived: run.survived + 1,
  };
}

/**
 * The opponent's move on its own, once the engine has chosen one.
 *
 * Extended play normally takes your move and their answer together, so this is
 * only for the turn that starts it: a line ends on a move of yours, which hands
 * the run to the engine with the opponent still to move. Their move earns
 * nothing — the score counts moves you survived.
 */
export function playExtendedReply(run: Run, san: string): Run {
  const applied = applySan(run.fen, san);
  if (!applied) return { ...run, over: true };
  return { ...run, fen: applied.after, played: [...run.played, san] };
}

/**
 * True when the prep has been played out with no mistake left to make.
 *
 * A run already handed to the engine is never complete this way: past the prep
 * there is always another move, and only a blunder or the game itself ends it.
 */
export function isComplete(source: LineSource, run: Run): boolean {
  return !run.over && !isExtended(run) && movesHere(source, run).length === 0;
}

/**
 * True at the edge of the prep: your move, nothing prepared, the book still
 * going. This is where a run completes, or — with moves left to add — where it
 * offers the book.
 *
 * Never once the prep has been left: from there the book judges every move
 * and nothing is added. And never for the engine: past the hand-over there is
 * no prep to be at the edge of.
 */
export function atEdge(source: LineSource, run: Run): boolean {
  if (run.over || run.leftPrep || isExtended(run) || !isUsersTurn(run)) return false;
  return source.prepAt(run.fen).length === 0 && movesHere(source, run).length > 0;
}

/** What to offer at the edge: the book's replies, most played first. */
export function edgeOptions(index: ReferenceIndex, fen: string, limit = 4) {
  return optionsAt(index, fen, limit);
}

/**
 * Take a move from the book at the edge of the prep.
 *
 * It is played and it spends one of the run's new moves, but it is not a move
 * you found, so it counts for nothing: the score is moves survived. The drawn
 * line stops steering — it led here and no further — and the opponent answers
 * from the book.
 */
export function chooseAtEdge(run: Run, san: string): Run {
  const move = applySan(run.fen, san);
  if (!move || run.newMoves <= 0) return { ...run, over: true };
  return {
    ...run,
    fen: move.after,
    played: [...run.played, san],
    newMoves: run.newMoves - 1,
    added: run.added + 1,
    target: [],
  };
}

/** How the line would have gone on from here. */
export function continuation(source: LineSource, run: Run, plies = 48): string[] {
  const out: string[] = [];
  let fen = run.fen;
  const played = [...run.played];
  for (let i = 0; i < plies; i += 1) {
    const onLine = run.target[played.length];
    const options = source.movesAt(fen, played);
    if (!options.length) break;
    const san = onLine && options.includes(onLine) ? onLine : options[0];
    const move = applySan(fen, san);
    if (!move) break;
    out.push(san);
    played.push(san);
    fen = move.after;
  }
  return out;
}

/** The secret line in full: what was reached, plus how it would have gone. */
export function fullLine(source: LineSource, run: Run, plies = 48): string[] {
  return [...run.played, ...continuation(source, run, plies)];
}

export function revealText(source: LineSource, run: Run): string {
  return sansToMoveText(fullLine(source, run));
}

export function playedIsLegal(run: Run): boolean {
  let fen = START_FEN;
  for (const san of run.played) {
    const move = applySan(fen, san);
    if (!move) return false;
    fen = move.after;
  }
  return true;
}

export interface LineName {
  name: string;
  eco?: string;
  /** False when the database only knew the opening in general terms. */
  specific: boolean;
}

/**
 * What to call the line once the run is over.
 *
 * The database names a position by the deepest entry on its path, so a line
 * that transposes into the King's Indian through an unusual move order can come
 * back as "Queen's Pawn Opening" — technically right and no use to anyone. When
 * the match is that shallow, fall back to the source's own name.
 *
 * Three plies is the cutoff because that is where a name starts saying more
 * than the first move: "Sicilian: Alapin" earns its place, "Sicilian Defence"
 * does not — and the fallback, the repertoire's own name, already beats it.
 */
export function lineName(
  index: ReferenceIndex,
  source: LineSource,
  run: Run,
  minPly = 3,
): LineName {
  const found = deepestName(index, fullLine(source, run));
  if (found && found.ply >= minPly) return { name: found.name, eco: found.eco, specific: true };
  return { name: run.sourceLabel, eco: found?.eco, specific: false };
}

/* ── record ─────────────────────────────────────────────────────────────── */

export interface OpeningRunRecord {
  runs: number;
  /** Deepest run, counted in the user's own correct moves. */
  best: number;
  lastDepth: number;
  lastAt: number | null;
  /** Runs that reached the end of the line. */
  survivals: number;
  /**
   * What the last logged run was, so a run carried on past its prep updates its
   * own entry instead of counting twice.
   */
  last?: { id: string; completed: boolean; grade?: RunGrade };
  /** How runs ended, counted by grade. */
  grades: Record<RunGrade, number>;
}

export const EMPTY_RECORD: OpeningRunRecord = {
  runs: 0,
  best: 0,
  lastDepth: 0,
  lastAt: null,
  survivals: 0,
  grades: { green: 0, yellow: 0, red: 0, purple: 0 },
};

/** A saved record missing a field is still a record. */
export function normalizeRecord(record: Partial<OpeningRunRecord> | undefined): OpeningRunRecord {
  if (!record) return { ...EMPTY_RECORD, grades: { ...EMPTY_RECORD.grades } };
  return {
    ...EMPTY_RECORD,
    ...record,
    grades: { ...EMPTY_RECORD.grades, ...(record.grades ?? {}) },
  };
}

export interface RunOutcome {
  /** The run this came from, so carrying a run on amends it. */
  id: string;
  grade: RunGrade;
  label: string;
  openingId: string;
  color: Color;
  depth: number;
  completed: boolean;
}

export function outcomeOf(run: Run, completed: boolean): RunOutcome {
  return {
    id: run.id,
    grade: gradeOf(run, completed),
    label: run.sourceLabel,
    openingId: run.openingId,
    color: run.color,
    depth: run.survived,
    completed,
  };
}

/**
 * Log a finished run.
 *
 * Logging the same run twice amends it rather than counting it again: a run that
 * reaches the end of its prep is logged there, and may then be carried on into
 * extended play and finish deeper. The count stays at one run and the deeper
 * score replaces the shallower one — `best` only ever grows, so taking the
 * maximum is right either way.
 *
 * Reaching the end of a line is a fact, so carrying the run on past it and
 * blundering does not unmake it: a completed line stays counted.
 */
export function recordRun(
  record: OpeningRunRecord,
  outcome: RunOutcome,
  at = Date.now(),
): OpeningRunRecord {
  const base = normalizeRecord(record);
  const amend = base.last?.id === outcome.id;
  const alreadyCounted = amend && !!base.last?.completed;
  const addSurvival = outcome.completed && !alreadyCounted ? 1 : 0;
  return {
    runs: base.runs + (amend ? 0 : 1),
    best: Math.max(base.best, outcome.depth),
    lastDepth: outcome.depth,
    lastAt: at,
    survivals: base.survivals + addSurvival,
    grades: amendGrades(base.grades, amend ? base.last?.grade : undefined, outcome.grade),
    last: {
      id: outcome.id,
      completed: outcome.completed || alreadyCounted,
      grade: outcome.grade,
    },
  };
}

/** Move a run's grade tally, taking back the grade it was last logged under. */
function amendGrades(
  grades: Record<RunGrade, number>,
  previous: RunGrade | undefined,
  next: RunGrade,
): Record<RunGrade, number> {
  const out = { ...grades };
  if (previous) out[previous] = Math.max(0, out[previous] - 1);
  out[next] += 1;
  return out;
}

/* ── keeping what you survived ──────────────────────────────────────────── */

/**
 * The part of a run worth writing into a repertoire.
 *
 * Only the moves that were actually correct, and only while the book was still
 * judging them: a run's `played` never contains the move that ended it, and
 * anything past `prepEnded` was passed by the engine rather than found in the
 * book, which makes it sound but not theory. The line is trimmed to end on your
 * own move, because one ending on the opponent's prepares nothing.
 */
export function lineToKeep(run: Run): string[] {
  const inBook = run.prepEnded ?? run.played.length;
  const cut = run.played.slice(0, Math.max(0, inBook));
  // White's moves sit at even indices, so a White line has odd length.
  const wantsOdd = run.color === 'w';
  if (!cut.length) return [];
  return cut.length % 2 === 1 === wantsOdd ? cut : cut.slice(0, -1);
}
