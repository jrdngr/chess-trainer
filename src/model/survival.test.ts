import { describe, expect, it } from 'vitest';
import { walkSan } from '../chess/core';
import { nodeById, openingTree } from './openingTree';
import { addLine, createRepertoire } from './repertoire';
import { referenceIndex } from './referenceIndex';
import { mulberry32 } from './session';
import {
  bookReply,
  DEFAULT_SURVIVAL,
  glowFor,
  moveScore,
  evalSwing,
  EMPTY_SURVIVAL_RECORD,
  moveNumber,
  normalizeSurvival,
  openingsAlong,
  playTheirs,
  playYours,
  prepHere,
  recentForm,
  RECENT_RUNS,
  HISTORY_RUNS,
  recordEndedSurvival,
  recordSurvival,
  startSurvival,
  SURVIVAL_STEERS,
  survivalFor,
  survivalSteerLabel,
  type SurvivalRun,
} from './survival';
import type { Repertoire } from './types';

const index = referenceIndex();
const tree = openingTree(index);

function whiteRep(): Repertoire {
  let rep = createRepertoire('White', 'w', 'rep_w');
  rep = addLine(rep, ['d4', 'd5', 'c4', 'e6', 'Nc3', 'Nf6', 'cxd5', 'exd5', 'Bg5'], 'seed').rep;
  rep = addLine(rep, ['d4', 'd5', 'c4', 'c6', 'Nf3', 'Nf6', 'Nc3', 'dxc4', 'a4'], 'seed').rep;
  return rep;
}

const KID = ['d4', 'Nf6', 'c4', 'g6', 'Nc3', 'Bg7', 'e4', 'd6', 'Nf3', 'O-O', 'Be2', 'e5'];

describe('Survival options', () => {
  it('offers three steers, My lines first and by default', () => {
    expect(SURVIVAL_STEERS).toEqual(['lines', 'gaps', 'book']);
    expect(DEFAULT_SURVIVAL.steer).toBe('lines');
    expect(SURVIVAL_STEERS.map(survivalSteerLabel)).toEqual(['My lines', 'My gaps', 'Ignore my lines']);
  });
});

describe('starting a run', () => {
  it('steers into your lines from move one', () => {
    const begun = startSurvival({ steer: 'lines', tree, reps: [whiteRep()], node: tree.root, color: 'w', seed: 3 });
    expect(begun).not.toBeNull();
    expect(begun!.state.moves).toBe(0);
    expect(begun!.state.run.played).toEqual([]);
    expect(begun!.state.run.target[0]).toBe('d4');
    expect(prepHere(begun!.source, begun!.state)).toEqual(['d4']);
  });

  it('ignoring your lines still knows your prep, to catch a miss', () => {
    const begun = startSurvival({ steer: 'book', tree, reps: [whiteRep()], node: tree.root, color: 'w', seed: 3 });
    expect(begun!.state.run.bookRun).toBe(true);
    expect(begun!.state.run.repertoireId).toBe('rep_w');
    expect(prepHere(begun!.source, begun!.state)).toEqual(['d4']);
  });
});

describe('playing', () => {
  const begun = startSurvival({ steer: 'lines', tree, reps: [whiteRep()], node: tree.root, color: 'w', seed: 3 })!;

  it('counts every move of yours, and keeps a miss with the move you should have played', () => {
    let state: SurvivalRun = playYours(begun.state, 'd4');
    state = playTheirs(state, 'd5');
    state = playYours(state, 'Nf3', 'c4');
    expect(state.moves).toBe(2);
    expect(state.run.played).toEqual(['d4', 'd5', 'Nf3']);
    expect(state.misses).toEqual([
      { ply: 2, fen: walkSan(['d4', 'd5']).fens[2], played: 'Nf3', expected: 'c4' },
    ]);
  });

  it('plays the book past the opening, and hands over to the engine once the book is silent', () => {
    const rand = mulberry32(5);
    const inBook = { ...begun.state, run: { ...begun.state.run, ...runAt(['e4', 'e5']) } };
    expect(bookReply(begun.source, index, { ...inBook, run: { ...inBook.run, ...runAt(['e4', 'e5', 'Nf3']) } }, rand)).toBeTruthy();
    const nowhere = ['a4', 'h5', 'Ra3', 'Rh6', 'Rb3', 'Rg6', 'Rc3', 'Rf6'];
    expect(bookReply(begun.source, index, { ...inBook, run: { ...inBook.run, ...runAt(nowhere) } }, rand)).toBeNull();
  });

  it('numbers moves the way a score sheet does', () => {
    expect(moveNumber(0)).toBe(1);
    expect(moveNumber(1)).toBe(1);
    expect(moveNumber(46)).toBe(24);
  });
});

function runAt(sans: string[]) {
  return { fen: walkSan(sans).fens[sans.length], played: sans, target: [] as string[] };
}

