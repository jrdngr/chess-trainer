import { describe, expect, it } from 'vitest';
import { applySan, fenTurn, positionKey, START_FEN, walkSan } from '../chess/core';
import {
  beginRun,
  BLUNDER_LIMIT,
  DRAW_WINDOW,
  clockLabel,
  clockSeconds,
  CLOCK_MODES,
  DEFAULT_OPTIONS,
  evalLoss,
  movesToFit,
  judgeByEval,
  lineOdds,
  lineWeakness,
  opponentReply,
  regionSource,
  resolveColor,
  wayIn,
  weaknessFromCards,
  type LineSource,
  type Run,
  type Weakness,
} from './openingRun';
import { findHoles } from './growth';
import { markSeen } from './freshness';
import { lineStatus, nodeById, openingTree } from './openingTree';
import { addLine, createRepertoire, leafLines, pathTo } from './repertoire';
import { lookup } from './reference';
import { referenceIndex } from './referenceIndex';
import { cardId, mulberry32 } from './session';
import { buildSeedRepertoires } from '../test/fixtures/seed';
import { MAX_LIFTED, PREPARED_FLOOR, withFloor } from './prepFloor';
import type { Card, Repertoire } from './types';
import { hasLine } from '../test/helpers';

const index = referenceIndex();
const tree = openingTree(index);
const any = tree.root;
const byName = (name: string) => {
  const found = [...tree.byId.values()].find((node) => node.name === name);
  if (!found) throw new Error(`no node named ${name}`);
  return found;
};

// The old Run mode's drivers, kept here as test scaffolding: the source,
// the opponent and the way in are live, and these walk a run through them.
const isUsersTurn = (run: Run) => fenTurn(run.fen) === run.color;
const movesHere = (source: LineSource, run: Run) => source.movesAt(run.fen, run.played);
const staysInside = (run: Run, san: string) =>
  lineStatus(tree, nodeById(tree, run.openingId), [...run.played, san]) !== 'outside';
