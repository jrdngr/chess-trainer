import { positionKey, type Color } from '../chess/core';
import { analyseAgainstRepertoire, buildPlayerTree, type Finding } from './gameAnalysis';
import type { ImportedGame, Repertoire } from './types';

/**
 * Repair: the openings you actually got wrong, in games you actually played.
 *
 * Everything here comes from imported games compared against the repertoire —
 * no position is invented. That is the whole point: a mode built on generated
 * mistakes can only ever ask about mistakes nobody makes, whereas your own game
 * history is a list of the ones you really do.
 *
 * Two things can be wrong at a position you reached, and they want different
 * answers, so they stay separate all the way to the screen:
 *
 *   off prep    — you had a prepared move here and played something else.
 *                 There is a right answer, so this is a question.
 *   unprepared  — you reached this repeatedly with nothing prepared at all.
 *                 There is no right answer yet, so this is a decision.
 */

export type RepairKind = 'offprep' | 'unprepared';

export interface RepairItem {
  /** Stable across rebuilds, so a fixed item can be skipped. */
  id: string;
  kind: RepairKind;
  repertoireId: string;
  /** The side you were playing — always this repertoire's colour. */
  color: Color;
  key: string;
  /** The position you are to move in. */
  fen: string;
  /** Moves from the start to that position. */
  path: string[];
  lineText: string;
  /** How many of your games reached it. */
  games: number;
  results: { wins: number; draws: number; losses: number };
  /** What you actually played there, most often first. */
  played: { san: string; count: number }[];
  /** What the repertoire says. Empty for `unprepared`. */
  expected: string[];
  /** Ranking weight — bigger is more worth fixing. */
  weight: number;
}

export type RepairSort = 'common' | 'costly';

export interface RepairOptions {
  /** '' — every repertoire. */
  repertoireId?: string;
  kinds?: 'both' | RepairKind;
  /** How many of your games must have reached a position before it counts. */
  minGames?: number;
  /** Only positions from games you went on to lose. */
  lossesOnly?: boolean;
  sort?: RepairSort;
  limit?: number;
}

export const DEFAULT_MIN_GAMES = 2;

/** The ply at which this colour makes its first choice of the game. */
function firstDecisionPly(color: Color): number {
  return color === 'w' ? 0 : 1;
}

const KIND_OF: Partial<Record<Finding['kind'], RepairKind>> = {
  deviation: 'offprep',
  gap: 'unprepared',
};

/**
 * How much a mistake cost, as a share of the games it appeared in.
 *
 * A position you reached eight times and lost six of is worth more of your
 * attention than one you reached eight times and won. Draws count as half a
 * loss so a line that never wins still surfaces.
 */
export function costOf(item: Pick<RepairItem, 'games' | 'results'>): number {
  const { wins, draws, losses } = item.results;
  const played = wins + draws + losses;
  if (!played) return 0;
  return (losses + draws * 0.5) / played;
}

/** Every repairable position across the given repertoires. */
export function buildRepairs(
  games: ImportedGame[],
  reps: Repertoire[],
  opts: RepairOptions = {},
): RepairItem[] {
  const minGames = opts.minGames ?? DEFAULT_MIN_GAMES;
  const kinds = opts.kinds ?? 'both';
  const out: RepairItem[] = [];

  for (const rep of reps) {
    if (opts.repertoireId && rep.id !== opts.repertoireId) continue;
    const tree = buildPlayerTree(games, rep.color);
    if (!tree.games) continue;

    for (const finding of analyseAgainstRepertoire(tree, rep, { minGames, maxFindings: 200 })) {
      const kind = KIND_OF[finding.kind];
      if (!kind) continue;
      if (kinds !== 'both' && kinds !== kind) continue;
      if (!finding.played.length) continue;
      // The first decision of the game is which opening to play, not a move to
      // get right. Someone whose games open 1.e4 against a 1.d4 repertoire has
      // a mismatched repertoire, not 29 lapses — and left in, that one position
      // outranks everything real. `openingMismatch` reports it instead.
      if (finding.path.length <= firstDecisionPly(rep.color)) continue;

      const item: RepairItem = {
        id: `${rep.id}#${finding.key}#${kind}`,
        kind,
        repertoireId: rep.id,
        color: rep.color,
        key: finding.key,
        fen: finding.fen,
        path: finding.path,
        lineText: finding.lineText,
        games: finding.games,
        results: finding.results,
        played: finding.played,
        expected: finding.expected,
        weight: 0,
      };
      if (opts.lossesOnly && item.results.losses === 0) continue;
      // An off-prep move is a mistake you know how to fix, so it outranks a
      // position you never prepared at the same frequency.
      item.weight = finding.games * (kind === 'offprep' ? 1.5 : 1) * (1 + costOf(item));
      out.push(item);
    }
  }

  const sorted = out.sort((a, b) =>
    opts.sort === 'costly'
      ? costOf(b) - costOf(a) || b.games - a.games
      : b.weight - a.weight || a.path.length - b.path.length,
  );
  return opts.limit ? sorted.slice(0, opts.limit) : sorted;
}

/** Did they find the prepared move? Only `offprep` items have one. */
export function isRepaired(item: RepairItem, san: string): boolean {
  return item.expected.includes(san);
}

/** The line that adding `san` here would write into the repertoire. */
export function lineFor(item: RepairItem, san: string): string[] {
  return [...item.path, san];
}

/** The moves offered as a fix for an unprepared position: yours, then the book's. */
export function fixCandidates(item: RepairItem, book: string[]): string[] {
  const mine = item.played.map((p) => p.san);
  return [...mine, ...book.filter((san) => !mine.includes(san))];
}

/** A position key matches an item when the same position is reached any way. */
export function matchesPosition(item: RepairItem, fen: string): boolean {
  return item.key === positionKey(fen);
}

/**
 * The opening the player actually reaches for, when it is not the one this
 * repertoire prepares.
 *
 * This is the disagreement `buildRepairs` deliberately skips: it is a question
 * about which repertoire to keep, and repeating it as a puzzle would be telling
 * someone their own opening is a mistake.
 */
export interface OpeningMismatch {
  repertoireId: string;
  /** What they play, most often first. */
  played: { san: string; count: number }[];
  expected: string[];
  games: number;
}

/** Below this, a disagreement is too thin to call someone's opening wrong. */
export const MISMATCH_MIN_GAMES = 4;

export function openingMismatch(
  games: ImportedGame[],
  rep: Repertoire,
): OpeningMismatch | null {
  const tree = buildPlayerTree(games, rep.color);
  if (!tree.games) return null;
  const ply = firstDecisionPly(rep.color);
  for (const finding of analyseAgainstRepertoire(tree, rep, { minGames: 1, maxFindings: 200 })) {
    if (finding.kind !== 'deviation' || finding.path.length !== ply) continue;
    const off = finding.played.reduce((sum, p) => sum + p.count, 0);
    // Only a mismatch if they mostly do not play their own first move, and only
    // on enough games that it is a habit rather than two stray tries.
    if (off < MISMATCH_MIN_GAMES || off < finding.games * 0.5) return null;
    return {
      repertoireId: rep.id,
      played: finding.played,
      expected: finding.expected,
      games: off,
    };
  }
  return null;
}