describe('the record', () => {
  it('credits every opening the line went through, and the ones above them', () => {
    const along = openingsAlong(tree, KID);
    const names = along.map((id) => nodeById(tree, id).name);
    expect(names.some((name) => name.startsWith("King's Indian"))).toBe(true);
    // Deeper King's Indian lines count as well as the family.
    expect(names.filter((name) => name.startsWith("King's Indian")).length).toBeGreaterThan(1);
    expect(along).not.toContain(tree.root.id);
  });

  it('keeps a best per opening and overall, and recent form over the last few runs', () => {
    let record = EMPTY_SURVIVAL_RECORD;
    record = recordSurvival(record, tree, KID, 20);
    record = recordSurvival(record, tree, KID.slice(0, 4), 8);
    const kid = openingsAlong(tree, KID.slice(0, 6)).find((id) => nodeById(tree, id).name.startsWith("King's Indian"))!;
    expect(survivalFor(record, '').best).toBe(20);
    expect(survivalFor(record, '').runs).toBe(2);
    expect(survivalFor(record, kid).best).toBe(20);
    expect(survivalFor(record, kid).runs).toBe(1);
    for (let i = 0; i < RECENT_RUNS + 2; i += 1) record = recordSurvival(record, tree, KID, 4);
    expect(survivalFor(record, '').recent).toHaveLength(RECENT_RUNS);
    expect(survivalFor(record, '').best).toBe(20);
    expect(recentForm(survivalFor(record, ''))).toBe(4);
  });

  it('counts a run you ended yourself apart from best and recent form', () => {
    let record = recordSurvival(EMPTY_SURVIVAL_RECORD, tree, KID, 12);
    record = recordEndedSurvival(record, tree, KID);
    const kid = openingsAlong(tree, KID.slice(0, 6)).find((id) => nodeById(tree, id).name.startsWith("King's Indian"))!;
    expect(survivalFor(record, '')).toEqual({ best: 12, recent: [12], history: [12], runs: 1, ended: 1 });
    expect(survivalFor(record, kid).ended).toBe(1);
  });

  it('recent form is the median, and nothing before a run', () => {
    expect(recentForm(undefined)).toBeNull();
    expect(recentForm({ best: 9, recent: [9, 1, 5], history: [], runs: 3, ended: 0 })).toBe(5);
    expect(recentForm({ best: 9, recent: [2, 4, 9, 6], history: [], runs: 4, ended: 0 })).toBe(5);
  });

  it('reads a save with nothing in it', () => {
    expect(normalizeSurvival(undefined)).toEqual(EMPTY_SURVIVAL_RECORD);
    expect(normalizeSurvival({ global: { best: 3 } as never }).global).toEqual({ best: 3, recent: [], history: [], runs: 0, ended: 0 });
  });

  it('keeps a longer history than recent form, seeded from it on old saves', () => {
    let record = EMPTY_SURVIVAL_RECORD;
    for (let i = 1; i <= HISTORY_RUNS + 3; i += 1) record = recordSurvival(record, tree, KID, i);
    expect(survivalFor(record, '').history).toHaveLength(HISTORY_RUNS);
    expect(survivalFor(record, '').history.at(-1)).toBe(HISTORY_RUNS + 3);
    expect(normalizeSurvival({ global: { best: 5, recent: [3, 5], runs: 2 } as never }).global.history).toEqual([3, 5]);
  });
});

describe('Survival feedback', () => {
  it('is on by default', () => {
    expect(DEFAULT_SURVIVAL.moveScores).toBe(true);
    expect(DEFAULT_SURVIVAL.boardGlow).toBe(true);
  });

  it('never shows a zero', () => {
    expect(moveScore(0)).toBeNull();
    expect(moveScore(0.4)).toBeNull();
    expect(moveScore(-0.4)).toBeNull();
  });

  it('shows gains in green and losses in yellow or red', () => {
    expect(moveScore(120)).toEqual({ cp: 120, tone: 'up' });
    expect(moveScore(-18)).toEqual({ cp: -18, tone: 'slight' });
    expect(moveScore(-40)).toEqual({ cp: -40, tone: 'slight' });
    expect(moveScore(-41)).toEqual({ cp: -41, tone: 'bad' });
  });

  it('measures a swing from your side, and not across a mate', () => {
    expect(evalSwing('w', 20, 150)).toBe(130);
    expect(evalSwing('b', 20, 150)).toBe(-130);
    expect(evalSwing('w', 20, 10_000)).toBeNull();
  });

  it('reads the glow from your side of the board', () => {
    expect(glowFor('w', 0)).toBeNull();
    expect(glowFor('w', 99)).toBeNull();
    expect(glowFor('w', -99)).toBeNull();
    expect(glowFor('w', 100)).toEqual({ tone: 'green', strength: 0 });
    expect(glowFor('w', 300)).toEqual({ tone: 'green', strength: 0.5 });
    expect(glowFor('b', -900)).toEqual({ tone: 'green', strength: 1 });
    expect(glowFor('w', -100)?.tone).toBe('yellow');
    expect(glowFor('w', -299)?.tone).toBe('yellow');
    expect(glowFor('w', -150)).toEqual({ tone: 'yellow', strength: 0.5 });
    expect(glowFor('w', -300)).toEqual({ tone: 'red', strength: 0.5 });
    expect(glowFor('w', -500)).toEqual({ tone: 'red', strength: 0.75 });
    expect(glowFor('b', 10_000)).toEqual({ tone: 'red', strength: 1 });
  });
});
