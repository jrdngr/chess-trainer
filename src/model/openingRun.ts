import {
  applySan,
  fenTurn,
  positionKey,
  sansToMoveText,
  START_FEN,
  type Color,
  type Square,
} from '../chess/core';
import {
  deepestName,
  lookup,
  openingById,
  type CatalogueEntry,
  type ReferenceIndex,
} from './reference';
import { childrenOf, displayName, fenAt, leafLines, pathTo } from './repertoire';
import { cardId, mulberry32 } from './session';
import type { Card, RepMove, Repertoire } from './types';

/**
 * OpeningRun: one secret line, played until the first mistake ends the run.
 *
 * Both modes run on the same engine. A `LineSource` answers two questions about
 * a position — which moves count as staying in, and how the opponent replies —
 * and everything else (judging, revealing, scoring) is shared. The repertoire
 * source asks whether you know your own prep; the book source asks whether you
 * can stay in theory at all.
 */
export type SourceKind = 'repertoire' | 'book' | 'opening';

export interface LineSource {
  kind: SourceKind;
  /** Named after the run, alongside the opening the line turned out to be. */
  label: string;
  color: Color;
  /** Moves that keep the run alive from this position, best first. */
  movesAt(fen: string): string[];
  /** Relative likelihood of each opponent reply. */
  weightsAt(fen: string): { san: string; weight: number }[];
}

export function other(color: Color): Color {
  return color === 'w' ? 'b' : 'w';
}

/* ── sources ────────────────────────────────────────────────────────────── */

/**
 * One repertoire, indexed by position so transpositions behave the way they do
 * in training: the same position reached two ways offers the same moves.
 *
 * Every position in the tree is indexed, the opponent's included — that is what
 * lets a reversed run judge the side you prepared *against*.
 */
export function repertoireSource(rep: Repertoire, index?: ReferenceIndex | null): LineSource {
  const byPosition = new Map<string, string[]>();
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

  const movesAt = (fen: string) => byPosition.get(positionKey(fen)) ?? [];
  return {
    kind: 'repertoire',
    label: displayName(rep.name),
    color: rep.color,
    movesAt,
    weightsAt: (fen) => {
      const sans = movesAt(fen);
      if (!index || sans.length < 2) return sans.map((san) => ({ san, weight: 1 }));
      const games = new Map((lookup(index, fen)?.moves ?? []).map((m) => [m.san, m.games]));
      const total = [...games.values()].reduce((sum, n) => sum + n, 0);
      // A prepared move nobody in the database plays still deserves a turn, just
      // a rare one: the floor keeps sidelines in the rotation without letting
      // them crowd out the move orders you will actually meet.
      const floor = Math.max(1, total * SIDELINE_FLOOR);
      return sans.map((san) => ({ san, weight: Math.max(floor, games.get(san) ?? 0) }));
    },
  };
}

/** The least often a prepared sideline may be chosen, as a share of the position. */
const SIDELINE_FLOOR = 0.01;

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

/**
 * The whole reference database. Staying in book means playing a move somebody
 * has actually played here; the opponent answers in proportion to how often
 * each reply is played.
 */
export function bookSource(index: ReferenceIndex, color: Color): LineSource {
  const entryMoves = (fen: string) => lookup(index, fen)?.moves ?? [];
  return {
    kind: 'book',
    label: 'Book',
    color,
    movesAt: (fen) => [...entryMoves(fen)].sort((a, b) => b.games - a.games).map((m) => m.san),
    weightsAt: (fen) => entryMoves(fen).map((m) => ({ san: m.san, weight: Math.max(1, m.games) })),
  };
}

/**
 * One named opening, then the book.
 *
 * While the run is still inside the opening's move order, that move order is the
 * only thing that counts — for both sides, because it is what makes the opening
 * that opening. Past the end of it the book takes over and anything played in
 * the database keeps you alive.
 */
export function openingSource(
  index: ReferenceIndex,
  opening: CatalogueEntry,
  color: Color,
): LineSource {
  const book = bookSource(index, color);
  const forced = new Map<string, string>();
  let fen = START_FEN;
  for (const san of opening.sans) {
    const move = applySan(fen, san);
    if (!move) break;
    forced.set(positionKey(fen), san);
    fen = move.after;
  }
  const onPath = (at: string) => forced.get(positionKey(at));
  return {
    kind: 'opening',
    label: opening.name,
    color,
    movesAt: (at) => {
      const only = onPath(at);
      return only ? [only] : book.movesAt(at);
    },
    weightsAt: (at) => {
      const only = onPath(at);
      return only ? [{ san: only, weight: 1 }] : book.weightsAt(at);
    },
  };
}

