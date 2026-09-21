import {
  applySan,
  fenTurn,
  positionKey,
  sansToMoveText,
  START_FEN,
  walkSan,
  type Color,
  type Square,
} from '../chess/core';
import { findHoles, movesToFit, optionsAt, type Hole } from './growth';
import { deepestName, lookup, type ReferenceIndex } from './reference';
import {
  approachKeys,
  insideRegion,
  lineStatus,
  regionOf,
  type OpeningNode,
  type OpeningTree,
} from './openingTree';
import type { RepairItem } from './repair';
import { justRun, keysAlong, lineStaleness, NOTHING_SEEN, staleness, type Seen } from './freshness';
import { childrenOf, fenAt, leafLines, pathTo } from './repertoire';
import { cardId, mulberry32 } from './session';
import type { Card, RepMove, Repertoire } from './types';

/**
 * Run: the opening of a game, drilled against your prep.
 *
 * A run lives inside a region of the opening tree — the whole book, one first
 * move, a family, or a single variation. While your prep has a move for the
 * position, your prep is the referee: a prepared move is correct, and anything
 * else is handed to the engine. A move the engine calls a blunder ends the
 * round; one it calls sound is a *checkpoint* — you have left your prep, and
 * the choice is yours to keep playing or start a new round. The end of your
 * prep is a checkpoint too. Past a checkpoint the engine judges every move,
 * the opponent plays the book by popularity while the book lasts, and nothing
 * ends the game but a blunder, mate or a draw.
 *
 * The opponent replies in proportion to how often each move is played, but
 * only with moves that keep the game inside the region; on the way in, only
 * moves the book can still get there from. Where nothing of yours passes
 * through the region at all the book is the referee instead — a run through
 * the book — until the book runs out.
 *
 * Nothing is written into the repertoire by a run. The reveal offers the line
 * to keep, and keeping it is one tap.
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
 * How many moves are worth adding at a hole this far into a line.
 *
 * Lives with the holes it measures, in `growth`, since Growth answers them a
 * batch at a time by the same rule; re-exported here because a run's budget
 * at the edge of the prep is where it was first needed.
 */
export { movesToFit } from './growth';

/**
 * How much less often a hole may be met than the best one and still be drawn.
 *
 * Without a window the draw is proportional, and a reply played one game in a
 * hundred comes up one round in a hundred — which is fair and still wrong,
 * because those rounds are spent on a move you will not meet while the move
 * you meet in four games in ten goes unanswered. So the field is the holes
 * worth a real fraction of the best one, and the rest wait.
 *
 * They do not wait for ever: answering the top hole takes it out of the
 * reckoning, the best of what is left is worth less, and the window comes
 * down to meet the next tier. The common replies are covered first and the
 * obscure ones arrive when there is nothing commoner left to do.
 */
export const DRAW_WINDOW = 8;

/**
 * What the setup screen decides. The colour and the opening are global and
 * live in the selection, not here.
 */
export interface OpeningRunOptions {
  steer: Steer;
  /**
   * Moves the run may add. Where your prep runs out — on your move, with the
   * book still going — the book's replies are offered and the one you choose
   * is written into the repertoire; with none left the end of the prep is a
   * checkpoint instead. The one way a run writes anything while it is live,
   * and it is chosen up front.
   */
  newMoves: number;
  clock: ClockMode;
  hints: number;
}

