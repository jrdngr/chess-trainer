import { applySan, fenTurn, legalMoves, positionKey, type Color, type PieceType } from '../chess/core';
import { lookup, type ReferenceIndex } from './reference';
import { childrenOf, fenAt } from './repertoire';
import { mulberry32 } from './session';
import type { Repertoire } from './types';

/**
 * Punish: the opponent leaves your preparation with a move that drops material,
 * and you take it.
 *
 * The whole mode is static and material-only on purpose. "They blundered, win
 * the piece" is a claim that can be checked exactly — by counting what a capture
 * wins and what the recapture takes back — so a puzzle is either sound or it is
 * not generated. An engine could find deeper punishments, but then the answer
 * would depend on how long it was allowed to think, and a puzzle whose answer
 * moves is worse than a simple one that is always right.
 */
const VALUE: Record<PieceType, number> = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 0 };

/** Material a single capture wins, after the cheapest recapture. */
export interface Capture {
  san: string;
  /** The square it captures on. */
  to: string;
  /** Pawns won: what is taken, less what the recapture takes back. */
  gain: number;
}

/**
 * The best captures available to the side to move, and what they win.
 *
 * A capture is worth what it takes, less the attacker when the square can be
 * recaptured — the ordinary way of looking at a hanging piece. Recaptures are
 * generated rather than guessed, so a pinned defender does not count.
 */
export function bestCaptures(fen: string): Capture[] {
  const out: Capture[] = [];
  for (const move of legalMoves(fen)) {
    if (!move.captured) continue;
    const taken = VALUE[move.captured];
    const recapture = legalMoves(move.after).some((reply) => reply.to === move.to && reply.captured);
    out.push({ san: move.san, to: move.to, gain: taken - (recapture ? VALUE[move.piece] : 0) });
  }
  if (!out.length) return [];
  const best = Math.max(...out.map((c) => c.gain));
  return out.filter((c) => c.gain === best).sort((a, b) => a.san.localeCompare(b.san));
}

export interface Blunder {
  /** The move the opponent played. */
  san: string;
  /** The position it leads to, where the punishment is found. */
  after: string;
  /** The reply that wins the most, and any that tie with it. */
  answers: string[];
  /** Pawns the punishment wins. */
  gain: number;
  /** True when they took something first — the poisoned-pawn shape. */
  greedy: boolean;
}

export interface BlunderOptions {
  /** Moves that are prepared or in the book, and so never a blunder. */
  known?: (san: string) => boolean;
  /** The least material a puzzle is allowed to be worth. */
  minGain?: number;
}

/**
 * Moves that walk into a capture at this position.
 *
 * Two rules keep the puzzles worth solving.
 *
 * Only captures and checks are considered. A player who is about to go wrong
 * goes wrong on a move they had a reason to play — grabbing a pawn, giving a
 * check — not by dropping a bishop on an empty square for no reason. Scanning
 * every legal move finds far more "blunders" and almost none of them are moves
 * a human would ever make, which teaches nothing and is slow besides.
 *
 * And the punishment has to land on the square they just moved to, so the
 * mistake is this move rather than something that was already wrong with the
 * position. That also makes the answer easy to state: take the piece that just
 * came.
 */
export function findBlunders(fen: string, opts: BlunderOptions = {}): Blunder[] {
  const minGain = opts.minGain ?? 2;
  const out: Blunder[] = [];

  for (const move of legalMoves(fen)) {
    const check = move.san.includes('+') || move.san.includes('#');
    if (!move.captured && !check) continue;
    if (opts.known?.(move.san)) continue;

    const best = bestCaptures(move.after);
    if (!best.length) continue;
    // Only what this move gave away: a capture somewhere else on the board was
    // available before they moved and is not theirs to have blundered.
    const answers = best.filter((c) => c.to === move.to);
    if (!answers.length) continue;

    // What the exchange is actually worth. A move that takes a knight and
    // loses a bishop has conceded nothing, however big the recapture looks —
    // counting only the punishment turns every even trade into a blunder.
    const net = best[0].gain - (move.captured ? VALUE[move.captured] : 0);
    if (net < minGain) continue;

    out.push({
      san: move.san,
      after: move.after,
      answers: answers.map((c) => c.san),
      gain: net,
      greedy: !!move.captured,
    });
  }

  // The greedy ones first: a pawn grab punished is the shape worth learning.
  return out.sort(
    (a, b) => Number(b.greedy) - Number(a.greedy) || b.gain - a.gain || a.san.localeCompare(b.san),
  );
}

