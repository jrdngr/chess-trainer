import { describe, expect, it } from 'vitest';
import { fenTurn, positionKey, walkSan } from '../chess/core';
import {
  beginRun,
  bookSource,
  clockDescription,
  clockLabel,
  clockSpec,
  CLOCK_MODES,
  DEFAULT_OPTIONS,
  lineWeakness,
  takeHint,
  timeOut,
  weaknessFromCards,
  continuation,
  EMPTY_RECORD,
  fullLine,
  isComplete,
  isUsersTurn,
  lineName,
  movesHere,
  opponentReply,
  play,
  playableRepertoires,
  playedIsLegal,
  lineRecords,
  normalizeRecord,
  outcomeOf,
  recordRun,
  repertoireSource,
  resolveColor,
  revealText,
  startBookRun,
  startRepertoireRun,
  type LineSource,
  type Weakness,
  type Run,
} from './permadeath';
import { addLine, createRepertoire, displayName } from './repertoire';
import { referenceIndex } from './referenceIndex';
import { cardId, mulberry32 } from './session';
import { buildSeedRepertoires } from '../store/seed';
import type { Card, Repertoire } from './types';

const rand = () => 0.5;
const index = referenceIndex();

function whiteRep(): Repertoire {
  let rep = createRepertoire("White — Queen's Gambit", 'w', 'rep_w');
  rep = addLine(rep, ['d4', 'd5', 'c4', 'e6', 'Nc3', 'Nf6', 'cxd5', 'exd5', 'Bg5'], 'seed').rep;
  rep = addLine(rep, ['d4', 'd5', 'c4', 'c6', 'Nf3', 'Nf6', 'Nc3', 'dxc4', 'a4'], 'seed').rep;
  return rep;
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

describe('choosing a run', () => {
  const reps = buildSeedRepertoires();

  it('picks a line long enough to be a game', () => {
    const run = startRepertoireRun([whiteRep()], 'w', { seed: 1 })!;
    expect(run.survived).toBe(0);
    expect(run.over).toBe(false);
    expect(run.played).toEqual([]);
    expect(run.target.length).toBeGreaterThanOrEqual(7);
  });

  it('refuses when no line is long enough', () => {
    const shallow = addLine(createRepertoire('x', 'w', 'r'), ['d4'], 'seed').rep;
    expect(startRepertoireRun([shallow], 'w', { seed: 1, minDecisions: 4 })).toBeNull();
  });

  it('honours the chosen colour', () => {
    for (let seed = 0; seed < 12; seed += 1) {
      expect(startRepertoireRun(reps, 'w', { seed })!.color).toBe('w');
      expect(startRepertoireRun(reps, 'b', { seed })!.color).toBe('b');
    }
  });

  it('returns nothing when no repertoire plays the chosen colour', () => {
    expect(startRepertoireRun([whiteRep()], 'b', { seed: 1 })).toBeNull();
    expect(playableRepertoires([whiteRep()], 'b')).toEqual([]);
  });

  it('random picks both colours across seeds', () => {
    const colours = new Set<string>();
    for (let seed = 0; seed < 30; seed += 1) colours.add(startRepertoireRun(reps, 'random', { seed })!.color);
    expect([...colours].sort()).toEqual(['b', 'w']);
    expect(resolveColor('random', () => 0.1)).toBe('w');
    expect(resolveColor('random', () => 0.9)).toBe('b');
    expect(resolveColor('b', () => 0.1)).toBe('b');
  });

  it('spreads runs across repertoires rather than favouring the biggest', () => {
    const counts = new Map<string, number>();
    for (let seed = 0; seed < 90; seed += 1) {
      const run = startRepertoireRun(reps, 'random', { seed })!;
      counts.set(run.sourceLabel, (counts.get(run.sourceLabel) ?? 0) + 1);
    }
    expect(counts.size).toBe(reps.length);
    for (const n of counts.values()) expect(n).toBeGreaterThan(10);
  });

  it('starts a book run for either colour', () => {
    expect(startBookRun(index, 'w', { seed: 1 })!.color).toBe('w');
    expect(startBookRun(index, 'b', { seed: 1 })!.color).toBe('b');
    const random = new Set<string>();
    for (let seed = 0; seed < 20; seed += 1) random.add(startBookRun(index, 'random', { seed })!.color);
    expect([...random].sort()).toEqual(['b', 'w']);
  });

  it('puts the user on move when they are White and waiting when Black', () => {
    expect(isUsersTurn(startRepertoireRun(reps, 'w', { seed: 1 })!)).toBe(true);
    const black = startRepertoireRun(reps, 'b', { seed: 1 })!;
    expect(isUsersTurn(black)).toBe(false);
    expect(fenTurn(black.fen)).toBe('w');
  });
});

describe('playing a repertoire run', () => {
  const rep = whiteRep();
  const source = repertoireSource(rep);

  it('accepts a prepared move and counts it', () => {
    const res = play(source, startRepertoireRun([rep], 'w', { seed: 1 })!, 'd4');
    expect(res.ok).toBe(true);
    if (res.ok) {
      expect(res.run.survived).toBe(1);
      expect(res.run.played).toEqual(['d4']);
      expect(res.run.over).toBe(false);
    }
  });

  it('ends the run on anything outside the repertoire', () => {
    const res = play(source, startRepertoireRun([rep], 'w', { seed: 1 })!, 'e4');
    expect(res.ok).toBe(false);
    if (!res.ok) {
      expect(res.run.over).toBe(true);
      expect(res.expected).toEqual(['d4']);
      expect(res.run.played).not.toContain('e4');
    }
  });

  it('accepts a prepared alternative, and the opponent follows that branch', () => {
    let alt = createRepertoire('alt', 'w', 'rep_alt');
    alt = addLine(alt, ['d4', 'd5', 'c4', 'e6', 'Nc3', 'Nf6', 'Bg5'], 'seed').rep;
    alt = addLine(alt, ['d4', 'd5', 'c4', 'e6', 'Nf3', 'Nf6', 'Bf4'], 'seed').rep;
    const altSource = repertoireSource(alt);

    let run = startRepertoireRun([alt], 'w', { seed: 1, minDecisions: 3 })!;
    run = play(altSource, run, 'd4').run;
    run = opponentReply(altSource, run, rand);
    run = play(altSource, run, 'c4').run;
    run = opponentReply(altSource, run, rand);

    const options = movesHere(altSource, run);
    expect([...options].sort()).toEqual(['Nc3', 'Nf3']);
    const other = options.find((san) => san !== run.target[run.played.length])!;
    const res = play(altSource, run, other);
    expect(res.ok).toBe(true);
    if (res.ok) {
      expect(res.run.survived).toBe(3);
      const after = opponentReply(altSource, res.run, rand);
      expect(after.played.at(-1)).toBe('Nf6');
      expect(movesHere(altSource, after)).toEqual([other === 'Nc3' ? 'Bg5' : 'Bf4']);
    }
  });

  it('plays a run to the end of the line', () => {
    const run = finish(source, startRepertoireRun([rep], 'w', { seed: 1 })!);
    expect(isComplete(source, run)).toBe(true);
    expect(run.survived).toBeGreaterThanOrEqual(4);
    expect(playedIsLegal(run)).toBe(true);
    expect(walkSan(run.played).moves).toHaveLength(run.played.length);
  });

  it('keeps the losing move out of the line it reveals', () => {
    let run = startRepertoireRun([rep], 'w', { seed: 1 })!;
    run = play(source, run, 'd4').run;
    run = opponentReply(source, run, rand);
    const dead = play(source, run, 'a3');
    expect(dead.ok).toBe(false);
    if (!dead.ok) {
      expect(revealText(source, dead.run)).not.toContain('a3');
      expect(revealText(source, dead.run).startsWith('1. d4 d5')).toBe(true);
      expect(continuation(source, dead.run).length).toBeGreaterThan(0);
    }
  });
});

describe('playing a book run', () => {
  const source = bookSource(index, 'w');

  it('accepts any move somebody plays here and rejects the rest', () => {
    const run = startBookRun(index, 'w', { seed: 1 })!;
    expect(movesHere(source, run)).toContain('e4');
    expect(movesHere(source, run)).toContain('d4');
    expect(play(source, run, 'e4').ok).toBe(true);
    expect(play(source, run, 'Na3').ok).toBe(false);
  });

  it('is more forgiving than a repertoire at the same position', () => {
    const reps = buildSeedRepertoires();
    const repSource = repertoireSource(reps[0]);
    const start = startBookRun(index, 'w', { seed: 1 })!;
    expect(movesHere(source, start).length).toBeGreaterThan(movesHere(repSource, start).length);
  });

  it('plays out to the edge of the book without illegal moves', () => {
    for (let seed = 0; seed < 12; seed += 1) {
      const colour = seed % 2 === 0 ? 'w' : 'b';
      const src = bookSource(index, colour);
      const run = finish(src, startBookRun(index, colour, { seed })!, seed + 1);
      expect(run.over).toBe(false);
      expect(isComplete(src, run)).toBe(true);
      expect(playedIsLegal(run)).toBe(true);
      expect(run.survived).toBeGreaterThan(2);
    }
  });

  it('lets the opponent favour popular replies', () => {
    const run = play(source, startBookRun(index, 'w', { seed: 1 })!, 'e4').run;
    const replies = new Map<string, number>();
    for (let seed = 0; seed < 60; seed += 1) {
      const next = opponentReply(source, run, mulberry32(seed));
      replies.set(next.played[1], (replies.get(next.played[1]) ?? 0) + 1);
    }
    // The Sicilian is the most played answer to 1.e4 in the database.
    const top = [...replies.entries()].sort((a, b) => b[1] - a[1])[0];
    expect(top[0]).toBe('c5');
  });
});

describe('naming the line at the end of a run', () => {
  const reps = buildSeedRepertoires();

  it('never labels a line with a name so generic it says nothing', () => {
    const generic = /^(King's|Queen's) Pawn Opening$|^Réti Opening$|^English Opening$/;
    const bad: string[] = [];
    for (let seed = 0; seed < 40; seed += 1) {
      const run0 = startRepertoireRun(reps, 'random', { seed })!;
      const source = repertoireSource(reps.find((r) => displayName(r.name) === run0.sourceLabel)!);
      const run = finish(source, run0, seed + 1);
      const label = lineName(index, source, run);
      if (generic.test(label.name)) bad.push(`${label.name} <- ${fullLine(source, run).slice(0, 8).join(' ')}`);
    }
    expect(bad).toEqual([]);
  });

  it('names the variation, not just the opening', () => {
    let named = 0;
    const distinct = new Set<string>();
    for (let seed = 0; seed < 40; seed += 1) {
      const run0 = startRepertoireRun(reps, 'random', { seed })!;
      const source = repertoireSource(reps.find((r) => displayName(r.name) === run0.sourceLabel)!);
      const label = lineName(index, source, finish(source, run0, seed + 1));
      distinct.add(label.name);
      if (label.specific) named += 1;
    }
    expect(named / 40).toBeGreaterThan(0.95);
    expect(distinct.size).toBeGreaterThan(6);
  });

  it('names a book run too', () => {
    const source = bookSource(index, 'w');
    const run = finish(source, startBookRun(index, 'w', { seed: 4 })!, 5);
    expect(lineName(index, source, run).specific).toBe(true);
  });

  it('falls back to the source when the database only knows the opening vaguely', () => {
    const source = repertoireSource(reps[0]);
    const run = finish(source, startRepertoireRun([reps[0]], 'w', { seed: 0 })!);
    const label = lineName(index, source, run, 99);
    expect(label.specific).toBe(false);
    expect(label.name).toBe(run.sourceLabel);
  });
});

describe('the record', () => {
  const outcome = (depth: number, completed: boolean, key = 'rep:a:w') => ({
    key,
    label: 'Queen\u2019s Gambit',
    color: 'w' as const,
    depth,
    completed,
  });

  it('tracks runs, best depth and survivals', () => {
    let record = EMPTY_RECORD;
    record = recordRun(record, outcome(6, false), 1000);
    expect(record.runs).toBe(1);
    expect(record.best).toBe(6);
    expect(record.lastAt).toBe(1000);
    record = recordRun(record, outcome(3, false), 2000);
    expect(record.best).toBe(6);
    expect(record.lastDepth).toBe(3);
    record = recordRun(record, outcome(9, true), 3000);
    expect(record.runs).toBe(3);
    expect(record.best).toBe(9);
    expect(record.survivals).toBe(1);
  });

  it('keeps a separate best for each opening and side', () => {
    let record = EMPTY_RECORD;
    record = recordRun(record, outcome(12, false, 'rep:a:w'), 1000);
    record = recordRun(record, outcome(4, true, 'book:b'), 2000);
    record = recordRun(record, outcome(7, false, 'book:b'), 3000);

    expect(record.best).toBe(12);
    expect(record.byLine['rep:a:w'].best).toBe(12);
    expect(record.byLine['rep:a:w'].runs).toBe(1);
    expect(record.byLine['book:b']).toMatchObject({ best: 7, runs: 2, survivals: 1 });
  });

  it('sorts the breakdown by best run', () => {
    let record = EMPTY_RECORD;
    record = recordRun(record, outcome(3, false, 'rep:a:w'), 1000);
    record = recordRun(record, outcome(11, false, 'rep:b:b'), 2000);
    expect(lineRecords(record).map((l) => l.key)).toEqual(['rep:b:b', 'rep:a:w']);
  });

  it('reads a record saved before per-opening bests existed', () => {
    const old = { runs: 4, best: 9, lastDepth: 2, lastAt: 10, survivals: 1 };
    const fixed = normalizeRecord(old);
    expect(fixed.best).toBe(9);
    expect(fixed.byLine).toEqual({});
    expect(recordRun(fixed, outcome(5, false), 20).byLine['rep:a:w'].best).toBe(5);
  });

  it('files a run under its opening and the side actually played', () => {
    const reps = buildSeedRepertoires();
    const run = startRepertoireRun(reps, 'b', { seed: 5, reverse: true })!;
    const filed = outcomeOf(run, false);
    expect(filed.key).toBe(`rep:${run.repertoireId}:b`);
    expect(filed.label).toMatch(/reversed/);
    expect(outcomeOf({ ...run, reverse: false }, false).label).not.toMatch(/reversed/);
  });
});

describe('restricting a run to one opening', () => {
  const reps = buildSeedRepertoires();

  it('draws only from the chosen repertoire', () => {
    const wanted = reps.find((r) => r.color === 'b')!;
    for (let seed = 0; seed < 12; seed += 1) {
      const run = startRepertoireRun(reps, 'b', { seed, repertoireId: wanted.id });
      expect(run?.repertoireId).toBe(wanted.id);
    }
  });

  it('draws from every repertoire of that colour when none is chosen', () => {
    const black = reps.filter((r) => r.color === 'b');
    expect(black.length).toBeGreaterThan(1);
    const seen = new Set<string>();
    for (let seed = 0; seed < 40; seed += 1) {
      const run = startRepertoireRun(reps, 'b', { seed });
      if (run?.repertoireId) seen.add(run.repertoireId);
    }
    expect(seen.size).toBe(black.length);
  });

  it('refuses a repertoire that does not play the chosen colour', () => {
    const white = reps.find((r) => r.color === 'w')!;
    expect(startRepertoireRun(reps, 'b', { seed: 1, repertoireId: white.id })).toBeNull();
  });

  it('lists only the repertoires an option set can actually use', () => {
    const white = reps.find((r) => r.color === 'w')!;
    expect(playableRepertoires(reps, 'w').map((r) => r.id)).toEqual([white.id]);
    expect(playableRepertoires(reps, 'w', { repertoireId: white.id })).toHaveLength(1);
    expect(playableRepertoires(reps, 'b', { repertoireId: white.id })).toHaveLength(0);
    expect(playableRepertoires(reps, 'random')).toHaveLength(reps.length);
  });
});

describe('playing the other side', () => {
  const reps = buildSeedRepertoires();

  it('puts you on the side the repertoire prepares against', () => {
    for (let seed = 0; seed < 10; seed += 1) {
      const run = startRepertoireRun(reps, 'w', { seed, reverse: true })!;
      expect(run).not.toBeNull();
      const rep = reps.find((r) => r.id === run.repertoireId)!;
      // A Black repertoire, played from White's side of the board.
      expect(rep.color).toBe('b');
      expect(run.color).toBe('w');
      expect(run.reverse).toBe(true);
    }
  });

  it('judges the opponent moves the repertoire prepares for', () => {
    // A Black repertoire answering 1.d4; reversed, you are the White player and
    // 1.d4 is the move that keeps you alive.
    const rep = createRepertoire('Black — King’s Indian', 'b', 'rep_kid');
    const built = addLine(rep, ['d4', 'Nf6', 'c4', 'g6', 'Nc3', 'Bg7'], 'seed').rep;
    const run = startRepertoireRun([built], 'w', { seed: 1, reverse: true, minDecisions: 3 })!;
    const source = repertoireSource(built);

    expect(run.color).toBe('w');
    expect(movesHere(source, run)).toEqual(['d4']);
    expect(play(source, run, 'e4').ok).toBe(false);
    const after = play(source, run, 'd4');
    expect(after.ok).toBe(true);
  });

  it('has nothing to offer when no repertoire plays the other colour', () => {
    const only = whiteRep();
    // Reversed, playing White needs a Black repertoire — and there is none.
    expect(startRepertoireRun([only], 'w', { seed: 1, reverse: true })).toBeNull();
    expect(startRepertoireRun([only], 'b', { seed: 1, reverse: true })).not.toBeNull();
  });

  it('plays a reversed run out to the end of the line', () => {
    const run = startRepertoireRun(reps, 'w', { seed: 3, reverse: true })!;
    const rep = reps.find((r) => r.id === run.repertoireId)!;
    const source = repertoireSource(rep);
    const done = finish(source, run);
    expect(done.over).toBe(false);
    expect(playedIsLegal(done)).toBe(true);
    expect(done.survived).toBeGreaterThan(0);
  });
});

describe('targeting weak spots', () => {
  const reps = buildSeedRepertoires();
  const rep = reps.find((r) => r.color === 'w')!;

  function lapsedCard(key: string, repertoireId: string): Card {
    return {
      id: cardId(repertoireId, key),
      repertoireId,
      key,
      fen: '',
      stage: 'review',
      step: 0,
      interval: 1,
      ease: 1.3,
      reps: 8,
      lapses: 6,
      correct: 1,
      incorrect: 7,
      due: 0,
      lastReviewed: 1,
      createdAt: 1,
    };
  }

  it('rates a lapsed position above one never seen, and both above a solid one', () => {
    const solid: Card = {
      ...lapsedCard('solid', rep.id),
      ease: 2.9,
      lapses: 0,
      correct: 9,
      incorrect: 0,
      due: Date.now() + 9e8,
    };
    const weakness = weaknessFromCards({
      [cardId(rep.id, 'bad')]: lapsedCard('bad', rep.id),
      [cardId(rep.id, 'solid')]: solid,
    });
    expect(weakness(rep.id, 'bad')).toBeGreaterThan(weakness(rep.id, 'unseen'));
    expect(weakness(rep.id, 'unseen')).toBeGreaterThan(weakness(rep.id, 'solid'));
  });

  it('averages the appetite over the positions the line asks about', () => {
    const weakness: Weakness = (_id, key) => (key === 'hot' ? 7 : 1);
    expect(lineWeakness(rep.id, ['hot', 'hot'], weakness)).toBe(7);
    expect(lineWeakness(rep.id, ['hot', 'cold'], weakness)).toBe(4);
    expect(lineWeakness(rep.id, [], weakness)).toBe(1);
  });

  it('draws the line you are bad at far more often than the one you know', () => {
    // Two lines with nothing in common after move one, so the weighting cannot
    // leak between them.
    let two = createRepertoire('White \u2014 Two lines', 'w', 'rep_two');
    const weak = ['d4', 'd5', 'c4', 'e6', 'Nc3', 'Nf6', 'Bg5', 'Be7'];
    const known = ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6', 'Ba4', 'Nf6'];
    two = addLine(two, weak, 'seed').rep;
    two = addLine(two, known, 'seed').rep;

    // Everything past the opening move of the weak line is a sore spot.
    const { fens } = walkSan(weak);
    const sore = new Set(fens.filter((_, i) => i % 2 === 0).slice(1).map(positionKey));
    const weakness: Weakness = (_id, key) => (sore.has(key) ? 40 : 1);

    let biased = 0;
    let plain = 0;
    for (let seed = 0; seed < 60; seed += 1) {
      if (startsWith(startRepertoireRun([two], 'w', { seed, weakness }), weak)) biased += 1;
      if (startsWith(startRepertoireRun([two], 'w', { seed }), weak)) plain += 1;
    }
    expect(plain).toBeGreaterThan(15);
    expect(plain).toBeLessThan(45);
    expect(biased).toBeGreaterThan(50);
  });

  it('weights the draw only when the option is on', () => {
    let two = createRepertoire('White \u2014 Two lines', 'w', 'rep_two');
    const weak = ['d4', 'd5', 'c4', 'e6', 'Nc3', 'Nf6', 'Bg5', 'Be7'];
    two = addLine(two, weak, 'seed').rep;
    two = addLine(two, ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6', 'Ba4', 'Nf6'], 'seed').rep;
    const { fens } = walkSan(weak);
    const sore = new Set(fens.filter((_, i) => i % 2 === 0).slice(1).map(positionKey));
    const weakness: Weakness = (_id, key) => (sore.has(key) ? 40 : 1);

    let on = 0;
    let off = 0;
    for (let seed = 0; seed < 40; seed += 1) {
      const a = beginRun({ reps: [two], index, color: 'w', seed, weakFirst: true, weakness });
      const b = beginRun({ reps: [two], index, color: 'w', seed, weakness });
      if (startsWith(a?.run ?? null, weak)) on += 1;
      if (startsWith(b?.run ?? null, weak)) off += 1;
    }
    expect(on).toBeGreaterThan(off);
  });
});

describe('the clock', () => {
  it('describes each budget as either per move or per run', () => {
    expect(clockSpec('off')).toEqual({ perMove: null, perRun: null });
    expect(clockSpec('move10')).toEqual({ perMove: 10, perRun: null });
    expect(clockSpec('move30')).toEqual({ perMove: 30, perRun: null });
    expect(clockSpec('run180')).toEqual({ perMove: null, perRun: 180 });
  });

  it('labels every mode it offers', () => {
    for (const mode of CLOCK_MODES) {
      expect(clockLabel(mode)).toBeTruthy();
      expect(clockDescription(mode).length).toBeGreaterThan(10);
    }
  });

  it('ends the run where it stands, with no move played', () => {
    const rep = whiteRep();
    const source = repertoireSource(rep);
    const started = startRepertoireRun([rep], 'w', { seed: 1 })!;
    const moved = play(source, started, 'd4').run;
    const dead = timeOut(moved);
    expect(dead.over).toBe(true);
    expect(dead.survived).toBe(moved.survived);
    expect(dead.played).toEqual(moved.played);
  });
});

describe('hints', () => {
  const rep = whiteRep();
  const source = repertoireSource(rep);

  it('spends one from the budget and names the square the move starts on', () => {
    const run = startRepertoireRun([rep], 'w', { seed: 1, hints: 1 })!;
    const taken = takeHint(source, run)!;
    expect(taken.from).toBe('d2');
    expect(taken.san).toBe('d4');
    expect(taken.run.hints).toBe(0);
    expect(taken.run.hintsUsed).toBe(1);
  });

  it('gives nothing away once the budget is gone', () => {
    const run = startRepertoireRun([rep], 'w', { seed: 1, hints: 0 })!;
    expect(takeHint(source, run)).toBeNull();
  });

  it('does not touch the score', () => {
    const run = startRepertoireRun([rep], 'w', { seed: 1, hints: 3 })!;
    const taken = takeHint(source, run)!;
    expect(taken.run.survived).toBe(run.survived);
    expect(taken.run.fen).toBe(run.fen);
  });

  it('carries the budget from the options into the run', () => {
    const started = beginRun({ reps: [rep], index, color: 'w', seed: 1, hints: 3 })!;
    expect(started.run.hints).toBe(3);
    const book = beginRun({ reps: [rep], index, kind: 'book', color: 'w', seed: 1, hints: 1 })!;
    expect(book.run.hints).toBe(1);
  });
});

describe('defaults', () => {
  it('turns every extra off', () => {
    expect(DEFAULT_OPTIONS).toMatchObject({
      repertoireId: '',
      reverse: false,
      weakFirst: false,
      clock: 'off',
      hints: 0,
    });
  });

  it('leaves a run unconstrained when nothing is chosen', () => {
    const reps = buildSeedRepertoires();
    const started = beginRun({ ...DEFAULT_OPTIONS, reps, index, seed: 2 })!;
    expect(started.run.hints).toBe(0);
    expect(started.run.reverse).toBe(false);
  });
});

/** Did the run draw the line starting with these moves? */
function startsWith(run: Run | null, sans: string[]): boolean {
  if (!run) return false;
  return sans.every((san, i) => run.target[i] === san);
}