/* ── options ────────────────────────────────────────────────────────────── */

export type ColorChoice = Color | 'random';

/** How long you get, and whether the budget is per move or per run. */
export type ClockMode = 'off' | 'move10' | 'move30' | 'run180';

export interface ClockSpec {
  /** Seconds for each of your own moves, or null. */
  perMove: number | null;
  /** Seconds for the whole run, or null. */
  perRun: number | null;
}

export const CLOCK_MODES: ClockMode[] = ['off', 'move10', 'move30', 'run180'];

export function clockSpec(mode: ClockMode): ClockSpec {
  switch (mode) {
    case 'move10':
      return { perMove: 10, perRun: null };
    case 'move30':
      return { perMove: 30, perRun: null };
    case 'run180':
      return { perMove: null, perRun: 180 };
    default:
      return { perMove: null, perRun: null };
  }
}

export function clockLabel(mode: ClockMode): string {
  switch (mode) {
    case 'move10':
      return '10s';
    case 'move30':
      return '30s';
    case 'run180':
      return '3 min';
    default:
      return 'Off';
  }
}

export function clockDescription(mode: ClockMode): string {
  switch (mode) {
    case 'move10':
      return '10 seconds for each of your moves. Running out ends the run.';
    case 'move30':
      return '30 seconds for each of your moves. Running out ends the run.';
    case 'run180':
      return 'Three minutes for the whole run, counting only your own thinking.';
    default:
      return 'Take as long as you like.';
  }
}

export const HINT_BUDGETS = [0, 1, 3];

/** Everything the setup screen decides, in one place. */
export interface OpeningRunOptions {
  kind: SourceKind;
  color: ColorChoice;
  /** A single repertoire to draw from, or '' for every one that fits. */
  repertoireId: string;
  /** The named opening to run through, for the opening source. */
  openingId: string;
  /** Play the side your repertoire prepares *against*. */
  reverse: boolean;
  /** Draw lines you answer badly more often than lines you know cold. */
  weakFirst: boolean;
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
  kind: 'repertoire',
  color: 'random',
  repertoireId: '',
  openingId: '',
  reverse: false,
  weakFirst: false,
  clock: 'off',
  hints: 0,
  extended: false,
};

/** What the setup screen remembers between runs: the options, plus how the record is shown. */
export interface OpeningRunPrefs extends OpeningRunOptions {
  /** Break the record down by opening and side. */
  perLine: boolean;
}

export const DEFAULT_PREFS: OpeningRunPrefs = { ...DEFAULT_OPTIONS, perLine: false };

/**
 * Does this source produce lines worth offering to keep?
 *
 * A repertoire run is already playing your own lines back at you, so there is
 * nothing there to save.
 */
export function canKeepLine(kind: SourceKind): boolean {
  return kind === 'opening' || kind === 'book';
}

/* ── runs ───────────────────────────────────────────────────────────────── */

