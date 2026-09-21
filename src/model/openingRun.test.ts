import { describe, expect, it } from 'vitest';
import { applySan, fenTurn, positionKey, START_FEN, walkSan } from '../chess/core';
import {
  atEdge,
  beginRun,
  BLUNDER_LIMIT,
  DRAW_WINDOW,
  bookHas,
  chooseAtEdge,
  classify,
  clockLabel,
  clockSeconds,
  CLOCK_MODES,
  continuation,
  DEFAULT_OPTIONS,
  edgeOptions,
  EMPTY_RECORD,
  evalLoss,
  finishPrep,
  fullLine,
  gradeLabel,
  gradeOf,
  GRADES,
  isComplete,
  isUsersTurn,
  movesToFit,
  judgeByEval,
  keepPlaying,
  leavePrep,
  lineName,
  lineOdds,
  lineToKeep,
  lineWeakness,
  movesHere,
  NEW_MOVE_BUDGETS,
  normalizeRecord,
  opponentReply,
  outcomeOf,
  play,
  playedIsLegal,
  playPast,
  playReply,
  recordRun,
  regionSource,
  resolveColor,
  revealText,
  staysInside,
  steerLabel,
  STEERS,
  takeHint,
  wayIn,
  weaknessFromCards,
  type LineSource,
  type Run,
  type Weakness,
} from './openingRun';
import { findHoles } from './growth';
import { markSeen } from './freshness';
import { lineStatus, nodeById, openingTree } from './openingTree';
import { addLine, createRepertoire, hasLine, leafLines, pathTo } from './repertoire';
import { lookup } from './reference';
import { referenceIndex } from './referenceIndex';
import { cardId, mulberry32 } from './session';
import { buildSeedRepertoires } from '../store/seed';
import type { Card, Repertoire } from './types';

const index = referenceIndex();
const tree = openingTree(index);
const any = tree.root;
const byName = (name: string) => {
  const found = [...tree.byId.values()].find((node) => node.name === name);
  if (!found) throw new Error(`no node named ${name}`);
  return found;
};

function whiteRep(): Repertoire {
  let rep = createRepertoire('White', 'w', 'rep_w');
  rep = addLine(rep, ['d4', 'd5', 'c4', 'e6', 'Nc3', 'Nf6', 'cxd5', 'exd5', 'Bg5'], 'seed').rep;
  rep = addLine(rep, ['d4', 'd5', 'c4', 'c6', 'Nf3', 'Nf6', 'Nc3', 'dxc4', 'a4'], 'seed').rep;
  return rep;
}

/** A run in a region on a repertoire, deterministic. */
function start(reps: Repertoire[], color: 'w' | 'b' | 'random', seed = 1, node = any, extra = {}) {
  const begun = beginRun({ tree, reps, node, color, seed, ...extra });
  if (!begun) throw new Error('no run');
  return begun;
}

/** Play a run out correctly, always taking the source's first move. */
function finish(source: LineSource, run: Run, seed = 1) {
  const pick = mulberry32(seed);
  let current = run;
  let guard = 0;
  while (!current.over && !isComplete(source, current) && guard < 90) {
    guard += 1;
    if (isUsersTurn(current)) {
      const options = movesHere(source, current);
      expect(options.length).toBeGreaterThan(0);
      current = play(source, current, options[0]).run;
    } else {
      current = opponentReply(source, current, pick);
    }
  }
  return current;
}

/** The position after these moves, as a run sitting on it. */
function at(base: Run, sans: string[]): Run {
  return { ...base, fen: walkSan(sans).fens[sans.length], played: sans, target: [] };
}

describe('beginning a run', () => {
  const reps = buildSeedRepertoires();

  it('draws one of your own lines through the region to steer the opponent', () => {
    const { run } = start([whiteRep()], 'w');
    expect(run.survived).toBe(0);
    expect(run.played).toEqual([]);
    expect(run.repertoireId).toBe('rep_w');
    expect(run.target.length).toBeGreaterThanOrEqual(7);
    expect(run.target[0]).toBe('d4');
  });

  it('honours the chosen colour, and resolves random up front', () => {
    for (let seed = 0; seed < 12; seed += 1) {
      expect(start(reps, 'w', seed).run.color).toBe('w');
      expect(start(reps, 'b', seed).run.color).toBe('b');
    }
    const colours = new Set<string>();
    for (let seed = 0; seed < 30; seed += 1) colours.add(start(reps, 'random', seed).run.color);
    expect([...colours].sort()).toEqual(['b', 'w']);
    expect(resolveColor('random', () => 0.1)).toBe('w');
    expect(resolveColor('random', () => 0.9)).toBe('b');
    expect(resolveColor('b', () => 0.1)).toBe('b');
  });

  it('runs through the book when nothing is prepared for that side', () => {
    const { run, source } = start([whiteRep()], 'b');
    expect(run.repertoireId).toBeUndefined();
    expect(run.target).toEqual([]);
    expect(movesHere(source, run).length).toBeGreaterThan(1);
  });

  it('walks you into the opening when the region is narrower than your prep', () => {
    const najdorf = byName('Sicilian Defence: Najdorf Variation');
    const { run } = start([whiteRep()], 'w', 1, najdorf);
    expect(run.target).toEqual(najdorf.sans);
    expect(run.openingId).toBe(najdorf.id);
    expect(run.sourceLabel).toBe('Sicilian Defence: Najdorf Variation');
  });

  it('draws a line inside the region when you have one', () => {
    const slav = byName('Slav Defence');
    const { run } = start([whiteRep()], 'w', 1, slav);
    expect(run.target.slice(0, 4)).toEqual(['d4', 'd5', 'c4', 'c6']);
  });

  it('takes a short line rather than none when the region has nothing long', () => {
    const shallow = addLine(createRepertoire('x', 'w', 'r'), ['d4', 'd5', 'c4'], 'seed').rep;
    expect(start([shallow], 'w', 1, any, { minDecisions: 4 }).run.target).toEqual(['d4', 'd5', 'c4']);
  });

  it('puts the user on move when they are White and waiting when Black', () => {
    expect(isUsersTurn(start(reps, 'w').run)).toBe(true);
    const black = start(reps, 'b').run;
    expect(isUsersTurn(black)).toBe(false);
    expect(fenTurn(black.fen)).toBe('w');
  });
});

