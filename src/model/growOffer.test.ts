import { describe, expect, it } from 'vitest';
import { walkSan } from '../chess/core';
import { answerHole, atHole, startGrowthAt } from './growth';
import {
  CLEAN_FINISHES,
  growLaunch,
  holeAtEnd,
  isStubFinish,
  yourLastMove,
  lineFinishes,
  offerOpening,
  readyToGrow,
} from './growOffer';
import { atEdge, beginRun, finishPrep, isUsersTurn, opponentReply, play, movesHere } from './openingRun';
import { nodeById, openingTree } from './openingTree';
import { referenceIndex } from './referenceIndex';
import { addLine, createRepertoire, leafLines } from './repertoire';
import type { RoundRecord } from './scoring';
import { mulberry32 } from './session';
import type { Repertoire } from './types';

const index = referenceIndex();
const tree = openingTree(index);
const gambit = nodeById(tree, 'd4 d5 c4');
const opts = { minShare: 1, maxPly: 18, starred: [] };

function rep(color: 'w' | 'b', ...lines: string[]): Repertoire {
  let out = createRepertoire('Test', color, `rep_${color}`);
  for (const line of lines) out = addLine(out, line.split(' '), 'seed').rep;
  return out;
}

/** A clean Run round on a line, at a given time. */
function clean(line: string, at: number, color: 'w' | 'b' = 'w'): RoundRecord {
  return { mode: 'run', openingId: '', color, answered: 1, correct: 1, perfect: true, at, line: line.split(' ') };
}

describe('a stub opening', () => {
  // What onboarding saves for a Queen's Gambit pick: its move order, no further.
  const stub = rep('w', 'd4 d5 c4');

  it('ends a round started inside it without asking a move, and that is a stub finish', () => {
    const begun = beginRun({ tree, reps: [stub], node: tree.root, color: 'w', seed: 1, toward: gambit, enter: true });
    expect(begun).not.toBeNull();
    const { source, run } = begun!;
    expect(run.played).toEqual(['d4', 'd5', 'c4']);
    const replied = opponentReply(source, run, mulberry32(1));
    expect(isUsersTurn(replied)).toBe(true);
    expect(atEdge(source, replied)).toBe(true);
    const done = finishPrep(replied);
    expect(isStubFinish(done)).toBe(true);
  });

  it('is not a stub finish once a move of yours was found', () => {
    const full = rep('w', 'd4 d5 c4 e6 Nc3');
    const begun = beginRun({ tree, reps: [full], node: tree.root, color: 'w', seed: 1, toward: gambit, enter: true })!;
    let run = begun.run;
    const pick = mulberry32(2);
    while (!isUsersTurn(run) || movesHere(begun.source, run).length === 0) {
      run = opponentReply(begun.source, run, pick);
      if (run.played.length > 6) break;
    }
    // Whatever Black played, a prepared answer counts, and anything else is the edge.
    const prepared = begun.source.prepAt(run.fen);
    if (prepared.length) run = play(begun.source, run, prepared[0]).run;
    const done = finishPrep(run);
    expect(isStubFinish(done)).toBe(prepared.length === 0);
  });

  it('offers to grow from the reply the round ended on', () => {
    const played = ['d4', 'd5', 'c4', 'e6'];
    const opening = offerOpening(tree, tree.root, gambit, played);
    expect(opening.id).toBe(gambit.id);
    const launch = growLaunch(stub, index, tree, opening, played, opts);
    expect(launch?.hole?.san).toBe('e6');
    expect(launch?.hole?.path).toEqual(['d4', 'd5', 'c4']);
    expect(launch?.hole?.after).toBe(walkSan(played).fens[4]);
    expect(launch?.row.name).toBe(gambit.name);
    // And Growth starts standing on it, with you to answer.
    const run = startGrowthAt(stub, launch!.row, launch!.hole!);
    expect(run.path).toEqual(played);
    expect(atHole(stub, run)).toBe(true);
    expect(answerHole(run, 'Nc3')?.path).toEqual([...played, 'Nc3']);
  });

  it('names your last move for the card', () => {
    expect(yourLastMove(['d4', 'd5', 'c4', 'e6'], 'w')).toBe('2.c4');
    expect(yourLastMove(['d4', 'Nf6', 'c4', 'g6', 'Nc3'], 'b')).toBe('2...g6');
    expect(yourLastMove(['e4'], 'b')).toBeNull();
  });
});

