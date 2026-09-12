import { applySan, fenTurn, positionKey, sansToMoveText, START_FEN, type Color } from '../chess/core';
import { deepestName, lookup, type ReferenceIndex } from './reference';
import { childrenOf, displayName, fenAt, leafLines, pathTo } from './repertoire';
import { mulberry32 } from './session';
import type { Repertoire } from './types';

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

/* ── sources ────────────────────────────────────────────────────────────── */

/**
 * One repertoire, indexed by position so transpositions behave the way they do
 * in training: the same position reached two ways offers the same moves.
 */
export function repertoireSource(rep: Repertoire): LineSource {
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
    weightsAt: (fen) => movesAt(fen).map((san) => ({ san, weight: 1 })),
  };
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

/* ── runs ───────────────────────────────────────────────────────────────── */

export interface Run {
  source: SourceKind;
  sourceLabel: string;
  /** Which repertoire the line came from, for repertoire runs. */
  repertoireId?: string;
  color: Color;
  fen: string;
  played: string[];
  /** The user's correct moves so far — the score. */
  survived: number;
  over: boolean;
  /** Remaining moves of the line chosen up front, driving opponent replies. */
  target: string[];
}

export interface RunOptions {
  /** Skip lines that ask fewer than this many moves of the user. */
  minDecisions?: number;
  seed?: number;
}

function decisionsIn(color: Color, sans: string[]): number {
  return sans.filter((_, i) => (i % 2 === 0) === (color === 'w')).length;
}

/** Repertoires that can host a run for this colour. */
export function playableRepertoires(reps: Repertoire[], color: Color | 'random'): Repertoire[] {
  return reps.filter((rep) => (color === 'random' ? true : rep.color === color));
}

/**
 * Start a run from a repertoire. The line drawn up front only decides the
 * opponent's replies; any prepared move is accepted at your own turn.
 */
export function startRepertoireRun(
  reps: Repertoire[],
  color: Color | 'random',
  opts: RunOptions = {},
): Run | null {
  const minDecisions = opts.minDecisions ?? 4;
  const rand = mulberry32(opts.seed ?? Math.floor(Math.random() * 2 ** 31));

  const candidates = playableRepertoires(reps, color)
    .map((rep) => ({
      rep,
      lines: leafLines(rep).filter((l) => decisionsIn(rep.color, l.sans) >= minDecisions),
    }))
    .filter((c) => c.lines.length > 0);
  if (!candidates.length) return null;

  // Repertoire first, line second, so a big repertoire cannot crowd out the
  // others.
  const picked = candidates[Math.floor(rand() * candidates.length)];
  const line = picked.lines[Math.floor(rand() * picked.lines.length)];

  return {
    source: 'repertoire',
    sourceLabel: displayName(picked.rep.name),
    repertoireId: picked.rep.id,
    color: picked.rep.color,
    fen: START_FEN,
    played: [],
    survived: 0,
    over: false,
    target: pathTo(picked.rep, line.tipId).map((n) => n.san),
  };
}

/** Start a run in the book. There is no line to draw: the book is the line. */
export function startBookRun(
  index: ReferenceIndex,
  color: Color | 'random',
  opts: RunOptions = {},
): Run | null {
  const rand = mulberry32(opts.seed ?? Math.floor(Math.random() * 2 ** 31));
  const side: Color = color === 'random' ? (rand() < 0.5 ? 'w' : 'b') : color;
  if (!lookup(index, START_FEN)?.moves.length) return null;
  return {
    source: 'book',
    sourceLabel: 'Book',
    color: side,
    fen: START_FEN,
    played: [],
    survived: 0,
    over: false,
    target: [],
  };
}

/** Resolve "random" once, up front, so the rest of a run is deterministic. */
export function resolveColor(color: Color | 'random', rand: () => number): Color {
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
 */
export function lineName(
  index: ReferenceIndex,
  source: LineSource,
  run: Run,
  minPly = 4,
): LineName {
  const found = deepestName(index, fullLine(source, run));
  if (found && found.ply >= minPly) return { name: found.name, eco: found.eco, specific: true };
  return { name: run.sourceLabel, eco: found?.eco, specific: false };
}

/* ── starting a run ─────────────────────────────────────────────────────── */

export type ColorChoice = Color | 'random';

export interface BeginOptions {
  kind: SourceKind;
  reps: Repertoire[];
  index: ReferenceIndex;
  color: ColorChoice;
  seed?: number;
  minDecisions?: number;
}

/** Everything a run needs, or null when the options cannot produce one. */
export function beginRun(opts: BeginOptions): { source: LineSource; run: Run } | null {
  if (opts.kind === 'book') {
    const run = startBookRun(opts.index, opts.color, { seed: opts.seed });
    return run ? { run, source: bookSource(opts.index, run.color) } : null;
  }
  const run = startRepertoireRun(opts.reps, opts.color, {
    seed: opts.seed,
    minDecisions: opts.minDecisions,
  });
  if (!run) return null;
  const rep = opts.reps.find((r) => r.id === run.repertoireId);
  return rep ? { run, source: repertoireSource(rep) } : null;
}

/* ── record ─────────────────────────────────────────────────────────────── */

export interface PermadeathRecord {
  runs: number;
  /** Deepest run, counted in the user's own correct moves. */
  best: number;
  lastDepth: number;
  lastAt: number | null;
  /** Runs that reached the end of the line. */
  survivals: number;
}

export const EMPTY_RECORD: PermadeathRecord = {
  runs: 0,
  best: 0,
  lastDepth: 0,
  lastAt: null,
  survivals: 0,
};

export function recordRun(
  record: PermadeathRecord,
  depth: number,
  completed: boolean,
  at = Date.now(),
): PermadeathRecord {
  return {
    runs: record.runs + 1,
    best: Math.max(record.best, depth),
    lastDepth: depth,
    lastAt: at,
    survivals: record.survivals + (completed ? 1 : 0),
  };
}

