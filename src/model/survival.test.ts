import { describe, expect, it } from 'vitest';
import { walkSan } from '../chess/core';
import { nodeById, openingTree } from './openingTree';
import { addLine, createRepertoire } from './repertoire';
import { referenceIndex } from './referenceIndex';
import { mulberry32 } from './session';
import { bookMoves, inTheBook, isBookMove, SCORE_SLIGHT, bookReply, prepSummary, secondsText, speedTone, DEFAULT_SURVIVAL, comboAfter, comboMultiplier, firstMission, isMoment, judgedExtras, missionFor, missionText, planMission, momentBonus, MISSION_BONUS, MISSION_BREAK, NO_EXTRAS, stepMission, type Extras, glowFor, moveScore, evalSwing, moveNumber, normalizeSurvival, openingsAlong, playTheirs, playYours, prepHere, recentForm, RECENT_RUNS, HISTORY_RUNS, recordEndedSurvival, recordSurvival, startSurvival, SURVIVAL_STEERS, survivalFor, survivalSteerLabel, type SurvivalRun } from './survival';
import type { Repertoire } from './types';
import { EMPTY_SURVIVAL_RECORD } from '../test/helpers';

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

  it('only plays book moves, plus the replies you prepared', () => {
    const indian = nodeById(tree, 'd4 Nf6');
    let stub = createRepertoire('Black', 'b', 'rep_b');
    stub = addLine(stub, ['d4', 'Nf6'], 'picker').rep;
    const run = startSurvival({ steer: 'lines', tree, reps: [stub], node: indian, color: 'b', seed: 1 })!;
    const at = { ...run.state, run: { ...run.state.run, ...runAt(['d4', 'Nf6']) } };
    const seen = new Set<string>();
    const rand = mulberry32(7);
    for (let i = 0; i < 400; i++) seen.add(bookReply(run.source, index, at, rand)!);
    // 2.c3 and the other sub-5% moves are never rolled.
    expect([...seen].sort()).toEqual(['Nf3', 'c4', 'Nc3', 'Bg5'].sort());
    // A reply you prepared is still played, however rare.
    stub = addLine(stub, ['d4', 'Nf6', 'c3', 'g6'], 'growth').rep;
    const kept = startSurvival({ steer: 'lines', tree, reps: [stub], node: indian, color: 'b', seed: 1 })!;
    expect(kept.source.weightsAt(at.run.fen, at.run.played).map((w) => w.san)).toContain('c3');
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
    expect(survivalFor(record, '')).toEqual({ best: 12, recent: [12], history: [12], runs: 1, ended: 1, bestPoints: 12 });
    // Points are kept beside moves, never in place of them.
    expect(recordSurvival(record, tree, KID, 5, 40).global).toMatchObject({ best: 12, bestPoints: 40 });
    expect(survivalFor(record, kid).ended).toBe(1);
  });

  it('recent form is the median, and nothing before a run', () => {
    expect(recentForm(undefined)).toBeNull();
    expect(recentForm({ best: 9, recent: [9, 1, 5], history: [], runs: 3, ended: 0, bestPoints: 0 })).toBe(5);
    expect(recentForm({ best: 9, recent: [2, 4, 9, 6], history: [], runs: 4, ended: 0, bestPoints: 0 })).toBe(5);
  });

  it('reads a save with nothing in it', () => {
    expect(normalizeSurvival(undefined)).toEqual(EMPTY_SURVIVAL_RECORD);
    expect(normalizeSurvival({ global: { best: 3 } as never }).global).toEqual({ best: 3, recent: [], history: [], runs: 0, ended: 0, bestPoints: 0 });
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

describe('past the opening', () => {
  const all = { moments: true, missions: true, combo: true };

  it('has moments, missions and the combo on by default', () => {
    expect(DEFAULT_SURVIVAL.moments && DEFAULT_SURVIVAL.missions && DEFAULT_SURVIVAL.combo).toBe(true);
  });

  it('builds the combo on clean moves, holds it on near ones, breaks it on worse', () => {
    expect(comboAfter(2, 0)).toBe(3);
    expect(comboAfter(2, 20)).toBe(3);
    expect(comboAfter(2, 35)).toBe(2);
    expect(comboAfter(2, 41)).toBe(0);
    expect([0, 2, 3, 5, 6, 9, 10, 30].map(comboMultiplier)).toEqual([1, 1, 2, 2, 3, 3, 4, 4]);
  });

  it('calls a moment on a big gap that leaves you ahead, from your side', () => {
    expect(isMoment('w', 250, 50)).toBe(true);
    // Escaping trouble is not a moment.
    expect(isMoment('w', 0, -300)).toBe(false);
    expect(isMoment('w', 200, 100)).toBe(false);
    expect(isMoment('b', -250, -50)).toBe(true);
    expect(isMoment('w', 10_000, 40)).toBe(true);
    expect(isMoment('w', 10_000, 10_000)).toBe(false);
    expect(isMoment('w', 400, null)).toBe(false);
    expect([0, 1, 2].map(momentBonus)).toEqual([10, 15, 20]);
  });

  it('sets the mission the eval calls for', () => {
    expect(missionFor('w', 150).kind).toBe('edge');
    expect(missionFor('w', 0).kind).toBe('lead');
    expect(missionFor('w', -150).kind).toBe('dig');
    expect(missionFor('b', -150).kind).toBe('edge');
  });

  it('keeps an edge for ten moves, and fails it on dropping below +1', () => {
    let mission = missionFor('w', 150);
    for (let i = 0; i < 9; i++) {
      const step = stepMission(mission, 'w', 120);
      expect(step.result).toBeNull();
      mission = step.mission;
    }
    expect(stepMission(mission, 'w', 120).result).toBe('done');
    expect(stepMission(missionFor('w', 150), 'w', 90).result).toBe('failed');
  });

  it('takes the lead or digs in within fifteen moves', () => {
    expect(stepMission(missionFor('w', 0), 'w', 100).result).toBe('done');
    let lead = missionFor('w', 0);
    for (let i = 0; i < 14; i++) lead = stepMission(lead, 'w', 50).mission;
    expect(stepMission(lead, 'w', 50).result).toBe('failed');
    expect(stepMission(missionFor('w', -200), 'w', -50).result).toBe('done');
  });

  it('pays each judged move its multiplier, and bonuses on top', () => {
    let extras: Extras = { ...NO_EXTRAS, combo: 2 };
    const clean = judgedExtras(extras, all, 'w', { lost: 0, after: 0, moment: false, found: false });
    expect(clean.extras.combo).toBe(3);
    expect(clean.earned.points).toBe(2);
    expect(clean.earned.combo).toBe('up');

    const found = judgedExtras(clean.extras, all, 'w', { lost: 0, after: 300, moment: true, found: true });
    expect(found.earned.moment).toEqual({ found: true, bonus: 10 });
    expect(found.earned.points).toBe(2 + 10);
    expect(found.extras.moments.streak).toBe(1);

    const missed = judgedExtras(found.extras, all, 'w', { lost: 200, after: 50, moment: true, found: false });
    expect(missed.extras.combo).toBe(0);
    expect(missed.extras.moments).toEqual({ found: 1, missed: 1, streak: 0 });
    expect(missed.earned.points).toBe(1);

    extras = { ...NO_EXTRAS, mission: { kind: 'lead', moves: 3, held: 0 } };
    const led = judgedExtras(extras, all, 'w', { lost: 0, after: 120, moment: false, found: false });
    expect(led.earned.mission).toEqual({ kind: 'lead', result: 'done', bonus: MISSION_BONUS });
    expect(led.extras.mission).toBeNull();
    expect(led.extras.missionBreak).toBe(MISSION_BREAK);
  });

  it('sets the next mission after a three-move break', () => {
    let extras: Extras = { ...NO_EXTRAS, missionBreak: MISSION_BREAK };
    for (let i = 0; i < MISSION_BREAK; i++) {
      extras = judgedExtras(extras, all, 'w', { lost: 0, after: 200, moment: false, found: false }).extras;
    }
    expect(extras.mission?.kind).toBe('edge');
  });

  it('scores moves survived as points with every extra off', () => {
    const off = { moments: false, missions: false, combo: false };
    let extras = NO_EXTRAS;
    for (let i = 0; i < 12; i++) {
      extras = judgedExtras(extras, off, 'w', { lost: 0, after: 400, moment: true, found: true }).extras;
    }
    expect(extras.points).toBe(12);
    expect(extras.mission).toBeNull();
    expect(firstMission(NO_EXTRAS, off, 'w', 0)).toBe(NO_EXTRAS);
    expect(firstMission(NO_EXTRAS, all, 'w', 0).mission?.kind).toBe('lead');
  });
});

describe('plan and Convert it missions', () => {
  const carlsbad = 'r1bq1rk1/pp1nbppp/2p2n2/3p2B1/3P4/2NBP3/PPQ2PPP/R3K1NR w KQ - 0 1';
  const all = { missions: true };

  it('sets the plan as the first mission where the pawns form a structure', () => {
    const mission = planMission(carlsbad, 'w', 30)!;
    expect(mission).toMatchObject({ kind: 'plan', start: 30 });
    // Every square the plan names, so no one push is the "right" move.
    expect(mission.goals).toEqual(expect.arrayContaining([{ piece: 'p', to: 'b5' }, { piece: 'n', to: 'e5' }]));
    expect(missionText(mission)).toBe('Follow the plan · 8 moves left');
    expect(firstMission(NO_EXTRAS, all, 'w', 30, carlsbad).mission?.kind).toBe('plan');
    // No structure, no plan: the eval's mission as before.
    expect(planMission('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 'w', 0)).toBeNull();
  });

  it('completes the plan once the piece is there, and fails it on a lost pawn or the clock', () => {
    const mission = planMission(carlsbad, 'w', 30)!;
    const there = 'r1bq1rk1/pp1nbppp/2p2n2/1P1p2B1/3P4/2NBP3/P1Q2PPP/R3K1NR b KQ - 0 1';
    expect(stepMission(mission, 'w', 20, there).result).toBe('done');
    expect(stepMission(mission, 'w', -90, there).result).toBe('failed');
    // Any of the plan's squares will do: a knight on e5 instead of the minority attack.
    const knight = 'r1bq1rk1/pp1nbppp/2p2n2/3pN1B1/3P4/2NBP3/PPQ2PPP/R3K2R b KQ - 0 1';
    expect(stepMission(mission, 'w', 20, knight).result).toBe('done');
    // A mission saved with one square still completes on it.
    expect(stepMission({ kind: 'plan', moves: 0, held: 0, goal: { piece: 'p', to: 'b5' }, start: 30 }, 'w', 20, there).result).toBe('done');
    let waiting = mission;
    for (let i = 0; i < 7; i++) waiting = stepMission(waiting, 'w', 30, carlsbad).mission;
    expect(stepMission(waiting, 'w', 30, carlsbad).result).toBe('failed');
  });

  it('asks you to convert when well ahead, done once a piece each has come off', () => {
    const mission = missionFor('w', 250, carlsbad);
    expect(mission).toMatchObject({ kind: 'convert', pieces: { mine: 7, theirs: 7 } });
    expect(missionFor('w', 250).kind).toBe('edge');
    const traded = 'r1bq1rk1/pp1nbppp/2p5/3p2B1/3P4/3BP3/PPQ2PPP/R3K1NR w KQ - 0 1';
    expect(stepMission(mission, 'w', 260, traded).result).toBe('done');
    expect(stepMission(mission, 'w', 150, traded).result).toBe(null);
    expect(stepMission(mission, 'w', 80, carlsbad).result).toBe('failed');
  });
});

describe("Autopilot's prep speed", () => {
  it('colors a time by the grade it earns its card', () => {
    expect(speedTone(1.2)).toBe('up');
    expect(speedTone(5)).toBe('slight');
    expect(speedTone(12)).toBe('bad');
    expect(secondsText(2.345)).toBe('2.3s');
    expect(secondsText(14.6)).toBe('15s');
  });

  it('sums a run up as found of asked, the average time and how many were fast', () => {
    expect(prepSummary(3, 4, [1, 2, 6])).toBe('Prep 3 of 4 · 3.0s average · 2 fast');
    expect(prepSummary(0, 2, [])).toBe('Prep 0 of 2');
    expect(prepSummary(0, 0, [])).toBeNull();
  });
});

describe('the book phase', () => {
  const qg = walkSan(['d4', 'd5', 'c4']).fens.at(-1)!;

  it('takes the moves strong players play, most played first', () => {
    const moves = bookMoves(index, qg);
    expect(moves.length).toBeGreaterThan(1);
    expect(moves).toContain('e6');
    expect(moves).toContain('c6');
  });

  it('leaves out a legal move the book has no games of', () => {
    expect(bookMoves(index, qg)).not.toContain('a5');
  });

  it('passes a book move only when the engine does not call it a mistake', () => {
    expect(isBookMove(index, qg, 'e6', 0)).toBe(true);
    expect(isBookMove(index, qg, 'e6', SCORE_SLIGHT)).toBe(true);
    expect(isBookMove(index, qg, 'e6', SCORE_SLIGHT + 1)).toBe(false);
    expect(isBookMove(index, qg, 'a5', 0)).toBe(false);
  });

  it('ends where the book has nothing', () => {
    expect(inTheBook(index, qg)).toBe(true);
    const silly = walkSan(['a4', 'h5', 'Ra3', 'Rh6', 'Rg3', 'Ra6']).fens.at(-1)!;
    expect(inTheBook(index, silly)).toBe(false);
    expect(bookMoves(index, silly)).toEqual([]);
  });

  it('counts book moves on the end screen', () => {
    expect(prepSummary(2, 2, [1, 2], 3)).toBe('Prep 2 of 2 · 1.5s average · 2 fast · 3 book moves');
    expect(prepSummary(0, 0, [], 1)).toBe('1 book move');
  });
});