describe('prepared or theory, inside the region', () => {
  const rep = whiteRep();

  it('accepts a prepared move, a theory move, and nothing else', () => {
    const { source, run } = start([rep], 'w');
    // The repertoire plays 1.d4; 1.e4 is theory; 1.a4 is nobody's move.
    expect(classify(source, run, 'd4')).toBe('prep');
    expect(classify(source, run, 'e4')).toBe('theory');
    // 1.Nh3 is one of the two first moves the book does not hold at all.
    expect(classify(source, run, 'Nh3')).toBe('miss');
    expect(play(source, run, 'e4').ok).toBe(true);
    expect(play(source, run, 'Nh3').ok).toBe(false);
    expect(movesHere(source, run)[0]).toBe('d4');
  });

  it('counts a theory move as plain where prep says nothing', () => {
    const { source, run } = start([rep], 'w');
    // Leaving the prep changes nothing about what a move is: off your prep, it goes to the engine.
    expect(classify(source, { ...run, leftPrep: true }, 'e4')).toBe('theory');
    // Past the end of the prepared lines the book is the only referee.
    const deep = at(run, ['d4', 'd5', 'c4', 'e6', 'Nc3', 'Nf6', 'cxd5', 'exd5', 'Bg5', 'Be7', 'e3', 'O-O']);
    expect(source.prepAt(deep.fen)).toEqual([]);
    expect(classify(source, deep, 'Bd3')).toBe('prep');
  });

  it('keeps the run inside the region on the way in', () => {
    const najdorf = byName('Sicilian Defence: Najdorf Variation');
    const { source, run } = start([rep], 'w', 1, najdorf);
    // Every first move offered has to be able to become a Najdorf. Several can:
    // 1.d4 c5 2.e4 and 1.Nf3 c5 2.e4 both transpose. Most cannot.
    const offered = movesHere(source, run);
    expect(offered).toContain('e4');
    for (const san of offered) expect(staysInside(tree, run, san)).toBe(true);
    // Most cannot, and are not offered: the region is a filter, not a list of
    // everything the book holds at move one.
    const firsts = lookup(referenceIndex(), START_FEN)!.moves.length;
    expect(offered.length).toBeLessThan(firsts / 2);
    // 1.d4 stays alive, because 1.d4 c5 2.e4 is a Sicilian.
    expect(staysInside(tree, run, 'd4')).toBe(true);
    // Once there, anything in the book keeps you alive.
    const inside = at(run, [...najdorf.sans, 'Be3']);
    expect(movesHere(source, inside).length).toBeGreaterThan(1);
  });

  it('lets the opponent only play moves that stay in the region', () => {
    const najdorf = byName('Sicilian Defence: Najdorf Variation');
    const { source, run } = start([rep], 'w', 1, najdorf);
    const played = play(source, run, 'e4').run;
    for (let seed = 0; seed < 10; seed += 1) {
      expect(opponentReply(source, played, mulberry32(seed)).played).toEqual(['e4', 'c5']);
    }
  });

  it('accepts a prepared alternative, and the opponent follows that branch', () => {
    const { source, run } = start([rep], 'w');
    const afterD4 = play(source, run, 'd4').run;
    const afterD5 = opponentReply(source, afterD4, () => 0.5);
    expect(afterD5.played).toEqual(['d4', 'd5']);
    const afterC4 = play(source, afterD5, 'c4').run;
    const branches = new Set<string>();
    for (let seed = 0; seed < 40; seed += 1) {
      branches.add(opponentReply(source, afterC4, mulberry32(seed)).played[3]);
    }
    expect(branches.has('e6') || branches.has('c6')).toBe(true);
  });

  it('plays a run to the end of the line and keeps the losing move out of the reveal', () => {
    const { source, run } = start([rep], 'w');
    const done = finish(source, run);
    expect(isComplete(source, done)).toBe(true);
    expect(playedIsLegal(done)).toBe(true);
    expect(done.survived).toBeGreaterThanOrEqual(4);

    const lost = play(source, at(run, ['d4', 'd5']), 'a4');
    expect(lost.ok).toBe(false);
    expect(lost.run.over).toBe(true);
    expect(lost.run.played).toEqual(['d4', 'd5']);
    expect(revealText(source, lost.run)).toContain('2. c4');
    expect(fullLine(source, lost.run).length).toBeGreaterThan(2);
  });

  it('accepts every prepared answer, not just the one line drawn', () => {
    const kid = buildSeedRepertoires().find((r) => r.name.includes('King'))!;
    const source = regionSource(tree, any, kid, 'b');
    const run = at(start([kid], 'b').run, ['d4', 'Nf6', 'c4', 'g6', 'Nc3', 'Bg7']);
    const options = movesHere(source, run);
    expect(options.length).toBeGreaterThan(1);
    for (const san of options) expect(play(source, run, san).ok).toBe(true);
  });

  it('plays out to the edge of the book without illegal moves', () => {
    const { source, run } = start([], 'w', 3);
    const done = finish(source, run, 3);
    expect(playedIsLegal(done)).toBe(true);
    expect(done.survived).toBeGreaterThan(3);
    expect(continuation(source, done)).toEqual([]);
  });

  it('lets the opponent favour popular replies', () => {
    const { source, run } = start([], 'w', 1);
    const afterE4 = play(source, run, 'e4').run;
    const counts = new Map<string, number>();
    for (let seed = 0; seed < 200; seed += 1) {
      const reply = opponentReply(source, afterE4, mulberry32(seed)).played[1];
      counts.set(reply, (counts.get(reply) ?? 0) + 1);
    }
    const c5 = counts.get('c5') ?? 0;
    expect(c5).toBeGreaterThan(50);
    expect(counts.size).toBeGreaterThan(2);
  });

  it('tells a real move apart from one nobody plays', () => {
    expect(bookHas(index, walkSan(['d4', 'd5']).fens[2], 'Nf3')).toBe(true);
    expect(bookHas(index, walkSan(['d4', 'd5']).fens[2], 'Na3')).toBe(false);
  });
});

describe('naming the line at the end of a run', () => {
  const reps = buildSeedRepertoires();

  it('names the variation, never something so generic it says nothing', () => {
    for (let seed = 0; seed < 8; seed += 1) {
      const { source, run } = start(reps, 'b', seed);
      const named = lineName(index, source, finish(source, run, seed));
      expect(named.name).not.toMatch(/Pawn Opening$/);
      expect(named.name.length).toBeGreaterThan(3);
    }
  });

  it('falls back to the region when the database only knows the opening vaguely', () => {
    const { source, run } = start([whiteRep()], 'w');
    const named = lineName(index, source, at(run, ['d4']), 99);
    expect(named.specific).toBe(false);
    expect(named.name).toBe('Any opening');
  });
});