/* ── drawing a puzzle from a repertoire ─────────────────────────────────── */

export interface Puzzle {
  repertoireId: string;
  /** Your colour: the side that does the punishing. */
  color: Color;
  /** Moves from the start to the position the opponent went wrong in. */
  path: string[];
  /** The position they moved from. */
  fen: string;
  /** What they played. */
  blunder: string;
  /** The position you are shown. */
  after: string;
  /** The moves that win the material. */
  answers: string[];
  /** Pawns it wins. */
  gain: number;
}

/** Positions a repertoire reaches where the opponent is on move. */
export function opponentPositions(
  rep: Repertoire,
  maxPly = 16,
): { path: string[]; fen: string; prepared: Set<string> }[] {
  const seen = new Map<string, { path: string[]; fen: string; prepared: Set<string> }>();
  const walk = (nodeId: string | null, path: string[]) => {
    const fen = fenAt(rep, nodeId);
    const kids = childrenOf(rep, nodeId);
    if (path.length <= maxPly && fenTurn(fen) !== rep.color && kids.length) {
      const key = positionKey(fen);
      const found = seen.get(key);
      if (!found) seen.set(key, { path, fen, prepared: new Set(kids.map((k) => k.san)) });
      else for (const kid of kids) found.prepared.add(kid.san);
    }
    if (path.length >= maxPly) return;
    for (const kid of kids) walk(kid.id, [...path, kid.san]);
  };
  walk(null, []);
  return [...seen.values()];
}

export interface PuzzleOptions {
  seed?: number;
  minGain?: number;
  maxPly?: number;
}

/**
 * Every sound puzzle a repertoire can produce, one per position.
 *
 * Moves the book knows are left out: a gambit is not a blunder, and being asked
 * to "punish" a move that thousands of games play would teach the wrong lesson.
 */
export function puzzlesFrom(
  rep: Repertoire,
  index: ReferenceIndex,
  opts: PuzzleOptions = {},
): Puzzle[] {
  return opponentPositions(rep, opts.maxPly ?? 16)
    .map((spot) => puzzleAt(rep, index, spot, opts.minGain))
    .filter((puzzle): puzzle is Puzzle => puzzle !== null);
}

/**
 * One puzzle, found without working out all of them.
 *
 * Scanning a whole repertoire takes seconds, which is a long time to hold a
 * screen still for a single puzzle. Positions are visited in a shuffled order
 * that favours the opening — a trap on move three is worth knowing, one on move
 * fifteen is a curiosity — and the search stops at the first sound one.
 */
export function findPuzzle(
  rep: Repertoire,
  index: ReferenceIndex,
  opts: PuzzleOptions = {},
): Puzzle | null {
  const rand = mulberry32(Math.floor(opts.seed ?? Math.random() * 2 ** 31));
  const spots = opponentPositions(rep, opts.maxPly ?? 16)
    .map((spot) => ({ spot, order: rand() * (1 + spot.path.length) }))
    .sort((a, b) => a.order - b.order);

  for (const { spot } of spots) {
    const puzzle = puzzleAt(rep, index, spot, opts.minGain);
    if (puzzle) return puzzle;
  }
  return null;
}

function puzzleAt(
  rep: Repertoire,
  index: ReferenceIndex,
  spot: { path: string[]; fen: string; prepared: Set<string> },
  minGain?: number,
): Puzzle | null {
  const book = new Set((lookup(index, spot.fen)?.moves ?? []).map((m) => m.san));
  const best = findBlunders(spot.fen, {
    minGain,
    known: (san) => spot.prepared.has(san) || book.has(san),
  })[0];
  if (!best || !best.answers.length) return null;
  return {
    repertoireId: rep.id,
    color: rep.color,
    path: spot.path,
    fen: spot.fen,
    blunder: best.san,
    after: best.after,
    answers: best.answers,
    gain: best.gain,
  };
}

/** Did they find it? */
export function isPunishment(puzzle: Puzzle, san: string): boolean {
  return puzzle.answers.includes(san);
}

/** The position after the punishment, for showing what it wins. */
export function afterPunishment(puzzle: Puzzle): string | null {
  return applySan(puzzle.after, puzzle.answers[0])?.after ?? null;
}