export const DEFAULT_OPTIONS: OpeningRunOptions = {
  steer: 'popular',
  newMoves: 0,
  clock: 'off',
  hints: 0,
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
   * True once the run has stepped outside its prep and carried on. The run is
   * graded as an out-of-prep one however it ends.
   */
  leftPrep: boolean;
  /**
   * True when nothing of yours passes through the region: the book is the
   * referee, and the run is a walk through it. Reaching the end of the book
   * is the checkpoint, not the end of the prep, because there is none.
   */
  bookRun: boolean;
  /**
   * True once the engine is the referee — chosen at a checkpoint, never
   * automatic. From here the opponent plays the book while it lasts, then
   * the engine, and only a blunder, mate or a draw ends the game.
   */
  extended: boolean;
  /**
   * How many plies had been played when the referee handed over to the
   * engine, or null while it has not. Everything from here was passed by the
   * engine rather than found in your prep or the book.
   */
  handOver: number | null;
  /** Your own moves past the hand-over, judged by the engine. They earn nothing. */
  past: number;
  color: Color;
  fen: string;
  played: string[];
  /** The user's correct moves so far — the score. */
  survived: number;
  over: boolean;
  /** Remaining moves of the line drawn, driving opponent replies. */
  target: string[];
  /**
   * The line drawn, kept whole. `target` is spent as the run goes and
   * cleared when you step off it; this is the record of what the round was
   * about, for the rounds after it not to be. Redrawn along with the target
   * when the run is steered again from a new position.
   */
  drawn: string[];
  /**
   * How many plies were played for you before the run began: the way into
   * the opening a round starts inside. Zero for a run from move one. They
   * are on the board and in `played`, earn nothing, and are shown dimmed.
   */
  opened: number;
  /**
   * The opening the run was started inside — an opening tree node id — or
   * null for a run from move one. What the run is called on screen: a run
   * started in the Caro-Kann is a Caro-Kann run, whatever region it was
   * drawn in.
   */
  enteredIn: string | null;
  /**
   * How many plies had been played when the referee ran out — the end of
   * your prep, or of the book on a run through it — or null while it has
   * not. Reaching it is what completes a run, whatever happens after.
   */
  prepDone: number | null;
  /** Hints left to spend. */
  hints: number;
  /** Hints spent, shown on the reveal so a deep run stays honest. */
  hintsUsed: number;
  /** Moves the run may still add at the edge of the prep. */
  newMoves: number;
  /** Moves it has added. */
  added: number;
}

/**
 * How a run ended short of finishing: on a blunder, or stopped at a
 * checkpoint after a move off your prep. The latter is kept apart because
 * the move that ended it was sound — it just was not yours.
 */
export type DeathCause = 'blunder' | 'offprep';

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

  /** How much more a hole is worth for the games you have lost in it — see `evidenceFor`. */
  holeWeight?: (hole: Hole) => number;
  /** What the last few rounds were about, so this one is drawn on what they were not. */
  seen?: Seen;
  /**
   * Start inside the opening walked toward rather than from move one: the
   * drawn line's way in is played onto the board before the run begins. Only
   * a family or deeper is worth entering; a first move is left alone.
   */
  enter?: boolean;
}

/**
 * A run, and how to steer it again.
 *
 * `redraw` draws a new line from wherever the run has got to, by the same
 * steer the run began on — one of your lines through the position, your
 * weakest, or the walk to the nearest hole — and returns the run with its
 * target set. Unchanged where nothing of yours passes through the position,
 * which is where the opponent falls back to the book. Only while the run is
 * still inside its prep: once you have left it the drill is over, and the
 * opponent plays the book rather than walking you back.
 */
