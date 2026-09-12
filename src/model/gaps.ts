import { applySan, fenTurn, positionKey, type Color } from '../chess/core';
import { lookup, totalGamesAt, type ReferenceIndex } from './reference';
import type { ExplorerMove } from './types';
import { childrenOf, fenAt } from './repertoire';
import type { Repertoire } from './types';

/**
 * Gaps: replies the world plays that your repertoire has no answer to.
 *
 * A gap is only counted where preparation already exists and simply stops
 * short of one of the opponent's choices. Where a line ends outright there is
 * nothing to disagree with — that is prep running out, not prep contradicting
 * itself — and a mode that listed every unplayed move would be a list of the
 * whole database.
 *
 * Positions are merged by key first, exactly as drilling does, so a reply
 * covered through one move order counts as covered through all of them.
 */
export interface Gap {
  repertoireId: string;
  /** Moves from the start to the position where the opponent chooses. */
  path: string[];
  /** The position they choose in. */
  fen: string;
  /** The reply you have no answer to. */
  san: string;
  /** How often it is played there, as a percentage. */
  share: number;
  games: number;
  /** The replies you do answer. */
  have: string[];
  /** The position their move leads to — where your answer goes. */
  after: string;
}

export interface GapOptions {
  /** The least popular a reply can be and still count as a gap. */
  minShare?: number;
  /** How deep to look. Past this, "prep" is not really the word. */
  maxPly?: number;
}

export const DEFAULT_MIN_SHARE = 1;

/** Every position a repertoire reaches, with the union of its answers. */
function answersByPosition(rep: Repertoire, maxPly: number) {
  const answers = new Map<string, Set<string>>();
  const shortest = new Map<string, string[]>();
  const walk = (nodeId: string | null, path: string[]) => {
    const key = positionKey(fenAt(rep, nodeId));
    const kids = childrenOf(rep, nodeId);
    const set = answers.get(key) ?? new Set<string>();
    for (const kid of kids) set.add(kid.san);
    answers.set(key, set);
    const previous = shortest.get(key);
    if (!previous || path.length < previous.length) shortest.set(key, path);
    if (path.length >= maxPly) return;
    for (const kid of kids) walk(kid.id, [...path, kid.san]);
  };
  walk(null, []);
  return { answers, shortest };
}

export function findGaps(
  rep: Repertoire,
  index: ReferenceIndex,
  opts: GapOptions = {},
): Gap[] {
  const minShare = opts.minShare ?? DEFAULT_MIN_SHARE;
  const maxPly = opts.maxPly ?? 18;
  const { answers, shortest } = answersByPosition(rep, maxPly);
  const gaps: Gap[] = [];

  for (const [key, prepared] of answers) {
    const path = shortest.get(key)!;
    // The opening position is a per-colour question, answered by whichever
    // repertoire meets that first move.
    if (path.length === 0 || path.length > maxPly) continue;
    if (prepared.size === 0) continue;
    const turn: Color = path.length % 2 === 0 ? 'w' : 'b';
    if (turn === rep.color) continue;

    const entry = index.entries.get(key);
    if (!entry) continue;
    const total = totalGamesAt(entry);
    if (total === 0) continue;
    const fen = positionFor(rep, path);
    if (!fen) continue;

    for (const move of entry.moves) {
      const share = (move.games / total) * 100;
      if (share < minShare || prepared.has(move.san)) continue;
      const after = applySan(fen, move.san);
      if (!after) continue;
      gaps.push({
        repertoireId: rep.id,
        path,
        fen,
        san: move.san,
        share: Math.round(share * 10) / 10,
        games: move.games,
        have: [...prepared],
        after: after.after,
      });
    }
  }

  // Shallow and popular first: the gaps you are most likely to fall into.
  return gaps.sort((a, b) => a.path.length - b.path.length || b.share - a.share);
}

/** Walk a path from the root, since a key alone is not a position. */
function positionFor(rep: Repertoire, path: string[]): string | null {
  let fen = rep.rootFen;
  for (const san of path) {
    const move = applySan(fen, san);
    if (!move) return null;
    fen = move.after;
  }
  return fen;
}

/**
 * What the database plays in the gap, as candidate answers.
 *
 * Ordered by how often they are played rather than by result: a first
 * repertoire move should be one you will actually meet again, not the one that
 * scores best in forty games.
 */
export function candidateAnswers(
  index: ReferenceIndex,
  fen: string,
  limit = 5,
): ExplorerMove[] {
  const entry = lookup(index, fen);
  if (!entry) return [];
  return [...entry.moves].sort((a, b) => b.games - a.games).slice(0, limit);
}

/** The side whose answer is missing — always the repertoire's own colour. */
export function gapColor(gap: Gap): Color {
  return fenTurn(gap.after);
}