describe('the record', () => {
  const rep = whiteRep();

  it('tracks runs, best depth, survivals and grades', () => {
    const { run } = start([rep], 'w');
    let record = recordRun(EMPTY_RECORD, outcomeOf({ ...run, survived: 4 }, 'blunder'), 1000);
    expect(record).toMatchObject({ runs: 1, best: 4, lastDepth: 4, survivals: 0, lastAt: 1000 });
    expect(record.grades).toEqual({ green: 0, yellow: 0, red: 1, purple: 0 });
    const other = start([rep], 'w', 2).run;
    record = recordRun(record, outcomeOf(finishPrep({ ...other, survived: 9 }), null), 2000);
    expect(record).toMatchObject({ runs: 2, best: 9, survivals: 1 });
    expect(record.grades.green).toBe(1);
  });

  it('files a run under its region and colour', () => {
    const najdorf = byName('Sicilian Defence: Najdorf Variation');
    const { run } = start([rep], 'w', 1, najdorf);
    expect(outcomeOf(run, 'blunder')).toMatchObject({ openingId: najdorf.id, color: 'w', label: 'Sicilian Defence: Najdorf Variation' });
  });

  it('counts a run completed once it reached the end of its prep, however it ended after', () => {
    const { run } = start([rep], 'w');
    expect(outcomeOf(run, null).completed).toBe(false);
    const done = finishPrep({ ...run, survived: 4 });
    expect(outcomeOf(done, null)).toMatchObject({ completed: true, grade: 'green', depth: 4 });
    // Kept playing and blundered: still completed, graded by the blunder.
    expect(outcomeOf(keepPlaying(done), 'blunder')).toMatchObject({ completed: true, grade: 'red' });
    // Left the prep and stopped at the checkpoint: never reached the end.
    const strayed = leavePrep(at(run, ['d4', 'd5']), 'Nf3');
    expect(outcomeOf(strayed, 'offprep')).toMatchObject({ completed: false, grade: 'purple' });
  });

  it('amends the record instead of counting the same run twice', () => {
    const { run } = start([rep], 'w');
    const done = finishPrep({ ...run, survived: 4 });
    let record = recordRun(EMPTY_RECORD, outcomeOf(done, null), 1000);
    expect(record).toMatchObject({ runs: 1, best: 4, survivals: 1 });
    record = recordRun(record, outcomeOf(keepPlaying(done), 'blunder'), 2000);
    expect(record).toMatchObject({ runs: 1, best: 4, survivals: 1, lastDepth: 4 });
    expect(record.grades).toEqual({ green: 0, yellow: 0, red: 1, purple: 0 });
    const other = start([rep], 'w', 2).run;
    expect(other.id).not.toBe(run.id);
    record = recordRun(record, outcomeOf({ ...other, survived: 3 }, 'blunder'), 3000);
    expect(record).toMatchObject({ runs: 2, best: 4, survivals: 1 });
  });

  it('moves the grade count when a run is amended', () => {
    const { run } = start([rep], 'w');
    let record = recordRun(EMPTY_RECORD, outcomeOf({ ...run, survived: 4 }, 'blunder'), 1000);
    const strayed = { ...leavePrep(at(run, ['d4', 'd5']), 'Nf3'), survived: 4 };
    record = recordRun(record, outcomeOf(strayed, 'offprep'), 2000);
    expect(record.runs).toBe(1);
    expect(record.grades).toEqual({ green: 0, yellow: 0, red: 0, purple: 1 });
  });

  it('reads a record missing fields', () => {
    const fixed = normalizeRecord({ runs: 2, best: 5 });
    expect(fixed.last).toBeUndefined();
    expect(fixed.grades).toEqual({ green: 0, yellow: 0, red: 0, purple: 0 });
    expect(
      recordRun(fixed, { id: 'x', grade: 'red', label: 'L', openingId: '', color: 'w', depth: 2, completed: false }).runs,
    ).toBe(3);
  });
});