export interface Begun {
  source: LineSource;
  run: Run;
  redraw: (run: Run) => Run;
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
 * Among your own lines, the one that has been left longest is preferred, and
 * the one the last round was drawn on is not drawn at all while there is any
 * other — see `freshness.ts`.
 *
 * Null only when the book is empty, which it never is.
 */
export function beginRun(opts: BeginOptions): Begun | null {
  const rand = mulberry32(opts.seed ?? Math.floor(Math.random() * 2 ** 31));
  const side = resolveColor(opts.color, rand);
  const { tree, node } = opts;
  if (!lookup(tree.index, START_FEN)?.moves.length) return null;
  const rep = opts.reps.find((r) => r.color === side) ?? null;
  const source = regionSource(tree, node, rep, side);
  const aim = opts.toward ?? node;
  const steer = opts.steer ?? DEFAULT_OPTIONS.steer;

  /**
   * Draw a line from a position: the whole line from the start, the moves
   * played so far first. At the start it is the line the round is about;
   * later it is how the round follows you once you have stepped off it.
   */
  const draw = (at: At): Drawn => {
    const atStart = at.played.length === 0;
    // With nothing of yours to draw on, the opening's own move order, while
    // the moves played are still on it.
    const onWay = aim.sans.length > at.played.length && at.played.every((san, i) => aim.sans[i] === san);
    const fallback = onWay ? aim.sans : [];
    const through = rep ? linesThrough(rep, tree, aim, side, at) : [];
    // An opening with nothing of yours in it yet is entered by its own move
    // order, not by whichever hole on the way in is met most often: a player
    // who chose the Sämisch plays 1.d4, and the line they are about to build
    // should be the one the opening is named by. The budget is the opening's
    // own — the moves it takes to get there past the prep are not charged.
    const firstLine = rep !== null && steer === 'gaps' && atStart && through.length === 0 && aim.depth > 0;
    const gap = rep && steer === 'gaps' && !firstLine ? drawHole(rep, tree, aim, opts, rand, at) : null;
    if (gap) return { target: [...at.played, ...gap.rest], gap: gap.hole, firstLine };
    if (!rep || firstLine || !through.length) return { target: fallback, gap: null, firstLine };
    const minDecisions = opts.minDecisions ?? 4;
    const weakness = steer === 'weak' ? (opts.weakness ?? null) : null;
    // Long enough to be a game where there are such lines; anything at all
    // where there are not — a thin region is still yours to play.
    const long = through.filter((line) => line.keys.length >= minDecisions);
    const usable = long.length ? long : through;
    // Never the same line twice running, while there is another to run.
    const seen = opts.seen ?? NOTHING_SEEN;
    const rested = usable.filter((line) => !justRun(seen, rep, line.tipId));
    const field = rested.length ? rested : usable;
    const odds = lineOdds(rep, side, tree.index, new Set(field.map((l) => l.tipId)));
    const even = odds.size === 0;
    const line = pickWeighted(
      field,
      (l) =>
        (even ? 1 : (odds.get(l.tipId) ?? 0)) *
        (weakness ? lineWeakness(rep.id, l.keys, weakness) : 1) *
        Math.max(lineStaleness(seen, rep, l.tipId), 0.02),
      rand,
    );
    return { target: line.sans, gap: null, firstLine };
  };

  const first = draw({ fen: START_FEN, played: [] });
  // A round started inside the opening: the drawn line's way in is played
  // for you, up to the first position the opening names.
  const way = opts.enter && aim.depth >= 2 ? wayIn(tree, aim, first.target) : [];
  const entered = walkSan(way);
  const opened = entered.moves.length === way.length ? way.length : 0;
  const fen = entered.fens[opened] ?? START_FEN;

  /** What the round may add: the allowance, fitted to the line it walks. */
  const budgetFor = (): number => {
    const allowance = Math.max(0, opts.newMoves ?? DEFAULT_OPTIONS.newMoves);
    const maxPly = opts.growth?.maxPly;
    if (first.gap) return Math.min(allowance, movesToFit(first.gap.path.length, maxPly));
    if (!first.firstLine) return allowance;
    // The way in, where it was not played for you, is yours to choose at the
    // edge one move at a time, and none of it is the opening: it is not
    // charged against the budget.
    let at = START_FEN;
    let onWay = 0;
    for (const san of aim.sans.slice(opened)) {
      if (fenTurn(at) === side && !source.prepAt(at).includes(san)) onWay += 1;
      at = applySan(at, san)?.after ?? at;
    }
    return onWay + Math.min(allowance, movesToFit(aim.sans.length, maxPly));
  };

  const run: Run = {
    id: newRunId(),
    sourceLabel: opened > 0 ? aim.name : node.name,
    openingId: node.id,
    repertoireId: rep?.id,
    leftPrep: false,
    // Nothing of yours through the region makes this a walk through the
    // book — a first line built by playing it, if the reveal's offer is
    // taken — rather than a drill with nothing to drill.
    bookRun: !rep || linesThrough(rep, tree, aim, side, { fen: START_FEN, played: [] }).length === 0,
    extended: false,
    handOver: null,
    past: 0,
    color: side,
    fen,
    played: way.slice(0, opened),
    survived: 0,
    over: false,
    target: first.target,
    drawn: first.target,
    opened,
    enteredIn: opened > 0 ? aim.id : null,
    prepDone: null,
    hints: opts.hints ?? DEFAULT_OPTIONS.hints,
    hintsUsed: 0,
    // The budget is what the round may spend; the line decides what it needs.
    newMoves: budgetFor(),
    added: 0,
  };

  const redraw = (current: Run): Run => {
    if (current.leftPrep || current.extended) return current;
    const next = draw({ fen: current.fen, played: current.played });
    if (next.target.length <= current.played.length) return current;
    return { ...current, target: next.target, drawn: next.target };
  };

  return { source, run, redraw };
}

/** A position a line is drawn from: where the run has got to. */
interface At {
  fen: string;
  played: string[];
}

interface Drawn {
  /** The whole line from the start, or empty where there is nothing to walk. */
  target: string[];
  gap: Hole | null;
  /** True when the round builds an opening's first line by its own move order. */
  firstLine: boolean;
}

/**
 * Your lines through the opening that pass through a position, each as the
 * whole line with the moves played so far first, and the positions it will
 * still ask you about. A line reached by a transposition counts: what
 * matters is the position, not the road to it.
 */
function linesThrough(
  rep: Repertoire,
  tree: OpeningTree,
  aim: OpeningNode,
  side: Color,
  at: At,
): { tipId: string; sans: string[]; keys: string[] }[] {
  const key = positionKey(at.fen);
  const out: { tipId: string; sans: string[]; keys: string[] }[] = [];
  for (const line of leafLines(rep)) {
    if (lineStatus(tree, aim, line.sans) !== 'reached') continue;
    const path = pathTo(rep, line.tipId);
    // A move's key is the position it is played from, so the node found is
    // the next move of the line from here.
    const from = path.findIndex((move) => move.key === key);
    if (from < 0) continue;
    const rest = path.slice(from);
    out.push({
      tipId: line.tipId,
      sans: [...at.played, ...rest.map((move) => move.san)],
      keys: yourMoves(side, rest).map((move) => move.key),
    });
  }
  return out;
}

/**
 * The way into an opening along a line: its moves up to and including the
 * first that reaches a position the opening names. Empty when the line never
 * gets there, in which case there is nowhere to start but move one.
 */
export function wayIn(tree: OpeningTree, aim: OpeningNode, sans: string[]): string[] {
  if (aim.depth === 0) return [];
  const { inside } = regionOf(tree, aim);
  let fen = START_FEN;
  for (let i = 0; i < sans.length; i += 1) {
    const move = applySan(fen, sans[i]);
    if (!move) return [];
    fen = move.after;
    if (inside.has(positionKey(fen))) return sans.slice(0, i + 1);
  }
  return [];
}

/**
 * The hole to walk toward: one inside the opening while there is any, drawn
 * on how often you would actually meet it, and on what your own games say
 * about it. Null where the prep has no holes in the region past the
 * position, and the run falls back to a line through it.
 *
 * How often you would meet it is the reply's share of the position times the
 * share of games that get to the position at all — nothing else. That one
 * number is what orders the work: an unanswered 1.e4 is met in four games in
 * ten, a sideline at the same position in one game in a hundred, the tip of a
 * line you reach one game in twenty in less than that. So the common replies
 * are covered first and the obscure ones wait their turn, which is also what
 * makes a repertoire wider: the moves most often played against you are the
 * ones you have not met, not the next move of the line you already know.
 *
 * Then by how much of the round would be new. A round at a gap is the walk to
 * the hole and the moves added past it; the walk was just played if the last
 * round was drawn on the same line, and a hole at the tip of that line is
 * that whole round again with one move on the end. A hole at an earlier
 * junction shares the walk and none of what follows. Read off the same
 * stamps the line draw reads, with the added moves counted as new, and
 * squared, because a round a tenth new is not a tenth as good as a new one
 * — so a young repertoire branches early rather than deepening the one line
 * it has, and a mature one, whose walks were not just played, is free to
 * deepen.
 *
 * Drawn rather than taken in order, so the rounds are not the same round
 * twice — but drawn from the holes worth a real fraction of the best one, so
 * a reply nobody plays is not what a round is spent on while a reply everyone
 * plays goes unanswered. See `DRAW_WINDOW`.
 *
 * Drawn from a position, only the holes past it: the run has got this far
 * and walks on from here.
 */
function drawHole(
  rep: Repertoire,
  tree: OpeningTree,
  aim: OpeningNode,
  opts: BeginOptions,
  rand: () => number,
  at: At,
): { hole: Hole; rest: string[] } | null {
  const key = positionKey(at.fen);
  const found = findHoles(rep, tree.index, { ...opts.growth, region: { tree, node: aim } })
    .map((hole) => {
      // The walk to the hole from here: the rest of its path past this
      // position, then the reply itself.
      const from = at.played.length === 0 ? 0 : keysAlong(hole.path).indexOf(key) + 1;
      if (at.played.length > 0 && from === 0) return null;
      return { hole, rest: [...hole.path.slice(from), hole.san] };
    })
    .filter((x): x is { hole: Hole; rest: string[] } => x !== null);
  if (!found.length) return null;
  // Inside the opening before on the way to it. A hole on the way in — 1.c4,
  // met in every game, on its way to the Sämisch by transposition — is met
  // far more often than anything inside, and would take every round from
  // the opening the player actually chose. The way in is walked to only
  // once there is nothing left inside to answer.
  const inside = found.filter(({ hole }) => lineStatus(tree, aim, [...hole.path, hole.san]) === 'reached');
  const holes = inside.length ? inside : found;
  const evidence = opts.holeWeight ?? (() => 1);
  const seen = opts.seen ?? NOTHING_SEEN;
  const fresh = (hole: Hole) => {
    const walk = keysAlong(hole.path).map((k) => staleness(seen, k));
    const added = 2 * movesToFit(hole.path.length, opts.growth?.maxPly);
    return ((walk.reduce((sum, s) => sum + s, 0) + added) / (walk.length + added)) ** 2;
  };
  const met = ({ hole }: { hole: Hole }) => hole.reach * hole.share * evidence(hole) * fresh(hole);
  const best = Math.max(...holes.map(met));
  const field = holes.filter((h) => met(h) * DRAW_WINDOW >= best);
  return pickWeighted(field.length ? field : holes, met, rand);
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
 * does not have, or a move the referee does not know at all.
 *
 * Theory is only told apart from prep where prep has something to say. Where
 * it says nothing — a run through the book — a theory move is simply the
 * move. Both theory and a miss are handed to the engine: a blunder ends the
 * run, and a sound move is a checkpoint.
 */
export type MoveKind = 'prep' | 'theory' | 'miss';

export function classify(source: LineSource, run: Run, san: string): MoveKind {
  if (!movesHere(source, run).includes(san)) return 'miss';
  const prep = source.prepAt(run.fen);
  if (!prep.length || prep.includes(san)) return 'prep';
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
 * Stopping after a sound move off your prep is not the same kind of failure
 * as a blunder, and finishing after having left your prep is not the same
 * kind of success as finishing having known it all the way through. Keeping
 * them apart is the difference between "learn this" and "you got that wrong".
 *
 * `cause` is null for a run that finished: the referee ran out and you
 * stopped there, or you kept playing and the game itself ended.
 */
export type RunGrade = 'green' | 'yellow' | 'red' | 'purple';

export function gradeOf(run: Run, cause: DeathCause | null): RunGrade {
  if (cause === null) return run.leftPrep ? 'yellow' : 'green';
  return cause === 'offprep' ? 'purple' : 'red';
}

export const GRADES: RunGrade[] = ['green', 'yellow', 'red', 'purple'];

export function gradeLabel(grade: RunGrade): string {
  switch (grade) {
    case 'green':
      return 'Clean finish';
    case 'yellow':
      return 'Finished out of prep';
    case 'purple':
      return 'Stopped out of prep';
    default:
      return 'Blundered';
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
 * Step outside the prep and carry on, from a checkpoint.
 *
 * The move — sound, by the engine — is played. It earns nothing: the score
 * is moves found in your prep, and this was not one. The drawn line stops
 * steering, and from here the engine is the referee.
 */
export function leavePrep(run: Run, san: string): Run {
  const move = applySan(run.fen, san);
  if (!move) return { ...run, over: true };
  return {
    ...run,
    fen: move.after,
    played: [...run.played, san],
    leftPrep: true,
    extended: true,
    handOver: run.handOver ?? run.played.length,
    past: run.past + 1,
    target: [],
  };
}

/**
 * The referee has nothing more to say: your prep has been played out, or the
 * book has on a run through it. That completes the run, whatever comes after.
 */
export function finishPrep(run: Run): Run {
  return run.prepDone === null ? { ...run, prepDone: run.played.length } : run;
}

/**
 * Keep playing past the end of the prep, from its checkpoint. Not leaving
 * the prep — there was nothing here to leave — so a finish stays green; but
 * the engine judges from here, and its verdicts earn nothing.
 */
export function keepPlaying(run: Run): Run {
  if (run.extended) return run;
  return { ...finishPrep(run), extended: true, handOver: run.played.length, target: [] };
}

/* ── past the hand-over ─────────────────────────────────────────────────── */

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

/**
 * One of your moves the engine passed, past the hand-over. It earns nothing
 * and does not count as survived: the score is what you found in your prep.
 */
export function playPast(run: Run, san: string): Run {
  const applied = applySan(run.fen, san);
  if (!applied) return { ...run, over: true };
  return { ...run, fen: applied.after, played: [...run.played, san], past: run.past + 1 };
}

/** The opponent's move, once something has chosen it — the book or the engine. */
export function playReply(run: Run, san: string): Run {
  const applied = applySan(run.fen, san);
  if (!applied) return { ...run, over: true };
  return { ...run, fen: applied.after, played: [...run.played, san] };
}

/**
 * True when the referee has run out entirely: nothing prepared and nothing
 * in the book, at either side's turn.
 *
 * Never past the hand-over: the engine always has another move, and only a
 * blunder or the game itself ends play from there.
 */
export function isComplete(source: LineSource, run: Run): boolean {
  return !run.over && !run.extended && movesHere(source, run).length === 0;
}

/**
 * True at the edge of the prep: your move, nothing prepared, the book still
 * going. This is where a run offers the book, with moves left to add, and
 * otherwise where the end of the prep is a checkpoint.
 *
 * Never on a run through the book — there is no prep to be at the edge of,
 * and the book running out is its checkpoint — and never past the hand-over.
 */
export function atEdge(source: LineSource, run: Run): boolean {
  if (run.over || run.bookRun || run.extended || !isUsersTurn(run)) return false;
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

/**
 * What a run adds up to, once it is over.
 *
 * Completing a run is reaching the end of its prep — a fact, once it has
 * happened, whatever you chose to do next. The grade is how the run actually
 * ended: a blunder past the checkpoint is still a blunder.
 */
export function outcomeOf(run: Run, cause: DeathCause | null): RunOutcome {
  return {
    id: run.id,
    grade: gradeOf(run, cause),
    label: run.sourceLabel,
    openingId: run.openingId,
    color: run.color,
    depth: run.survived,
    completed: run.prepDone !== null,
  };
}

/**
 * Log a finished run.
 *
 * Logging the same run twice amends it rather than counting it again: the
 * count stays at one run and the deeper score replaces the shallower one —
 * `best` only ever grows, so taking the maximum is right either way. A
 * completed line stays counted.
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

/* ── keeping the line ───────────────────────────────────────────────────── */

/**
 * The part of a run worth offering to the repertoire, at the reveal.
 *
 * Nothing is written by playing; this is what the one tap would write. Every
 * move the referee passed — a run's `played` never contains the move that
 * ended it — and then, past the hand-over, only as far as the moves are still
 * theory: a move the engine passed that the book has never seen is sound but
 * not prep. The line is trimmed to end on your own move, because one ending
 * on the opponent's prepares nothing.
 */
export function lineToKeep(index: ReferenceIndex, run: Run): string[] {
  const judged = run.handOver ?? run.played.length;
  let fen = START_FEN;
  const cut: string[] = [];
  for (let ply = 0; ply < run.played.length; ply += 1) {
    const san = run.played[ply];
    if (ply >= judged && !bookHas(index, fen, san)) break;
    const move = applySan(fen, san);
    if (!move) break;
    cut.push(san);
    fen = move.after;
  }
  // White's moves sit at even indices, so a White line has odd length.
  const wantsOdd = run.color === 'w';
  if (!cut.length) return [];
  return cut.length % 2 === 1 === wantsOdd ? cut : cut.slice(0, -1);
}
