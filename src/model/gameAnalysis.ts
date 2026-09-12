import { applySan, fenTurn, positionKey, sansToMoveText, START_FEN, type Color } from '../chess/core';
import { childrenOf, fenAt } from './repertoire';
import type { RepMove, Repertoire } from './types';
import type { ImportedGame } from './types';

/** One position in the player's own game history. */
export interface PlayedNode {
  key: string;
  fen: string;
  /** SAN path from the start position (shortest route seen). */
  path: string[];
  games: number;
  wins: number;
  draws: number;
  losses: number;
  /** SAN -> times the player chose it (only for positions on their turn). */
  choices: Map<string, number>;
}

export interface PlayerTree {
  color: Color;
  nodes: Map<string, PlayedNode>;
  games: number;
}

function scoreFor(game: ImportedGame, color: Color): 'win' | 'draw' | 'loss' {
  if (game.result === '1/2-1/2') return 'draw';
  const whiteWon = game.result === '1-0';
  return whiteWon === (color === 'w') ? 'win' : 'loss';
}

/** Fold a set of games into a tree of the positions the player actually reached. */
export function buildPlayerTree(
  games: ImportedGame[],
  color: Color,
  maxPlies = 24,
): PlayerTree {
  const nodes = new Map<string, PlayedNode>();
  let counted = 0;

  for (const game of games) {
    if (game.userColor !== color) continue;
    counted += 1;
    const outcome = scoreFor(game, color);
    let fen = START_FEN;
    const path: string[] = [];

    for (let i = 0; i <= Math.min(game.moves.length, maxPlies); i += 1) {
      const key = positionKey(fen);
      let node = nodes.get(key);
      if (!node) {
        node = { key, fen, path: [...path], games: 0, wins: 0, draws: 0, losses: 0, choices: new Map() };
        nodes.set(key, node);
      }
      node.games += 1;
      if (outcome === 'win') node.wins += 1;
      else if (outcome === 'draw') node.draws += 1;
      else node.losses += 1;

      const san = game.moves[i];
      if (san === undefined) break;
      if (fenTurn(fen) === color) {
        node.choices.set(san, (node.choices.get(san) ?? 0) + 1);
      }
      const move = applySan(fen, san);
      if (!move) break;
      fen = move.after;
      path.push(move.san);
    }
  }

  return { color, nodes, games: counted };
}

export type FindingKind = 'gap' | 'deviation' | 'unplayed';

export interface Finding {
  kind: FindingKind;
  key: string;
  fen: string;
  path: string[];
  lineText: string;
  /** How many of the player's games reached this position. */
  games: number;
  score: number;
  /** Result percentage from the player's side, 0..1. */
  results: { wins: number; draws: number; losses: number };
  /** For 'deviation' and 'gap': what the player actually played, most common first. */
  played: { san: string; count: number }[];
  /** For 'deviation' and 'unplayed': what the repertoire says. */
  expected: string[];
}

export interface AnalysisOptions {
  minGames?: number;
  maxFindings?: number;
}

/**
 * Compare what the player actually played against what their repertoire says.
 *
 * - gap:       a position they reach often with nothing prepared
 * - deviation: a position where they played something other than their prep
 * - unplayed:  prepared lines that never came up (lowest priority)
 */