describe('targeting weak spots', () => {
  const reps = buildSeedRepertoires();
  const rep = reps.find((r) => r.color === 'w')!;

  function lapsedCard(key: string, repertoireId: string): Card {
    return {
      id: cardId(repertoireId, key), repertoireId, key, fen: '', stage: 'review', step: 0,
      interval: 1, ease: 1.3, reps: 8, lapses: 6, correct: 1, incorrect: 7, due: 0,
      lastReviewed: 1, createdAt: 1,
    };
  }

  it('rates a lapsed position above one never seen, and both above a solid one', () => {
    const solid: Card = { ...lapsedCard('solid', rep.id), ease: 2.9, lapses: 0, correct: 9, incorrect: 0, due: Date.now() + 9e8 };
    const weakness = weaknessFromCards({
      [cardId(rep.id, 'bad')]: lapsedCard('bad', rep.id),
      [cardId(rep.id, 'solid')]: solid,
    });
    expect(weakness(rep.id, 'bad')).toBeGreaterThan(weakness(rep.id, 'unseen'));
    expect(weakness(rep.id, 'unseen')).toBeGreaterThan(weakness(rep.id, 'solid'));
  });

  it('counts what your games got wrong, on top of the schedule', () => {
    const plain = weaknessFromCards({});
    const slipped = weaknessFromCards({}, [{ kind: 'offprep', repertoireId: rep.id, key: 'k', games: 3 }]);
    expect(slipped(rep.id, 'k')).toBeGreaterThan(plain(rep.id, 'k'));
    expect(slipped(rep.id, 'other')).toBe(plain(rep.id, 'other'));
    // Reaching it with nothing prepared is a hole, not a slip: not counted here.
    const gap = weaknessFromCards({}, [{ kind: 'unprepared', repertoireId: rep.id, key: 'k', games: 3 }]);
    expect(gap(rep.id, 'k')).toBe(plain(rep.id, 'k'));
  });

  it('averages the appetite over the positions the line asks about', () => {
    const weakness: Weakness = (_id, key) => (key === 'hot' ? 7 : 1);
    expect(lineWeakness(rep.id, ['hot', 'hot'], weakness)).toBe(7);
    expect(lineWeakness(rep.id, ['hot', 'cold'], weakness)).toBe(4);
    expect(lineWeakness(rep.id, [], weakness)).toBe(1);
  });

  it('draws the line you are bad at far more often, and only when asked', () => {
    let two = createRepertoire('White', 'w', 'rep_two');
    const weak = ['d4', 'd5', 'c4', 'e6', 'Nc3', 'Nf6', 'Bg5', 'Be7'];
    two = addLine(two, weak, 'seed').rep;
    two = addLine(two, ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6', 'Ba4', 'Nf6'], 'seed').rep;
    const { fens } = walkSan(weak);
    const sore = new Set(fens.filter((_, i) => i % 2 === 0).slice(1).map(positionKey));
    const weakness: Weakness = (_id, key) => (sore.has(key) ? 40 : 1);
    const startsWeak = (run: Run) => weak.every((san, i) => run.target[i] === san);

    let on = 0;
    let off = 0;
    for (let seed = 0; seed < 60; seed += 1) {
      if (startsWeak(start([two], 'w', seed, any, { steer: 'weak', weakness }).run)) on += 1;
      if (startsWeak(start([two], 'w', seed, any, { weakness }).run)) off += 1;
    }
    expect(off).toBeGreaterThan(15);
    expect(off).toBeLessThan(45);
    expect(on).toBeGreaterThan(50);
  });
});

describe('the clock', () => {
  it('is a budget per move, or nothing', () => {
    expect(clockSeconds('off')).toBeNull();
    expect(clockSeconds('move10')).toBe(10);
    expect(clockSeconds('move30')).toBe(30);
  });

  it('labels every mode it offers', () => {
    for (const mode of CLOCK_MODES) expect(clockLabel(mode)).toBeTruthy();
  });
});

describe('hints', () => {
  const rep = whiteRep();

  it('spends one from the budget and names the square the prepared move starts on', () => {
    const { source, run } = start([rep], 'w', 1, any, { hints: 1 });
    const hint = takeHint(source, run)!;
    expect(hint.san).toBe('d4');
    expect(hint.from).toBe('d2');
    expect(hint.run.hints).toBe(0);
    expect(hint.run.hintsUsed).toBe(1);
    expect(hint.run.survived).toBe(run.survived);
    expect(takeHint(source, hint.run)).toBeNull();
  });

  it('defaults to none', () => {
    expect(DEFAULT_OPTIONS.hints).toBe(0);
    expect(start([rep], 'w').run.hints).toBe(0);
  });
});

describe('defaults', () => {
  it('turns every extra off: a popular line, nothing added', () => {
    expect(DEFAULT_OPTIONS).toEqual({ steer: 'popular', newMoves: 0, clock: 'off', hints: 0 });
    expect(NEW_MOVE_BUDGETS).toEqual([0, 1, 2, 3, 4, 5, 6, 7, 8]);
    for (const steer of STEERS) expect(steerLabel(steer)).toBeTruthy();
  });
});

describe('steering at gaps', () => {
  /** A Spanish and nothing else: every other Black reply to 1.e4 is a hole. */
  function spanish(): Repertoire {
    return addLine(createRepertoire('White', 'w', 'rep_sp'), ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5'], 'seed').rep;
  }

  it('walks the opponent to a reply you have no answer to', () => {
    const rep = spanish();
    const seen = new Set<string>();
    for (let seed = 0; seed < 40; seed += 1) {
      const { run } = start([rep], 'w', seed, any, { steer: 'gaps' });
      expect(run.target.length).toBeGreaterThanOrEqual(2);
      // Everything up to the reply is prep; the reply itself is not.
      expect(hasLine(rep, run.target.slice(0, -1))).toBe(true);
      expect(hasLine(rep, run.target)).toBe(false);
      expect(run.target.length % 2).toBe(0);
      seen.add(run.target.join(' '));
    }
    // Drawn, not fixed: more than one hole comes up.
    expect(seen.size).toBeGreaterThan(1);
  });

  it('lets what your games say decide which hole', () => {
    const rep = spanish();
    const after = applySan(applySan(START_FEN, 'e4')!.after, 'c5')!.after;
    const sicilian = positionKey(after);
    for (let seed = 0; seed < 20; seed += 1) {
      const { run } = start([rep], 'w', seed, any, {
        steer: 'gaps',
        holeWeight: (hole: { after: string }) => (positionKey(hole.after) === sicilian ? 1000 : 1),
      });
      expect(run.target).toEqual(['e4', 'c5']);
    }
  });

  it('spends its rounds on the replies it would actually meet', () => {
    const rep = spanish();
    const drawn = new Map<string, number>();
    for (let seed = 0; seed < 120; seed += 1) {
      const { run } = start([rep], 'w', seed, any, { steer: 'gaps' });
      const key = run.target.join(' ');
      drawn.set(key, (drawn.get(key) ?? 0) + 1);
    }
    // Every hole drawn is a reply worth a real share of the most played one,
    // so no round is spent on a move nobody plays while 1...c5 goes unmet.
    const holes = findHoles(rep, index);
    const met = (hole: { reach: number; share: number }) => hole.reach * hole.share;
    const best = Math.max(...holes.map(met));
    for (const key of drawn.keys()) {
      const hole = holes.find((h) => [...h.path, h.san].join(' ') === key)!;
      expect(met(hole) * DRAW_WINDOW).toBeGreaterThanOrEqual(best);
    }
    // The commonest reply leads, and more than one still comes up.
    const top = [...drawn].sort((a, b) => b[1] - a[1]);
    expect(top[0][0]).toBe('e4 c5');
    expect(drawn.size).toBeGreaterThan(1);
  });

  it('fits what a round adds to how much line is left to build', () => {
    expect(movesToFit(0)).toBeGreaterThanOrEqual(8);
    expect(movesToFit(4)).toBe(7);
    expect(movesToFit(8)).toBe(5);
    expect(movesToFit(14)).toBe(2);
    // Past the horizon there is still an answer worth having, never a line.
    expect(movesToFit(18)).toBe(1);
    expect(movesToFit(40)).toBe(1);
    // A shallow hole gets the whole allowance; a deep one only what it needs.
    const rep = spanish();
    const shallow = start([rep], 'w', 3, any, { steer: 'gaps', newMoves: 8 }).run;
    expect(shallow.newMoves).toBe(Math.min(8, movesToFit(shallow.target.length - 1)));
    expect(shallow.newMoves).toBeGreaterThan(4);
    // Never more than the run was allowed in the first place.
    const capped = start([rep], 'w', 3, any, { steer: 'gaps', newMoves: 2 }).run;
    expect(capped.newMoves).toBe(2);
  });

  it('falls back to a line through the opening when there is nothing to walk to', () => {
    // A region the prep never reaches has no holes inside it.
    const { run } = start([spanish()], 'w', 1, byName('Sicilian Defence'), { steer: 'gaps' });
    expect(run.target[0]).toBe('e4');
    expect(run.target[1]).toBe('c5');
  });
});

describe('not the same round twice', () => {
  const CLASSICAL = 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5';
  const SAMISCH = 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f3 O-O Be3 e5';
  function kid(...lines: string[]): Repertoire {
    let out = createRepertoire('Black', 'b', 'rep_kid');
    for (const line of lines) out = addLine(out, line.split(' '), 'seed').rep;
    return out;
  }

  it('remembers the line it was drawn on, whole', () => {
    const { run } = start([kid(CLASSICAL)], 'b', 1, any);
    expect(run.drawn).toEqual(run.target);
    // The edge spends the target; the record stays.
    const edge = chooseAtEdge({ ...run, newMoves: 1, fen: run.fen }, run.target[0]);
    expect(edge.target).toEqual([]);
    expect(edge.drawn).toEqual(run.target);
  });

  it('never draws the line the last round was drawn on while there is another', () => {
    const rep = kid(CLASSICAL, SAMISCH);
    const seen = { at: markSeen({}, CLASSICAL.split(' '), 7), round: 7 };
    for (let seed = 0; seed < 30; seed += 1) {
      const { run } = start([rep], 'b', seed, any, { seen });
      expect(run.drawn.join(' ')).toBe(SAMISCH);
    }
  });

  it('still runs the only line there is', () => {
    const rep = kid(CLASSICAL);
    const seen = { at: markSeen({}, CLASSICAL.split(' '), 7), round: 7 };
    expect(start([rep], 'b', 1, any, { seen }).run.drawn.join(' ')).toBe(CLASSICAL);
  });

  it('branches a young repertoire early rather than deepening the line just run', () => {
    // One line, just run. The hole at its tip is the same round with a move
    // on the end; the holes at move 9 are a different opening from there.
    const rep = kid(CLASSICAL + ' O-O Nc6 d5 Ne7');
    const seen = { at: markSeen({}, (CLASSICAL + ' O-O Nc6 d5 Ne7').split(' '), 3), round: 3 };
    const region = nodeById(tree, 'd4 Nf6 c4 g6 Nc3 Bg7 e4');
    for (let seed = 0; seed < 40; seed += 1) {
      const { run } = start([rep], 'b', seed, region, { steer: 'gaps', seen, newMoves: 8 });
      expect(run.target.length).toBeLessThanOrEqual(11);
    }
  });
});

describe('the first line of an opening', () => {
  const KID = 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5';
  const player = () => addLine(createRepertoire('Black', 'b', 'rep_b'), KID.split(' '), 'seed').rep;

  it('enters an opening with nothing in it by its own move order', () => {
    // A King's Indian player builds a Sämisch: 1.d4, as they play it — not
    // 1.c4, which is the hole on the way in met most often.
    const samisch = nodeById(tree, 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f3');
    for (let seed = 0; seed < 10; seed += 1) {
      const { run } = start([player()], 'b', seed, samisch, { steer: 'gaps', newMoves: 8 });
      expect(run.target).toEqual(samisch.sans);
    }
  });

  it('charges the budget for the opening, not for the way in', () => {
    const najdorf = nodeById(tree, 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6');
    const { run } = start([player()], 'b', 1, najdorf, { steer: 'gaps', newMoves: 8 });
    expect(run.target).toEqual(najdorf.sans);
    // Five of Black's moves just to get there, then what the opening wants.
    expect(run.newMoves).toBe(5 + Math.min(8, movesToFit(najdorf.sans.length)));
    // Prep all the way to the door: only the opening is budgeted.
    const samisch = nodeById(tree, 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f3');
    expect(start([player()], 'b', 1, samisch, { steer: 'gaps', newMoves: 8 }).run.newMoves).toBe(
      Math.min(8, movesToFit(samisch.sans.length)),
    );
  });

  it('grows an opening with a line in it from the inside, not from the way in', () => {
    const samisch = nodeById(tree, 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f3');
    const rep = addLine(player(), 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f3 O-O Be3 e5'.split(' '), 'seed').rep;
    for (let seed = 0; seed < 20; seed += 1) {
      const { run } = start([rep], 'b', seed, samisch, { steer: 'gaps', newMoves: 8 });
      // A hole past the door of the opening — never 1.c4, met in every game
      // and on its way to the Sämisch only by transposition.
      expect(run.target).not.toEqual(samisch.sans);
      expect(lineStatus(tree, samisch, run.target)).toBe('reached');
      expect(hasLine(rep, run.target)).toBe(false);
    }
  });

  it('walks the way in only once nothing inside is left to answer', () => {
    // Any opening as the region has no "inside" but the whole board; a first
    // move the prep cannot meet is the hole, as before.
    const rep = player();
    const { run } = start([rep], 'b', 1, any, { steer: 'gaps', newMoves: 8 });
    expect(run.target.length).toBe(1);
  });
});

describe('starting inside an opening', () => {
  const qgd = nodeById(tree, 'd4 d5 c4 e6');
  const slav = nodeById(tree, 'd4 d5 c4 c6');

  it('plays the way in for you, up to the first position the opening names', () => {
    const { run, source } = start([whiteRep()], 'w', 1, any, { toward: slav, enter: true });
    expect(run.opened).toBe(4);
    expect(run.played).toEqual(['d4', 'd5', 'c4', 'c6']);
    expect(run.fen).toBe(walkSan(run.played).fens[4]);
    expect(lineStatus(tree, slav, run.played)).toBe('reached');
    // The line drawn is still whole, and the run is on it.
    expect(run.target.slice(0, 4)).toEqual(run.played);
    expect(run.drawn).toEqual(run.target);
    // Nothing earned for it: the score is moves you found.
    expect(run.survived).toBe(0);
    expect(isUsersTurn(run)).toBe(true);
    expect(movesHere(source, run)).toContain('Nf3');
    expect(wayIn(tree, slav, ['d4', 'd5', 'c4', 'c6', 'Nf3'])).toEqual(['d4', 'd5', 'c4', 'c6']);
    // Called after the opening it was started in, not the region it was drawn in.
    expect(run.enteredIn).toBe(slav.id);
    expect(run.sourceLabel).toBe('Slav Defence');
    expect(run.openingId).toBe('');
  });

  it('enters by the drawn line, so a run toward a family lands in the variation drawn', () => {
    const gambit = nodeById(tree, 'd4 d5 c4');
    const { run } = start([whiteRep()], 'w', 1, any, { toward: gambit, enter: true });
    expect(run.opened).toBe(3);
    expect(run.played).toEqual(['d4', 'd5', 'c4']);
    expect(['e6', 'c6']).toContain(run.target[3]);
  });

  it('leaves a first move alone, and a run not asked to enter', () => {
    expect(start([whiteRep()], 'w', 1, any, { toward: nodeById(tree, 'd4'), enter: true }).run.opened).toBe(0);
    expect(start([whiteRep()], 'w', 1, any, { toward: qgd }).run.opened).toBe(0);
    expect(start([whiteRep()], 'w', 1, any, { toward: qgd }).run.enteredIn).toBeNull();
    expect(start([whiteRep()], 'w', 1, any, { toward: qgd }).run.sourceLabel).toBe('Any opening');
    expect(wayIn(tree, any, ['d4'])).toEqual([]);
    expect(wayIn(tree, qgd, ['e4', 'e5'])).toEqual([]);
  });

  it('keeps the way in with the line it survived', () => {
    const { run, source } = start([whiteRep()], 'w', 1, any, { toward: qgd, enter: true });
    const ended = finish(source, run);
    expect(isComplete(source, ended)).toBe(true);
    expect(lineToKeep(index, ended).slice(0, 4)).toEqual(['d4', 'd5', 'c4', 'e6']);
    expect(ended.survived).toBe(lineToKeep(index, ended).filter((_, i) => i % 2 === 0).length - 2);
  });

  it('builds an empty opening from its own position, and charges only the opening', () => {
    const kid = addLine(createRepertoire('Black', 'b', 'rep_b'), 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5'.split(' '), 'seed').rep;
    const najdorf = nodeById(tree, 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6');
    const { run } = start([kid], 'b', 1, najdorf, { steer: 'gaps', newMoves: 8, enter: true });
    expect(run.played).toEqual(najdorf.sans);
    expect(run.opened).toBe(najdorf.sans.length);
    expect(run.target).toEqual(najdorf.sans);
    // The way in was played for you, so none of it is budgeted.
    expect(run.newMoves).toBe(Math.min(8, movesToFit(najdorf.sans.length)));
  });
});

describe('following the player', () => {
  const SLAV = ['d4', 'd5', 'c4', 'c6', 'Nf3', 'Nf6', 'Nc3', 'dxc4', 'a4'];

  it('draws a new line through the position you took the run to', () => {
    const { run, redraw } = start([whiteRep()], 'w', 1, any, { seed: 2 });
    const off = at(run, ['d4', 'd5', 'c4', 'c6']);
    const steered = redraw(off);
    expect(steered.target).toEqual(SLAV);
    expect(steered.drawn).toEqual(SLAV);
    expect(steered.played).toEqual(off.played);
  });

  it('finds a line by the position, whatever the road to it', () => {
    const { run, redraw } = start([whiteRep()], 'w', 1);
    // The Slav position reached the other way round.
    const steered = redraw(at(run, ['d4', 'c6', 'c4', 'd5']));
    expect(steered.target).toEqual(['d4', 'c6', 'c4', 'd5', ...SLAV.slice(4)]);
  });

  it('leaves the run alone where nothing of yours passes through', () => {
    const { run, redraw } = start([whiteRep()], 'w', 1);
    const off = at(run, ['e4']);
    expect(redraw(off)).toBe(off);
    const past = at(run, [...SLAV, 'e6']);
    expect(redraw(past)).toBe(past);
  });

  it('walks to the nearest hole from here when steered at gaps', () => {
    const rep = addLine(createRepertoire('White', 'w', 'rep_sp'), ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5'], 'seed').rep;
    const { run, redraw } = start([rep], 'w', 1, any, { steer: 'gaps' });
    const off = at(run, ['e4', 'e5', 'Nf3']);
    const steered = redraw(off);
    expect(steered.target.slice(0, 3)).toEqual(['e4', 'e5', 'Nf3']);
    expect(steered.target).toHaveLength(4);
    expect(steered.target[3]).not.toBe('Nc6');
    expect(hasLine(rep, steered.target)).toBe(false);
  });

  it('draws by weakness from here when steered at weak spots', () => {
    const rep = whiteRep();
    const tips = leafLines(rep);
    const exchange = tips.find((line) => line.sans[3] === 'e6')!;
    const weakness: Weakness = (_, key) => (pathTo(rep, exchange.tipId).some((n) => n.key === key) ? 50 : 1);
    let steered = 0;
    for (let seed = 0; seed < 20; seed += 1) {
      const { run, redraw } = start([rep], 'w', seed, any, { steer: 'weak', weakness });
      if (redraw(at(run, ['d4', 'd5'])).target[3] === 'e6') steered += 1;
    }
    expect(steered).toBeGreaterThanOrEqual(18);
  });
});

describe('the edge of the prep', () => {
  /** One move of prep: after 1.e4 e5 White has nothing, and the book has plenty. */
  function thin(): Repertoire {
    return addLine(createRepertoire('White', 'w', 'rep_thin'), ['e4', 'e5'], 'seed').rep;
  }

  it('is your move, with nothing prepared and the book still going', () => {
    const { source, run } = start([thin()], 'w', 1, any, { newMoves: 3 });
    expect(atEdge(source, run)).toBe(false);
    const played = play(source, run, 'e4').run;
    // The opponent's turn is never the edge.
    expect(atEdge(source, played)).toBe(false);
    const edge = at(played, ['e4', 'e5']);
    expect(atEdge(source, edge)).toBe(true);
    expect(isComplete(source, edge)).toBe(false);
    expect(atEdge(source, leavePrep(at(played, ['e4', 'e5']), 'Nc3'))).toBe(false);
    expect(atEdge(source, keepPlaying(edge))).toBe(false);
    expect(atEdge(source, { ...edge, over: true })).toBe(false);
    expect(atEdge(source, { ...edge, bookRun: true })).toBe(false);
  });

  it('offers the book there, most played first', () => {
    const { run } = start([thin()], 'w', 1, any);
    const edge = at(run, ['e4', 'e5']);
    const options = edgeOptions(index, edge.fen);
    expect(options.length).toBeGreaterThan(1);
    expect(options[0].san).toBe('Nf3');
    expect(options[0].games).toBeGreaterThanOrEqual(options[1].games);
  });

  it('spends a new move on the choice and scores nothing for it', () => {
    const { run } = start([thin()], 'w', 1, any, { newMoves: 2 });
    const edge = at({ ...run, survived: 1 }, ['e4', 'e5']);
    const chosen = chooseAtEdge(edge, 'Nf3');
    expect(chosen.over).toBe(false);
    expect(chosen.played).toEqual(['e4', 'e5', 'Nf3']);
    expect(chosen.survived).toBe(1);
    expect(chosen.newMoves).toBe(1);
    expect(chosen.added).toBe(1);
    expect(chosen.target).toEqual([]);
    expect(playedIsLegal(chosen)).toBe(true);
    expect(chooseAtEdge({ ...edge, newMoves: 0 }, 'Nf3').over).toBe(true);
    expect(chooseAtEdge(edge, 'Ke2').over).toBe(false);
    expect(chooseAtEdge(edge, 'Qh7').over).toBe(true);
  });

  it('is a checkpoint where the prep ends, and nothing carries on by itself', () => {
    // A Ruy López stub: onboarding's five plies and nothing more.
    const stub = addLine(createRepertoire('White', 'w', 'rep_ruy'), ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5'], 'seed').rep;
    const { source, run } = start([stub], 'w', 1, any);
    const edge = at({ ...run, survived: 3 }, ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6']);
    expect(atEdge(source, edge)).toBe(true);
    // Reaching it completes the run; stopping there is a clean finish.
    const done = finishPrep(edge);
    expect(done.prepDone).toBe(6);
    expect(finishPrep(done)).toBe(done);
    expect(outcomeOf(done, null)).toMatchObject({ completed: true, grade: 'green', depth: 3 });
    expect(lineToKeep(index, done)).toEqual(['e4', 'e5', 'Nf3', 'Nc6', 'Bb5']);
    // Keeping on: the engine judges, the run is still a clean one, and nothing more is scored.
    const on = keepPlaying(edge);
    expect(on).toMatchObject({ extended: true, prepDone: 6, handOver: 6, leftPrep: false, target: [] });
    expect(atEdge(source, on)).toBe(false);
    expect(isComplete(source, on)).toBe(false);
    expect(keepPlaying(on)).toBe(on);
    const moved = playPast(on, 'Ba4');
    expect(moved.survived).toBe(3);
    expect(moved.past).toBe(1);
    expect(gradeOf(moved, null)).toBe('green');
    expect(gradeOf(moved, 'blunder')).toBe('red');
    // A book move past the hand-over is still worth keeping; the reveal offers it.
    expect(lineToKeep(index, moved)).toEqual(['e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6', 'Ba4']);
  });

  it('walks the book when nothing of yours passes through the region', () => {
    const najdorf = byName('Sicilian Defence: Najdorf Variation');
    const { source, run } = start([whiteRep()], 'w', 1, najdorf);
    expect(run.bookRun).toBe(true);
    expect(start([whiteRep()], 'w').run.bookRun).toBe(false);
    expect(start([], 'w').run.bookRun).toBe(true);
    // The book is the referee: its moves are simply the moves, and there is no edge to be at.
    const inBook = at(run, run.played);
    expect(isUsersTurn(inBook)).toBe(true);
    expect(movesHere(source, inBook).length).toBeGreaterThan(0);
    expect(classify(source, inBook, movesHere(source, inBook)[0])).toBe('prep');
    expect(atEdge(source, inBook)).toBe(false);
  });

  it('starts with the budget it was given, and none by default', () => {
    expect(start([thin()], 'w').run.newMoves).toBe(0);
    expect(start([thin()], 'w', 1, any, { newMoves: 3 }).run.newMoves).toBe(3);
    expect(start([thin()], 'w', 1, any, { newMoves: -2 }).run.newMoves).toBe(0);
    expect(start([thin()], 'w').run.added).toBe(0);
  });
});

describe('drawing move orders you will actually face', () => {
  const reps = buildSeedRepertoires();
  const kid = reps.filter((r) => r.name.includes('King'));

  /** Total odds of every line whose first plies are these moves. */
  function share(rep: Repertoire, side: 'w' | 'b', withIndex: boolean, prefix: string[]): number {
    const odds = lineOdds(rep, side, withIndex ? index : null);
    let hit = 0;
    let all = 0;
    for (const leaf of leafLines(rep)) {
      const weight = odds.get(leaf.tipId) ?? 1;
      all += weight;
      if (prefix.every((san, i) => leaf.sans[i] === san)) hit += weight;
    }
    return all ? hit / all : 0;
  }

  it('follows the database when the opponent chooses', () => {
    const rep = kid[0];
    expect(share(rep, 'b', true, ['d4'])).toBeGreaterThan(0.5);
    expect(share(rep, 'b', true, ['b4'])).toBeLessThan(0.05);
  });

  it('finds move orders that leaf counts had buried', () => {
    const rep = kid[0];
    expect(share(rep, 'b', true, ['Nf3'])).toBeGreaterThan(share(rep, 'b', false, ['Nf3']) * 2);
  });

  it('cuts how often a run turns on a reply almost nobody plays', () => {
    const rep = kid[0];
    const obscure = (withIndex: boolean, limit: number) => {
      const odds = lineOdds(rep, 'b', withIndex ? index : null);
      let all = 0;
      let hit = 0;
      for (const leaf of leafLines(rep)) {
        const weight = odds.get(leaf.tipId) ?? 1;
        all += weight;
        let rarest = 1;
        for (const node of pathTo(rep, leaf.tipId)) {
          if (fenTurn(node.fenBefore) === 'b') continue;
          const entry = lookup(index, node.fenBefore);
          if (!entry || entry.moves.length < 2) continue;
          const total = entry.moves.reduce((sum, m) => sum + m.games, 0);
          if (!total) continue;
          rarest = Math.min(rarest, (entry.moves.find((m) => m.san === node.san)?.games ?? 0) / total);
        }
        if (rarest < limit) hit += weight;
      }
      return hit / all;
    };
    expect(obscure(true, 0.05)).toBeLessThan(obscure(false, 0.05) * 0.75);
    expect(obscure(true, 0.05)).toBeGreaterThan(0.05);
  });

  it('keeps a prepared sideline in the rotation rather than burying it', () => {
    const sideline = share(kid[0], 'b', true, ['d4', 'Nf6', 'Nf3', 'g6', 'Bg5']);
    expect(sideline).toBeGreaterThan(0);
    expect(sideline).toBeLessThan(0.05);
  });

  it('does not let your own alternatives inflate a line', () => {
    let rep = createRepertoire('Black', 'b', 'rep_forks');
    rep = addLine(rep, ['d4', 'Nf6', 'c4', 'g6', 'Nc3', 'Bg7', 'e4', 'd6'], 'seed').rep;
    rep = addLine(rep, ['d4', 'Nf6', 'c4', 'g6', 'Nc3', 'Bg7', 'e4', 'O-O'], 'seed').rep;
    rep = addLine(rep, ['d4', 'Nf6', 'c4', 'g6', 'Nc3', 'Bg7', 'e4', 'c5'], 'seed').rep;
    rep = addLine(rep, ['d4', 'Nf6', 'Bg5', 'Ne4', 'Bf4', 'd5'], 'seed').rep;
    const mainline = share(rep, 'b', true, ['d4', 'Nf6', 'c4']);
    const sideline = share(rep, 'b', true, ['d4', 'Nf6', 'Bg5']);
    expect(mainline + sideline).toBeCloseTo(1, 5);
    // Three lines sit under 2.c4 and one under 2.Bg5, and that must not be what
    // decides how often each is drawn — how often White plays them is. So the
    // split tracks the book's own popularity rather than the line count.
    const after = lookup(referenceIndex(), walkSan(['d4', 'Nf6']).fens.at(-1)!)!;
    const games = (san: string) => after.moves.find((move) => move.san === san)!.games;
    expect(mainline / sideline).toBeCloseTo(games('c4') / games('Bg5'), 0);
  });

  it('gives the rarest lines back their share when short ones are skipped', () => {
    const rep = kid[0];
    const usable = new Set(
      leafLines(rep).filter((l) => l.sans.filter((_, i) => i % 2 === 1).length >= 4).map((l) => l.tipId),
    );
    const odds = lineOdds(rep, 'b', index, usable);
    const total = [...odds.values()].reduce((sum, n) => sum + n, 0);
    expect(total).toBeCloseTo(1, 5);
    expect([...odds.keys()].every((id) => usable.has(id))).toBe(true);
  });

  it('draws evenly with no reference data rather than guessing', () => {
    expect(lineOdds(kid[0], 'b', null).size).toBe(0);
  });
});

describe('past the hand-over', () => {
  const rep = whiteRep();

  it('starts with the referee in charge, and has no switch', () => {
    const { run } = start([rep], 'w');
    expect(run).toMatchObject({ extended: false, handOver: null, prepDone: null, past: 0 });
    expect(DEFAULT_OPTIONS).not.toHaveProperty('extended');
  });

  it('never completes once the engine is the referee', () => {
    const { source, run, redraw } = start([rep], 'w');
    const done = finish(source, run);
    expect(isComplete(source, done)).toBe(true);
    const on = keepPlaying(done);
    expect(isComplete(source, on)).toBe(false);
    expect(on.prepDone).toBe(done.played.length);
    expect(on.handOver).toBe(done.played.length);
    // Nothing steers the opponent from here either.
    expect(redraw(on)).toBe(on);
  });

  it('remembers where the prep ended, once', () => {
    const run = finishPrep({ ...start([rep], 'w').run, played: ['d4', 'd5'] });
    expect(run.prepDone).toBe(2);
    expect(finishPrep({ ...run, played: ['d4', 'd5', 'c4', 'e6'] }).prepDone).toBe(2);
  });

  it('measures a loss from your own side of the board', () => {
    expect(evalLoss('w', 100, 0)).toBe(100);
    expect(evalLoss('b', 100, 0)).toBe(-100);
    expect(evalLoss('b', -100, 0)).toBe(100);
    expect(evalLoss('w', -100, 0)).toBe(-100);
  });

  it('allows an inaccuracy and stops a blunder', () => {
    expect(BLUNDER_LIMIT).toBeGreaterThanOrEqual(50);
    expect(judgeByEval('w', 20, 20 - BLUNDER_LIMIT).ok).toBe(true);
    expect(judgeByEval('w', 20, 20 - BLUNDER_LIMIT - 1).ok).toBe(false);
    expect(judgeByEval('w', 20, -61).lost).toBe(81);
    expect(judgeByEval('b', -20, 300).ok).toBe(false);
    expect(judgeByEval('w', 10, 400)).toEqual({ ok: true, lost: 0 });
  });

  it('takes a move the engine passed, scoring nothing for it', () => {
    const begun = keepPlaying(start([rep], 'w').run);
    const next = playPast(begun, 'd4');
    expect(next.played).toEqual(['d4']);
    expect(next.survived).toBe(begun.survived);
    expect(next.past).toBe(1);
    expect(playedIsLegal(next)).toBe(true);
    expect(playPast(begun, 'e5').over).toBe(true);
  });

  it("takes the opponent's move on its own", () => {
    const { source, run } = start([rep], 'w');
    const begun = keepPlaying(play(source, run, 'd4').run);
    expect(isUsersTurn(begun)).toBe(false);
    const next = playReply(begun, 'd5');
    expect(next.played).toEqual(['d4', 'd5']);
    expect(next.survived).toBe(begun.survived);
    expect(next.past).toBe(0);
    expect(playReply(begun, 'd4').over).toBe(true);
  });
});

describe('stepping outside your prep', () => {
  const rep = whiteRep();

  it('carries the run on, hands over to the engine and stops steering', () => {
    const run = at(start([rep], 'w').run, ['d4', 'd5']);
    const carried = leavePrep(run, 'Nf3');
    expect(carried).toMatchObject({ leftPrep: true, extended: true, handOver: 2, over: false, past: 1, target: [] });
    // A move off your prep earns nothing, however sound.
    expect(carried.survived).toBe(run.survived);
    expect(carried.played).toEqual(['d4', 'd5', 'Nf3']);
    expect(playedIsLegal(carried)).toBe(true);
    expect(applySan(run.fen, 'e5')).toBeNull();
    expect(leavePrep(run, 'e5').over).toBe(true);
  });

  it('grades the endings apart', () => {
    const clean = at(start([rep], 'w').run, ['d4', 'd5']);
    const strayed = { ...clean, leftPrep: true };
    expect(gradeOf(clean, null)).toBe('green');
    expect(gradeOf(strayed, null)).toBe('yellow');
    expect(gradeOf(clean, 'blunder')).toBe('red');
    expect(gradeOf(strayed, 'blunder')).toBe('red');
    expect(gradeOf(strayed, 'offprep')).toBe('purple');
    for (const grade of GRADES) expect(gradeLabel(grade)).toBeTruthy();
    expect(outcomeOf(leavePrep(clean, 'Nf3'), null).grade).toBe('yellow');
  });

  it('starts every run inside its prep', () => {
    expect(start([rep], 'w').run.leftPrep).toBe(false);
    expect(start([], 'w').run.leftPrep).toBe(false);
  });
});

describe('keeping a line at the reveal', () => {
  function runOf(over: Partial<Run>): Run {
    return {
      id: 'r', sourceLabel: 'Any opening', openingId: '', leftPrep: false, bookRun: false, extended: false,
      handOver: null, past: 0, color: 'w', fen: START_FEN, played: [], survived: 0, over: true, target: [],
      drawn: [], hints: 0, hintsUsed: 0, newMoves: 0, added: 0, prepDone: null, opened: 0, enteredIn: null,
      ...over,
    };
  }

  it('ends a line on your own move', () => {
    expect(lineToKeep(index, runOf({ color: 'w', played: ['e4', 'c5', 'Nf3', 'd6'] }))).toEqual(['e4', 'c5', 'Nf3']);
    expect(lineToKeep(index, runOf({ color: 'b', played: ['e4', 'c5', 'Nf3'] }))).toEqual(['e4', 'c5']);
  });

  it('keeps theory past the hand-over and stops at the first move the book has never seen', () => {
    const theory = runOf({ color: 'w', played: ['e4', 'c5', 'Nf3', 'd6', 'd4', 'cxd4'], extended: true, handOver: 3 });
    expect(lineToKeep(index, theory)).toEqual(['e4', 'c5', 'Nf3', 'd6', 'd4']);
    const novelty = runOf({ color: 'w', played: ['e4', 'c5', 'Nf3', 'd6', 'Ke2', 'Nf6'], extended: true, handOver: 3 });
    expect(bookHas(index, walkSan(['e4', 'c5', 'Nf3', 'd6']).fens[4], 'Ke2')).toBe(false);
    expect(lineToKeep(index, novelty)).toEqual(['e4', 'c5', 'Nf3']);
  });

  it('offers a sound move off your prep when it is theory', () => {
    const run = at(start([whiteRep()], 'w').run, ['d4', 'd5']);
    expect(lineToKeep(index, leavePrep(run, 'Nf3'))).toEqual(['d4', 'd5', 'Nf3']);
  });

  it('keeps nothing from a run that died on its first move', () => {
    expect(lineToKeep(index, runOf({ color: 'w', played: [] }))).toEqual([]);
    expect(lineToKeep(index, runOf({ color: 'b', played: ['e4'] }))).toEqual([]);
  });
});

describe('the region of a run', () => {
  it('names the root as any opening', () => {
    expect(nodeById(tree, '').name).toBe('Any opening');
    expect(start([], 'w').run.openingId).toBe('');
  });
});
