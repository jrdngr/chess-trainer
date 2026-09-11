import { describe, expect, it } from 'vitest';
import { positionKey, walkSan } from '../chess/core';
import {
  analyseAgainstRepertoire,
  buildPlayerTree,
  findingToLine,
  measureCoverage,
} from './gameAnalysis';
import { addLine, createRepertoire } from './repertoire';
import { generateSampleArchive } from './seed/sampleGames';
import type { ImportedGame } from './types';

function game(moves: string, color: 'w' | 'b', result: string, id = 'g'): ImportedGame {
  return {
    id,
    source: 'pgn',
    white: color === 'w' ? 'me' : 'them',
    black: color === 'b' ? 'me' : 'them',
    result,
    userColor: color,
    moves: moves.split(' '),
  };
}

const whiteRep = addLine(
  createRepertoire('White', 'w', 'rep_w'),
  ['e4', 'c5', 'Nf3', 'd6', 'd4'],
  'seed',
).rep;

describe('player tree', () => {
  it('counts only the games played with the chosen colour', () => {
    const games = [
      game('e4 c5 Nf3', 'w', '1-0', 'a'),
      game('e4 c5 Nf3', 'w', '0-1', 'b'),
      game('d4 d5', 'b', '0-1', 'c'),
    ];
    expect(buildPlayerTree(games, 'w').games).toBe(2);
    expect(buildPlayerTree(games, 'b').games).toBe(1);
  });

  it('records the moves the player chose and how those games went', () => {
    const games = [
      game('e4 c5 Nf3', 'w', '1-0', 'a'),
      game('e4 c5 c3', 'w', '0-1', 'b'),
      game('e4 c5 c3', 'w', '1/2-1/2', 'c'),
    ];
    const tree = buildPlayerTree(games, 'w');
    const key = positionKey(walkSan(['e4', 'c5']).fens.at(-1)!);
    const node = tree.nodes.get(key)!;
    expect(node.games).toBe(3);
    expect([...node.choices.entries()].sort()).toEqual([
      ['Nf3', 1],
      ['c3', 2],
    ]);
    expect(node).toMatchObject({ wins: 1, draws: 1, losses: 1 });
  });

  it('does not record the opponent moves as the player choices', () => {
    const tree = buildPlayerTree([game('e4 c5 Nf3', 'w', '1-0')], 'w');
    const afterE4 = positionKey(walkSan(['e4']).fens.at(-1)!);
    expect(tree.nodes.get(afterE4)!.choices.size).toBe(0);
  });
});

