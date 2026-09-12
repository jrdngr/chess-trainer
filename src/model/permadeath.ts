import {
  applySan,
  fenTurn,
  positionKey,
  sansToMoveText,
  START_FEN,
  type Color,
  type Square,
} from '../chess/core';
import { deepestName, lookup, type ReferenceIndex } from './reference';
import { childrenOf, displayName, fenAt, leafLines, pathTo } from './repertoire';
import { cardId, mulberry32 } from './session';
import type { Card, RepMove, Repertoire } from './types';

/**
 * Permadeath: one secret line, played until the first mistake ends the run.
 *
 * Both modes run on the same engine. A `LineSource` answers two questions about
 * a position — which moves count as staying in, and how the opponent replies —
 * and everything else (judging, revealing, scoring) is shared. The repertoire
 * source asks whether you know your own prep; the book source asks whether you
 * can stay in theory at all.
 */
export type SourceKind = 'repertoire' | 'book';

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
export interface PermadeathOptions {
  kind: SourceKind;
  color: ColorChoice;
  /** A single repertoire to draw from, or '' for every one that fits. */
  repertoireId: string;
  /** Play the side your repertoire prepares *against*. */
  reverse: boolean;
  /** Draw lines you answer badly more often than lines you know cold. */
  weakFirst: boolean;
  clock: ClockMode;
  hints: number;
}

export const DEFAULT_OPTIONS: PermadeathOptions = {
  kind: 'repertoire',
  color: 'random',
  repertoireId: '',
  reverse: false,
  weakFirst: false,
  clock: 'off',
  hints: 0,
};

/* ── runs ───────────────────────────────────────────────────────────────── */

export interface Run {
  source: SourceKind;
  sourceLabel: string;
  /** Which repertoire the line came from, for repertoire runs. */
  repertoireId?: string;
  /** True when you are playing the side the repertoire prepares against. */
  reverse: boolean;
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
}

/** How a run ended. Time is a real cause of death, not a technicality. */
export type DeathCause = 'move' | 'time';

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

  // Repertoire first, then a line within it, so a big repertoire cannot crowd
  // out the others however popular its lines are.
  // Repertoire first and evenly, so a big one cannot crowd out the others
  // however popular its lines are; the line within it is drawn on its odds.
  const picked = candidates[Math.floor(rand() * candidates.length)];
  const line = pickWeighted(picked.lines, (l) => l.weight, rand);

  return {
    source: 'repertoire',
    sourceLabel: displayName(picked.rep.name),
    repertoireId: picked.rep.id,
    reverse,
    color: picked.side,
    fen: START_FEN,
    played: [],
    survived: 0,
    over: false,
    target: line.path.map((n) => n.san),
    hints: opts.hints ?? 0,
    hintsUsed: 0,
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
    source: 'book',
    sourceLabel: 'Book',
    reverse: false,
    color: side,
    fen: START_FEN,
    played: [],
    survived: 0,
    over: false,
    target: [],
    hints: opts.hints ?? 0,
    hintsUsed: 0,
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

/** True when the line has been played out with no mistake left to make. */
export function isComplete(source: LineSource, run: Run): boolean {
  return !run.over && source.movesAt(run.fen).length === 0;
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

export interface BeginOptions extends Partial<PermadeathOptions> {
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

export interface PermadeathRecord {
  runs: number;
  /** Deepest run, counted in the user's own correct moves. */
  best: number;
  lastDepth: number;
  lastAt: number | null;
  /** Runs that reached the end of the line. */
  survivals: number;
  /** Per opening and side, so a Sicilian best does not hide behind a KID one. */
  byLine: Record<string, LineRecord>;
}

export const EMPTY_RECORD: PermadeathRecord = {
  runs: 0,
  best: 0,
  lastDepth: 0,
  lastAt: null,
  survivals: 0,
  byLine: {},
};

/** A saved record from before per-opening bests existed is still a record. */
export function normalizeRecord(record: Partial<PermadeathRecord> | undefined): PermadeathRecord {
  if (!record) return { ...EMPTY_RECORD };
  return { ...EMPTY_RECORD, ...record, byLine: record.byLine ?? {} };
}

export interface RunOutcome {
  key: string;
  label: string;
  color: Color;
  depth: number;
  completed: boolean;
}

/** Which bucket a run counts towards: the opening, and the side you played. */
export function outcomeOf(run: Run, completed: boolean): RunOutcome {
  const key =
    run.source === 'book' ? `book:${run.color}` : `rep:${run.repertoireId ?? ''}:${run.color}`;
  return {
    key,
    label: run.reverse ? `${run.sourceLabel} (reversed)` : run.sourceLabel,
    color: run.color,
    depth: run.survived,
    completed,
  };
}

export function recordRun(
  record: PermadeathRecord,
  outcome: RunOutcome,
  at = Date.now(),
): PermadeathRecord {
  const base = normalizeRecord(record);
  const previous = base.byLine[outcome.key];
  return {
    runs: base.runs + 1,
    best: Math.max(base.best, outcome.depth),
    lastDepth: outcome.depth,
    lastAt: at,
    survivals: base.survivals + (outcome.completed ? 1 : 0),
    byLine: {
      ...base.byLine,
      [outcome.key]: {
        label: outcome.label,
        color: outcome.color,
        runs: (previous?.runs ?? 0) + 1,
        best: Math.max(previous?.best ?? 0, outcome.depth),
        survivals: (previous?.survivals ?? 0) + (outcome.completed ? 1 : 0),
        lastAt: at,
      },
    },
  };
}

/** Per-opening records, deepest first — what the breakdown shows. */
export function lineRecords(record: PermadeathRecord): (LineRecord & { key: string })[] {
  return Object.entries(normalizeRecord(record).byLine)
    .map(([key, value]) => ({ ...value, key }))
    .sort((a, b) => b.best - a.best || b.runs - a.runs);
}