export function analyseAgainstRepertoire(
  tree: PlayerTree,
  rep: Repertoire | null,
  opts: AnalysisOptions = {},
): Finding[] {
  const minGames = opts.minGames ?? 2;
  const findings: Finding[] = [];

  // Index the repertoire by position key for transposition-tolerant matching.
  const repByKey = new Map<string, string[]>();
  if (rep) {
    const visit = (nodeId: string | null) => {
      const fen = fenAt(rep, nodeId);
      const kids = childrenOf(rep, nodeId);
      if (kids.length && fenTurn(fen) === rep.color) {
        const key = positionKey(fen);
        const existing = repByKey.get(key) ?? [];
        for (const kid of kids) if (!existing.includes(kid.san)) existing.push(kid.san);
        repByKey.set(key, existing);
      }
      for (const kid of kids) visit(kid.id);
    };
    visit(null);
  }

  for (const node of tree.nodes.values()) {
    if (!node.choices.size || node.games < minGames) continue;
    const expected = repByKey.get(node.key);
    const played = [...node.choices.entries()]
      .map(([san, count]) => ({ san, count }))
      .sort((a, b) => b.count - a.count);

    const results = { wins: node.wins, draws: node.draws, losses: node.losses };
    const base: Omit<Finding, 'kind' | 'score' | 'expected'> = {
      key: node.key,
      fen: node.fen,
      path: node.path,
      lineText: sansToMoveText(node.path) || 'Starting position',
      games: node.games,
      results,
      played,
    };

    if (!expected) {
      // No prep at all here. Deeper positions matter less than early ones.
      const depthPenalty = 1 / (1 + node.path.length / 6);
      findings.push({
        ...base,
        kind: 'gap',
        expected: [],
        score: node.games * depthPenalty * (1 + node.losses / Math.max(1, node.games)),
      });
    } else {
      const offPrep = played.filter((p) => !expected.includes(p.san));
      const offCount = offPrep.reduce((s, p) => s + p.count, 0);
      if (offCount > 0) {
        findings.push({
          ...base,
          kind: 'deviation',
          expected,
          played: offPrep,
          score: offCount * 1.5,
        });
      }
    }
  }

  // Prepared lines that never appeared in the games.
  if (rep) {
    for (const [key, sans] of repByKey) {
      if (tree.nodes.has(key)) continue;
      const node = (Object.values(rep.nodes) as RepMove[]).find((n) => n.key === key);
      if (!node) continue;
      findings.push({
        kind: 'unplayed',
        key,
        fen: node.fenBefore,
        path: [],
        lineText: sansToMoveText([...sans.slice(0, 1)], node.fenBefore),
        games: 0,
        results: { wins: 0, draws: 0, losses: 0 },
        played: [],
        expected: sans,
        score: 0.01,
      });
    }
  }

  return findings
    .sort((a, b) => b.score - a.score)
    .slice(0, opts.maxFindings ?? 40);
}

export interface RepertoireCoverage {
  /** Games whose opening stayed inside the repertoire for at least 6 plies. */
  inPrep: number;
  outOfPrep: number;
  /** Average ply at which the game left the repertoire. */
  averageExitPly: number;
  games: number;
}

/** How long the player's games stayed inside their prepared lines. */
export function measureCoverage(games: ImportedGame[], rep: Repertoire): RepertoireCoverage {
  const repByKey = new Map<string, string[]>();
  const visit = (nodeId: string | null) => {
    const fen = fenAt(rep, nodeId);
    const kids = childrenOf(rep, nodeId);
    if (kids.length) {
      const existing = repByKey.get(positionKey(fen)) ?? [];
      for (const kid of kids) if (!existing.includes(kid.san)) existing.push(kid.san);
      repByKey.set(positionKey(fen), existing);
    }
    for (const kid of kids) visit(kid.id);
  };
  visit(null);

  let inPrep = 0;
  let exitSum = 0;
  let counted = 0;

  for (const game of games) {
    if (game.userColor !== rep.color) continue;
    counted += 1;
    let fen = START_FEN;
    let ply = 0;
    for (const san of game.moves) {
      const known = repByKey.get(positionKey(fen));
      if (!known || !known.includes(san)) break;
      const move = applySan(fen, san);
      if (!move) break;
      fen = move.after;
      ply += 1;
    }
    exitSum += ply;
    if (ply >= 6) inPrep += 1;
  }

  return {
    inPrep,
    outOfPrep: counted - inPrep,
    averageExitPly: counted ? exitSum / counted : 0,
    games: counted,
  };
}

/** Turn a finding into the line the user would add to their repertoire. */
export function findingToLine(finding: Finding): string[] {
  const best = finding.played[0]?.san;
  return best ? [...finding.path, best] : finding.path;
}