describe('where growing starts', () => {
  const stub = rep('w', 'd4 d5 c4');

  it('does not start at a position with your move prepared', () => {
    expect(holeAtEnd(rep('w', 'd4 d5 c4 e6 Nc3'), index, ['d4', 'd5', 'c4', 'e6'], 18)).toBeNull();
  });

  it('does not start on the opponent to move', () => {
    expect(holeAtEnd(stub, index, ['d4', 'd5', 'c4'], 18)).toBeNull();
  });

  it('falls back to the opening\'s most urgent gap when the line is already as deep as Growth goes', () => {
    const played = ['d4', 'd5', 'c4', 'e6'];
    const launch = growLaunch(stub, index, tree, gambit, played, { ...opts, maxPly: 4 });
    expect(launch).not.toBeNull();
    expect(launch!.hole).toBeNull();
    expect(launch!.row.holes.length).toBeGreaterThan(0);
  });
});

describe('ready to grow', () => {
  const kid = nodeById(tree, 'd4 Nf6 c4 g6 Nc3');
  const CLASSICAL = 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O';
  const SAMISCH = 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f3 O-O';
  const black = rep('b', CLASSICAL, SAMISCH);
  const added = Math.max(...Object.values(black.nodes).map((node) => node.addedAt));

  it('needs every line finished clean enough times', () => {
    const rounds = [
      ...Array.from({ length: CLEAN_FINISHES }, (_, i) => clean(CLASSICAL, added + 1 + i, 'b')),
      ...Array.from({ length: CLEAN_FINISHES - 1 }, (_, i) => clean(SAMISCH, added + 10 + i, 'b')),
    ];
    expect(readyToGrow(black, tree, kid, rounds)).toBe(false);
    expect(readyToGrow(black, tree, kid, [...rounds, clean(SAMISCH, added + 20, 'b')])).toBe(true);
  });

  it('counts only clean Run rounds on your side', () => {
    const rounds = [CLASSICAL, SAMISCH].flatMap((line) =>
      Array.from({ length: CLEAN_FINISHES }, (_, i) => clean(line, added + 1 + i, 'b')),
    );
    const spoiled = rounds.map((round, i) => (i === 0 ? { ...round, perfect: false } : round));
    expect(readyToGrow(black, tree, kid, spoiled)).toBe(false);
    const drill = rounds.map((round, i) => (i === 0 ? { ...round, mode: 'drill' as const } : round));
    expect(readyToGrow(black, tree, kid, drill)).toBe(false);
    const white = rounds.map((round, i) => (i === 0 ? { ...round, color: 'w' as const } : round));
    expect(readyToGrow(black, tree, kid, white)).toBe(false);
    expect(readyToGrow(black, tree, kid, rounds)).toBe(true);
  });

  it('starts a line again from nothing once a move is added to it', () => {
    const rounds = [CLASSICAL, SAMISCH].flatMap((line) =>
      Array.from({ length: CLEAN_FINISHES }, (_, i) => clean(line, added + 1 + i, 'b')),
    );
    const grown = addLine(black, `${CLASSICAL} Be2 e5`.split(' '), 'reference').rep;
    const tip = leafLines(grown).find((line) => line.sans.length === 12)!;
    grown.nodes[tip.tipId] = { ...grown.nodes[tip.tipId], addedAt: added + 100 };
    const finishes = lineFinishes(grown, tree, kid, rounds);
    expect(finishes.find((line) => line.tipId === tip.tipId)?.finishes).toBe(0);
    expect(readyToGrow(grown, tree, kid, rounds)).toBe(false);
  });

  it('is never ready with no lines in the opening', () => {
    expect(readyToGrow(rep('b', 'e4 c5'), tree, kid, [])).toBe(false);
  });

  it('names the family the round ended in, not the variation', () => {
    const opening = offerOpening(tree, tree.root, null, SAMISCH.split(' '));
    expect(opening.name).toBe("King's Indian Defence");
  });

  it('names what you chose, when you chose something', () => {
    expect(offerOpening(tree, kid, null, SAMISCH.split(' ')).id).toBe(kid.id);
  });
});