export interface Run {
  /** Distinguishes one run from the next, so a run can be amended in place. */
  id: string;
  source: SourceKind;
  sourceLabel: string;
  /** Which repertoire the line came from, for repertoire runs. */
  repertoireId?: string;
  /** Which named opening was chosen, for opening runs. */
  openingId?: string;
  /** True when you are playing the side the repertoire prepares against. */
  reverse: boolean;
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

export interface RunOptions {
  /** Skip lines that ask fewer than this many moves of the user. */
  minDecisions?: number;
  seed?: number;
  /** Draw only from this repertoire. */
  repertoireId?: string;
  reverse?: boolean;
  /** Positions you answer badly, scored — see `weaknessFromCards`. */
  weakness?: Weakness | null;
  hints?: number;
  /**
   * Reference data, used to draw realistic move orders. Without it every leaf
   * line is equally likely, which quizzes you on your thinnest sidelines as
   * often as on the lines you will actually face.
   */
  index?: ReferenceIndex | null;
}

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
export function weaknessFromCards(cards: Record<string, Card>, now = Date.now()): Weakness {
  return (repertoireId, key) => {
    const card = cards[cardId(repertoireId, key)];
    // Never studied: worth seeing, but not the emergency a lapse is.
    if (!card) return 1.5;
    let score = 1;
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

export interface PoolOptions {
  reverse?: boolean;
  repertoireId?: string;
}

/**
 * Repertoires that can host a run for this colour.
 *
 * A reversed run sits you on the other side of the board, so it needs a
 * repertoire of the opposite colour to the one you asked to play.
 */
export function playableRepertoires(
  reps: Repertoire[],
  color: ColorChoice,
  opts: PoolOptions = {},
): Repertoire[] {
  const wanted = color === 'random' ? null : opts.reverse ? other(color) : color;
  return reps.filter(
    (rep) =>
      (wanted === null || rep.color === wanted) &&
      (!opts.repertoireId || rep.id === opts.repertoireId),
  );
}

/**
 * Start a run from a repertoire. The line drawn up front only decides the
 * opponent's replies; any prepared move is accepted at your own turn.
 */
export function startRepertoireRun(
  reps: Repertoire[],
  color: ColorChoice,
  opts: RunOptions = {},
): Run | null {
  const minDecisions = opts.minDecisions ?? 4;
  const reverse = opts.reverse ?? false;
  const rand = mulberry32(opts.seed ?? Math.floor(Math.random() * 2 ** 31));

  const weakness = opts.weakness ?? null;
  const candidates = playableRepertoires(reps, color, {
    reverse,
    repertoireId: opts.repertoireId,
  })
    .map((rep) => {
      const side = reverse ? other(rep.color) : rep.color;
      const usable = leafLines(rep)
        .map((line) => {
          const path = pathTo(rep, line.tipId);
          return { tipId: line.tipId, path, keys: yourMoves(side, path).map((n) => n.key) };
        })
        .filter((line) => line.keys.length >= minDecisions);
      const odds = lineOdds(rep, side, opts.index, new Set(usable.map((l) => l.tipId)));
      const even = odds.size === 0;
      const lines = usable.map((line) => ({
        path: line.path,
        keys: line.keys,
        weight:
          (even ? 1 : (odds.get(line.tipId) ?? 0)) *
          (weakness ? lineWeakness(rep.id, line.keys, weakness) : 1),
      }));
      return { rep, side, lines };
    })
    .filter((c) => c.lines.length > 0);
  if (!candidates.length) return null;

  // Repertoire first and evenly, so a big one cannot crowd out the others
  // however popular its lines are; the line within it is drawn on its odds.
  const picked = candidates[Math.floor(rand() * candidates.length)];
  const line = pickWeighted(picked.lines, (l) => l.weight, rand);

  return {
    id: newRunId(),
    source: 'repertoire',
    sourceLabel: displayName(picked.rep.name),
    repertoireId: picked.rep.id,
    reverse,
    leftPrep: false,
    color: picked.side,
    fen: START_FEN,
    played: [],
    survived: 0,
    over: false,
    target: line.path.map((n) => n.san),
    hints: opts.hints ?? 0,
    hintsUsed: 0,
    prepEnded: null,
  };
}

/** Start a run in the book. There is no line to draw: the book is the line. */
export function startBookRun(
  index: ReferenceIndex,
  color: ColorChoice,
  opts: RunOptions = {},
): Run | null {
  const rand = mulberry32(opts.seed ?? Math.floor(Math.random() * 2 ** 31));
  const side = resolveColor(color, rand);
  if (!lookup(index, START_FEN)?.moves.length) return null;
  return {
    id: newRunId(),
    source: 'book',
    sourceLabel: 'Book',
    reverse: false,
    leftPrep: false,
    color: side,
    fen: START_FEN,
    played: [],
    survived: 0,
    over: false,
    target: [],
    hints: opts.hints ?? 0,
    hintsUsed: 0,
    prepEnded: null,
  };
}

/**
 * Start a run through a named opening. The opening's own move order is the
 * target, so the opponent walks you into it before the book takes over.
 */
export function startOpeningRun(
  index: ReferenceIndex,
  opening: CatalogueEntry,
  color: ColorChoice,
  opts: RunOptions = {},
): Run | null {
  const rand = mulberry32(opts.seed ?? Math.floor(Math.random() * 2 ** 31));
  const side = resolveColor(color, rand);
  if (!lookup(index, START_FEN)?.moves.length) return null;
  return {
    id: newRunId(),
    source: 'opening',
    sourceLabel: opening.name,
    openingId: opening.id,
    reverse: false,
    leftPrep: false,
    color: side,
    fen: START_FEN,
    played: [],
    survived: 0,
    over: false,
    target: opening.sans,
    hints: opts.hints ?? 0,
    hintsUsed: 0,
    prepEnded: null,
  };
}

/** Resolve "random" once, up front, so the rest of a run is deterministic. */
export function resolveColor(color: ColorChoice, rand: () => number): Color {
  return color === 'random' ? (rand() < 0.5 ? 'w' : 'b') : color;
}

export function isUsersTurn(run: Run): boolean {
  return fenTurn(run.fen) === run.color;
}

export function movesHere(source: LineSource, run: Run): string[] {
  return source.movesAt(run.fen);
}

export type Judgement =
  | { ok: true; run: Run; san: string }
  | { ok: false; run: Run; played: string; expected: string[] };

/** Judge one move by the user. A move outside the source ends the run. */
export function play(source: LineSource, run: Run, san: string): Judgement {
  const options = source.movesAt(run.fen);
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

/** The clock running out. Ends the run where it stands, with nothing played. */
export function timeOut(run: Run): Run {
  return { ...run, over: true };
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
  const best = source.movesAt(run.fen)[0];
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
  const options = source.weightsAt(run.fen);
  if (!options.length) return { ...run, over: true };

  let san = onLine && options.some((o) => o.san === onLine) ? onLine : null;
  if (!san) {
    // Prefer replies the source can still answer, so a run does not dead-end
    // on the opponent's move when a real continuation exists.
    const live = options.filter((o) => {
      const move = applySan(run.fen, o.san);
      return move ? source.movesAt(move.after).length > 0 : false;
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

/** Your own moves played past the end of the prep. */
export function extendedMoves(run: Run): number {
  if (run.prepEnded === null) return 0;
  const past = run.played.length - run.prepEnded;
  return Math.max(0, Math.ceil(past / 2));
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
 * True when the prep has been played out with no mistake left to make.
 *
 * A run already handed to the engine is never complete this way: past the prep
 * there is always another move, and only a blunder or the game itself ends it.
 */
export function isComplete(source: LineSource, run: Run): boolean {
  return !run.over && !isExtended(run) && source.movesAt(run.fen).length === 0;
}

/** How the line would have gone on from here. */
export function continuation(source: LineSource, run: Run, plies = 48): string[] {
  const out: string[] = [];
  let fen = run.fen;
  let index = run.played.length;
  for (let i = 0; i < plies; i += 1) {
    const onLine = run.target[index];
    const options = source.movesAt(fen);
    if (!options.length) break;
    const san = onLine && options.includes(onLine) ? onLine : options[0];
    const move = applySan(fen, san);
    if (!move) break;
    out.push(san);
    fen = move.after;
    index += 1;
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

/* ── starting a run ─────────────────────────────────────────────────────── */

export interface BeginOptions extends Partial<OpeningRunOptions> {
  reps: Repertoire[];
  index: ReferenceIndex;
  seed?: number;
  minDecisions?: number;
  weakness?: Weakness | null;
}

/** Everything a run needs, or null when the options cannot produce one. */
export function beginRun(opts: BeginOptions): { source: LineSource; run: Run } | null {
  const kind = opts.kind ?? DEFAULT_OPTIONS.kind;
  const color = opts.color ?? DEFAULT_OPTIONS.color;
  const hints = opts.hints ?? DEFAULT_OPTIONS.hints;

  if (kind === 'opening') {
    const opening = openingById(opts.index, opts.openingId ?? '');
    if (!opening) return null;
    const run = startOpeningRun(opts.index, opening, color, { seed: opts.seed, hints });
    return run ? { run, source: openingSource(opts.index, opening, run.color) } : null;
  }
  if (kind === 'book') {
    const run = startBookRun(opts.index, color, { seed: opts.seed, hints });
    return run ? { run, source: bookSource(opts.index, run.color) } : null;
  }
  const run = startRepertoireRun(opts.reps, color, {
    seed: opts.seed,
    minDecisions: opts.minDecisions,
    repertoireId: opts.repertoireId,
    reverse: opts.reverse,
    weakness: opts.weakFirst ? (opts.weakness ?? null) : null,
    hints,
    index: opts.index,
  });
  if (!run) return null;
  const rep = opts.reps.find((r) => r.id === run.repertoireId);
  return rep ? { run, source: repertoireSource(rep, opts.index) } : null;
}

/* ── record ─────────────────────────────────────────────────────────────── */

/** A running total for one opening, on one side of the board. */
export interface LineRecord {
  label: string;
  color: Color;
  runs: number;
  best: number;
  survivals: number;
  lastAt: number;
}

export interface OpeningRunRecord {
  runs: number;
  /** Deepest run, counted in the user's own correct moves. */
  best: number;
  lastDepth: number;
  lastAt: number | null;
  /** Runs that reached the end of the line. */
  survivals: number;
  /** Per opening and side, so a Sicilian best does not hide behind a KID one. */
  byLine: Record<string, LineRecord>;
  /**
   * What the last logged run was, so a run carried on past its prep updates its
   * own entry instead of counting twice.
   */
  last?: { id: string; key: string; completed: boolean; grade?: RunGrade };
  /** How runs ended, counted by grade. */
  grades: Record<RunGrade, number>;
}

export const EMPTY_RECORD: OpeningRunRecord = {
  runs: 0,
  best: 0,
  lastDepth: 0,
  lastAt: null,
  survivals: 0,
  byLine: {},
  grades: { green: 0, yellow: 0, red: 0, purple: 0 },
};

/** A saved record from before per-opening bests existed is still a record. */
export function normalizeRecord(record: Partial<OpeningRunRecord> | undefined): OpeningRunRecord {
  if (!record) return { ...EMPTY_RECORD, grades: { ...EMPTY_RECORD.grades } };
  return {
    ...EMPTY_RECORD,
    ...record,
    byLine: record.byLine ?? {},
    grades: { ...EMPTY_RECORD.grades, ...(record.grades ?? {}) },
  };
}

export interface RunOutcome {
  /** The run this came from, so carrying a run on amends it. */
  id: string;
  key: string;
  grade: RunGrade;
  label: string;
  color: Color;
  depth: number;
  completed: boolean;
}

/** Which bucket a run counts towards: the opening, and the side you played. */
export function outcomeOf(run: Run, completed: boolean): RunOutcome {
  const key =
    run.source === 'book'
      ? `book:${run.color}`
      : run.source === 'opening'
        ? `opening:${run.openingId ?? ''}:${run.color}`
        : `rep:${run.repertoireId ?? ''}:${run.color}`;
  return {
    id: run.id,
    key,
    grade: gradeOf(run, completed),
    label: run.reverse ? `${run.sourceLabel} (reversed)` : run.sourceLabel,
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
  const amend = base.last?.id === outcome.id && base.last.key === outcome.key;
  const alreadyCounted = amend && !!base.last?.completed;
  const addSurvival = outcome.completed && !alreadyCounted ? 1 : 0;
  const previous = base.byLine[outcome.key];
  return {
    runs: base.runs + (amend ? 0 : 1),
    best: Math.max(base.best, outcome.depth),
    lastDepth: outcome.depth,
    lastAt: at,
    survivals: base.survivals + addSurvival,
    grades: amendGrades(base.grades, amend ? base.last?.grade : undefined, outcome.grade),
    last: {
      id: outcome.id,
      key: outcome.key,
      completed: outcome.completed || alreadyCounted,
      grade: outcome.grade,
    },
    byLine: {
      ...base.byLine,
      [outcome.key]: {
        label: outcome.label,
        color: outcome.color,
        runs: (previous?.runs ?? 0) + (amend ? 0 : 1),
        best: Math.max(previous?.best ?? 0, outcome.depth),
        survivals: (previous?.survivals ?? 0) + addSurvival,
        lastAt: at,
      },
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

/** Per-opening records, deepest first — what the breakdown shows. */
export function lineRecords(record: OpeningRunRecord): (LineRecord & { key: string })[] {
  return Object.entries(normalizeRecord(record).byLine)
    .map(([key, value]) => ({ ...value, key }))
    .sort((a, b) => b.best - a.best || b.runs - a.runs);
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
