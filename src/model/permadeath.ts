import { applySan, fenTurn, sansToMoveText, type Color } from '../chess/core';
import { deepestName, type ReferenceIndex } from './reference';
import { childrenOf, displayName, fenAt, leafLines, pathTo } from './repertoire';
import { mulberry32 } from './session';
import type { RepMove, Repertoire } from './types';

/**
 * Permadeath: one secret line from the repertoire, played until the first
 * mistake ends the run.
 *
 * A run is not a fixed script. The line chosen up front only decides the
 * opponent's replies; at your own turn any move your repertoire prepares from
 * that position is accepted, and the run re-targets down whichever branch you
 * chose. The rule is "stay inside your repertoire", not "guess the one line I
 * picked" — which is both fairer and what the repertoire actually claims.
 */
export interface Run {
  repertoireId: string;
  /** Shown only after the run ends — during play the line is secret. */
  repertoireName: string;
  color: Color;
  /** Node ids of the line chosen up front, used to drive opponent replies. */
  target: string[];
  /** Current position: null is the start, otherwise the last move played. */
  nodeId: string | null;
  /** The user's correct moves so far — the score. */
  survived: number;
  /** Every move played, for the reveal. */
  played: string[];
  over: boolean;
}

export interface RunOptions {
  /** Skip lines that ask fewer than this many moves of the user. */
  minDecisions?: number;
  seed?: number;
}

function decisionsIn(rep: Repertoire, sans: string[]): number {
  // The user moves on every other ply, starting at 0 for White.
  return sans.filter((_, i) => (i % 2 === 0) === (rep.color === 'w')).length;
}

/**
 * Choose a repertoire first and a line within it second, so a big repertoire
 * does not crowd out the others.
 */
export function startRun(reps: Repertoire[], opts: RunOptions = {}): Run | null {
  const minDecisions = opts.minDecisions ?? 4;
  const rand = mulberry32(opts.seed ?? Math.floor(Math.random() * 2 ** 31));

  const candidates = reps
    .map((rep) => {
      const lines = leafLines(rep).filter((l) => decisionsIn(rep, l.sans) >= minDecisions);
      return { rep, lines };
    })
    .filter((c) => c.lines.length > 0);
  if (!candidates.length) return null;

  const picked = candidates[Math.floor(rand() * candidates.length)];
  const line = picked.lines[Math.floor(rand() * picked.lines.length)];
  const target = pathTo(picked.rep, line.tipId).map((n) => n.id);

  return {
    repertoireId: picked.rep.id,
    repertoireName: displayName(picked.rep.name),
    color: picked.rep.color,
    target,
    nodeId: null,
    survived: 0,
    played: [],
    over: false,
  };
}

export function currentFen(rep: Repertoire, run: Run): string {
  return fenAt(rep, run.nodeId);
}

export function isUsersTurn(rep: Repertoire, run: Run): boolean {
  return fenTurn(currentFen(rep, run)) === rep.color;
}

/** The moves the repertoire prepares from the current position. */
export function expectedMoves(rep: Repertoire, run: Run): RepMove[] {
  return childrenOf(rep, run.nodeId);
}

export type Judgement =
  | { ok: true; run: Run; san: string }
  | { ok: false; run: Run; played: string; expected: string[] };

/** Judge one move by the user. A move outside the repertoire ends the run. */
export function play(rep: Repertoire, run: Run, san: string): Judgement {
  const options = expectedMoves(rep, run);
  const match = options.find((o) => o.san === san);
  if (!match) {
    // The losing move is reported separately and deliberately kept out of
    // `played`, which stays the true line so the reveal shows the line the user
    // was actually on rather than their mistake.
    return {
      ok: false,
      run: { ...run, over: true },
      played: san,
      expected: options.map((o) => o.san),
    };
  }

  // Re-target if the user chose a prepared move off the original line.
  const target = run.target.includes(match.id)
    ? run.target
    : [...pathTo(rep, match.id).map((n) => n.id), ...deepestFrom(rep, match.id)];

  return {
    ok: true,
    san,
    run: {
      ...run,
      nodeId: match.id,
      survived: run.survived + 1,
      played: [...run.played, san],
      target,
    },
  };
}

/** Follow preferred children to the end of the line, for re-targeting. */
function deepestFrom(rep: Repertoire, nodeId: string): string[] {
  const out: string[] = [];
  let cur: string | null = nodeId;
  for (;;) {
    const kids: RepMove[] = childrenOf(rep, cur);
    if (!kids.length) break;
    const next = kids.find((k) => k.preferred) ?? kids[0];
    out.push(next.id);
    cur = next.id;
  }
  return out;
}

/**
 * The opponent's reply: the chosen line's move when it is still reachable,
 * otherwise any prepared continuation.
 */
export function opponentReply(rep: Repertoire, run: Run, rand: () => number): Run {
  const options = expectedMoves(rep, run);
  if (!options.length) return { ...run, over: true };
  const onTarget = options.find((o) => run.target.includes(o.id));
  const next = onTarget ?? options[Math.floor(rand() * options.length)];
  return { ...run, nodeId: next.id, played: [...run.played, next.san] };
}

/** True when the line has been played to its end without a mistake. */
export function isComplete(rep: Repertoire, run: Run): boolean {
  return !run.over && expectedMoves(rep, run).length === 0;
}

/**
 * The secret line in full: what was reached, plus how it would have gone.
 * The default reaches past the deepest seeded line so the reveal is complete.
 */
export function fullLine(rep: Repertoire, run: Run, plies = 48): string[] {
  return [...run.played, ...continuation(rep, run, plies)];
}

export function revealText(rep: Repertoire, run: Run): string {
  return sansToMoveText(fullLine(rep, run));
}

/** How the run would have continued, had it not ended. */
export function continuation(rep: Repertoire, run: Run, plies = 6): string[] {
  const out: string[] = [];
  // Death leaves run.nodeId at the last correct position; walk on from there.
  let cur: string | null = run.nodeId;
  for (let i = 0; i < plies; i += 1) {
    const kids: RepMove[] = childrenOf(rep, cur);
    if (!kids.length) break;
    const next = kids.find((k) => run.target.includes(k.id)) ?? kids.find((k) => k.preferred) ?? kids[0];
    out.push(next.san);
    cur = next.id;
  }
  return out;
}

/** Validate that a run's played moves are legal from the start position. */
export function playedIsLegal(run: Run): boolean {
  let fen = undefined as string | undefined;
  for (const san of run.played) {
    const move = applySan(fen ?? START, san);
    if (!move) return false;
    fen = move.after;
  }
  return true;
}

const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

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
 * the match is that shallow, the repertoire's own name is the better label.
 */
export function lineName(
  index: ReferenceIndex,
  rep: Repertoire,
  run: Run,
  minPly = 4,
): LineName {
  const found = deepestName(index, fullLine(rep, run));
  if (found && found.ply >= minPly) return { name: found.name, eco: found.eco, specific: true };
  return { name: run.repertoireName, eco: found?.eco, specific: false };
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