describe('analysis against a repertoire', () => {
  it('flags a deviation from the prepared move', () => {
    const games = [game('e4 c5 c3 d5', 'w', '0-1', 'a'), game('e4 c5 c3 Nf6', 'w', '0-1', 'b')];
    const findings = analyseAgainstRepertoire(buildPlayerTree(games, 'w'), whiteRep);
    const deviation = findings.find((f) => f.kind === 'deviation');
    expect(deviation).toBeDefined();
    expect(deviation!.expected).toEqual(['Nf3']);
    expect(deviation!.played).toEqual([{ san: 'c3', count: 2 }]);
    expect(deviation!.lineText).toBe('1. e4 c5');
  });

  it('flags a gap where the repertoire says nothing', () => {
    const games = [
      game('e4 e5 Nf3 Nc6 Bb5', 'w', '1-0', 'a'),
      game('e4 e5 Nf3 Nc6 Bc4', 'w', '0-1', 'b'),
    ];
    const findings = analyseAgainstRepertoire(buildPlayerTree(games, 'w'), whiteRep);
    const gap = findings.find((f) => f.kind === 'gap' && f.lineText === '1. e4 e5');
    expect(gap).toBeDefined();
    expect(gap!.games).toBe(2);
    expect(gap!.played.map((p) => p.san).sort()).toEqual(['Nf3']);
  });

  it('says nothing about positions seen only once by default', () => {
    const findings = analyseAgainstRepertoire(
      buildPlayerTree([game('e4 e5 Nf3', 'w', '1-0')], whiteRep.color),
      whiteRep,
    );
    expect(findings.filter((f) => f.kind === 'gap')).toHaveLength(0);
  });

  it('treats everything as a gap when there is no repertoire', () => {
    const games = [game('d4 d5 c4', 'w', '1-0', 'a'), game('d4 d5 c4', 'w', '1-0', 'b')];
    const findings = analyseAgainstRepertoire(buildPlayerTree(games, 'w'), null);
    expect(findings.every((f) => f.kind === 'gap')).toBe(true);
    expect(findings.length).toBeGreaterThan(0);
  });

  it('ranks frequent early positions above rare deep ones', () => {
    const games = [
      ...Array.from({ length: 6 }, (_, i) => game('d4 d5', 'w', '1-0', `x${i}`)),
      game('e4 e5 Nf3 Nc6 Bb5 a6 Ba4', 'w', '1-0', 'y1'),
      game('e4 e5 Nf3 Nc6 Bb5 a6 Ba4', 'w', '1-0', 'y2'),
    ];
    const findings = analyseAgainstRepertoire(buildPlayerTree(games, 'w'), whiteRep);
    expect(findings[0].lineText).toBe('Starting position');
  });

  it('turns a finding into an importable line', () => {
    const games = [game('e4 c5 c3 d5', 'w', '0-1', 'a'), game('e4 c5 c3 Nf6', 'w', '0-1', 'b')];
    const findings = analyseAgainstRepertoire(buildPlayerTree(games, 'w'), whiteRep);
    const deviation = findings.find((f) => f.kind === 'deviation')!;
    expect(findingToLine(deviation)).toEqual(['e4', 'c5', 'c3']);
  });
});

describe('coverage', () => {
  const deepRep = addLine(
    createRepertoire('White deep', 'w', 'rep_deep'),
    ['e4', 'c5', 'Nf3', 'd6', 'd4', 'cxd4', 'Nxd4', 'Nf6', 'Nc3'],
    'seed',
  ).rep;

  it('measures how deep games stay in prep', () => {
    const games = [
      game('e4 c5 Nf3 d6 d4 cxd4', 'w', '1-0', 'a'),
      game('d4 d5 c4', 'w', '0-1', 'b'),
    ];
    const coverage = measureCoverage(games, whiteRep);
    expect(coverage.games).toBe(2);
    // Five plies in prep on one game, zero on the other.
    expect(coverage.averageExitPly).toBe(2.5);
    // "In prep" needs at least three moves inside the repertoire.
    expect(coverage.inPrep).toBe(0);
    expect(coverage.outOfPrep).toBe(2);
  });

  it('counts a game that follows prep past move three', () => {
    const coverage = measureCoverage(
      [game('e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6', 'w', '1-0', 'a')],
      deepRep,
    );
    expect(coverage.inPrep).toBe(1);
    expect(coverage.averageExitPly).toBe(9);
  });

  it('ignores games played with the other colour', () => {
    expect(measureCoverage([game('e4 c5 Nf3', 'b', '0-1', 'a')], whiteRep).games).toBe(0);
  });
});

describe('sample archive', () => {
  const games = generateSampleArchive({ username: 'tester', count: 30, seed: 7 });

  it('is deterministic for a seed', () => {
    const again = generateSampleArchive({ username: 'tester', count: 30, seed: 7 });
    expect(games.map((g) => g.moves.join(' '))).toEqual(again.map((g) => g.moves.join(' ')));
  });

  it('produces legal games with the user on one side', () => {
    for (const g of games) {
      expect(walkSan(g.moves).moves).toHaveLength(g.moves.length);
      expect([g.white, g.black]).toContain('tester');
      expect(g.userColor).toBe(g.white === 'tester' ? 'w' : 'b');
    }
  });

  it('leans on the openings the fictional player prefers', () => {
    const asWhite = games.filter((g) => g.userColor === 'w');
    const e4 = asWhite.filter((g) => g.moves[0] === 'e4').length;
    expect(e4 / asWhite.length).toBeGreaterThan(0.6);
  });
});