function play(source: LineSource, run: Run, san: string): { ok: boolean; run: Run } {
  const move = movesHere(source, run).includes(san) ? applySan(run.fen, san) : null;
  if (!move) return { ok: false, run: { ...run, over: true } };
  const target = run.target[run.played.length] === san ? run.target : [];
  return { ok: true, run: { ...run, fen: move.after, played: [...run.played, san], survived: run.survived + 1, target } };
}

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

  it('keeps the run inside the region on the way in', () => {
    const najdorf = byName('Sicilian Defence: Najdorf Variation');
    const { source, run } = start([rep], 'w', 1, najdorf);
    // Every first move offered has to be able to become a Najdorf. Several can:
    // 1.d4 c5 2.e4 and 1.Nf3 c5 2.e4 both transpose. Most cannot.
    const offered = movesHere(source, run);
    expect(offered).toContain('e4');
    for (const san of offered) expect(staysInside(run, san)).toBe(true);
    // Most cannot, and are not offered: the region is a filter, not a list of
    // everything the book holds at move one.
    const firsts = lookup(referenceIndex(), START_FEN)!.moves.length;
    expect(offered.length).toBeLessThan(firsts / 2);
    // 1.d4 stays alive, because 1.d4 c5 2.e4 is a Sicilian.
    expect(staysInside(run, 'd4')).toBe(true);
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

  it('on the way in, counts only prep that can still reach the opening', () => {
    let rep = whiteRep();
    rep = addLine(rep, ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5'], 'seed').rep;
    const source = regionSource(tree, byName('Ruy Lopez'), rep, 'w');
    // 1.d4 is prep for the Queen's Gambit, not for the Ruy Lopez.
    expect(source.prepAt(START_FEN)).toEqual(['e4']);
    // Anywhere else, prep is prep.
    expect(regionSource(tree, any, rep, 'w').prepAt(START_FEN).sort()).toEqual(['d4', 'e4']);
  });

  it('accepts every prepared answer, not just the one line drawn', () => {
    const kid = buildSeedRepertoires().find((r) => r.name.includes('King'))!;
    const source = regionSource(tree, any, kid, 'b');
    const run = at(start([kid], 'b').run, ['d4', 'Nf6', 'c4', 'g6', 'Nc3', 'Bg7']);
    const options = movesHere(source, run);
    expect(options.length).toBeGreaterThan(1);
    for (const san of options) expect(play(source, run, san).ok).toBe(true);
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

  it('defaults to none', () => {
    expect(DEFAULT_OPTIONS.hints).toBe(0);
    expect(start([rep], 'w').run.hints).toBe(0);
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

describe('starting at a position', () => {
  it('plays the moves to it for you and draws the line on through it', () => {
    const at = ['d4', 'd5', 'c4', 'c6', 'Nf3', 'Nf6'];
    const { run } = start([whiteRep()], 'w', 1, any, { at, enter: true });
    expect(run.played).toEqual(at);
    expect(run.opened).toBe(at.length);
    expect(run.fen).toBe(walkSan(at).fens[at.length]);
    expect(run.target.slice(0, at.length + 1)).toEqual([...at, 'Nc3']);
    expect(isUsersTurn(run)).toBe(true);
    // Named for the deepest opening the way there reaches.
    expect(run.enteredIn).not.toBeNull();
    expect(lineStatus(tree, nodeById(tree, run.enteredIn!), at)).toBe('reached');
  });

  it('starts from move one when the moves do not reach a position', () => {
    const { run } = start([whiteRep()], 'w', 1, any, { at: ['d4', 'e4'] });
    expect(run.opened).toBe(0);
    expect(run.played).toEqual([]);
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
    const d4 = share(rep, 'b', true, ['d4']);
    for (const first of ['c4', 'Nf3', 'g3', 'b3', 'f4', 'b4']) {
      expect(d4).toBeGreaterThan(share(rep, 'b', true, [first]) * 2);
    }
  });

  it('keeps the book ahead above the floor', () => {
    // 1.Nf3 is played more than its floor, 1.b4 far less: both are prepared,
    // and the one strong players choose more still comes up more.
    const rep = kid[0];
    expect(share(rep, 'b', true, ['Nf3'])).toBeGreaterThan(share(rep, 'b', true, ['b4']));
  });

  it('tests a prepared reply strong players rarely choose', () => {
    // 1.b4 is barely in the book. Prepared, it is one you mean to be tested
    // on: it gets its floor, shrunk only because five such first moves share
    // MAX_LIFTED between them.
    const rep = kid[0];
    const b4 = share(rep, 'b', true, ['b4']);
    expect(b4).toBeGreaterThanOrEqual(MAX_LIFTED / 5 - 1e-9);
    expect(b4).toBeLessThanOrEqual(PREPARED_FLOOR);
  });

  it('lifts a lone rare reply to the full floor', () => {
    let rep = createRepertoire('Black', 'b', 'rep_floor');
    rep = addLine(rep, ['d4', 'Nf6', 'c4', 'g6', 'Nc3', 'Bg7', 'e4', 'd6', 'Nf3', 'O-O'], 'seed').rep;
    rep = addLine(rep, ['d4', 'Nf6', 'c4', 'g6', 'Nc3', 'Bg7', 'e4', 'd6', 'e5', 'dxe5'], 'manual').rep;
    const e5 = share(rep, 'b', true, ['d4', 'Nf6', 'c4', 'g6', 'Nc3', 'Bg7', 'e4', 'd6', 'e5']);
    expect(e5).toBeCloseTo(PREPARED_FLOOR, 5);
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
    // split tracks the book's own popularity, with 2.Bg5 at its floor, rather
    // than the line count.
    const after = lookup(referenceIndex(), walkSan(['d4', 'Nf6']).fens.at(-1)!)!;
    const games = (san: string) => after.moves.find((move) => move.san === san)!.games;
    const [c4, bg5] = withFloor([games('c4'), games('Bg5')], [true, true]);
    expect(mainline / sideline).toBeCloseTo(c4 / bg5, 5);
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
});

describe('stepping outside your prep', () => {
  const rep = whiteRep();

  it('starts every run inside its prep', () => {
    expect(start([rep], 'w').run.leftPrep).toBe(false);
    expect(start([], 'w').run.leftPrep).toBe(false);
  });
});

describe('the region of a run', () => {
  it('names the root as any opening', () => {
    expect(nodeById(tree, '').name).toBe('Any opening');
    expect(start([], 'w').run.openingId).toBe('');
  });
});
