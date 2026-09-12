import { describe, expect, it } from 'vitest';
import { applySan, fenTurn, positionKey, START_FEN, walkSan } from '../chess/core';
import {
  lineToKeep,
  canKeepLine,
  beginRun,
  bookHas,
  bookSource,
  clockDescription,
  clockLabel,
  clockSpec,
  CLOCK_MODES,
  BLUNDER_LIMIT,
  DEFAULT_OPTIONS,
  gradeLabel,
  gradeOf,
  GRADES,
  leavePrep,
  evalLoss,
  extend,
  extendedMoves,
  isExtended,
  judgeByEval,
  openingSource,
  playExtended,
  startOpeningRun,
  lineOdds,
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
} from './openingRun';
import { addLine, createRepertoire, displayName, leafLines, pathTo } from './repertoire';
import { lookup, openingById } from './reference';
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
      const run0 = startRepertoireRun(reps, 'random', { seed, index })!;
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
      const run0 = startRepertoireRun(reps, 'random', { seed, index })!;
      const source = repertoireSource(reps.find((r) => displayName(r.name) === run0.sourceLabel)!);
      const label = lineName(index, source, finish(source, run0, seed + 1));
      distinct.add(label.name);
      if (label.specific) named += 1;
    }
    // Not every line can be named: a couple of offbeat tries have no entry in
    // the database, and the fallback — the repertoire's own name — is honest
    // about that rather than inventing one.
    expect(named / 40).toBeGreaterThan(0.9);
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
  let ids = 0;
  const outcome = (depth: number, completed: boolean, key = 'rep:a:w', id = `r${(ids += 1)}`) => ({
    id,
    key,
    grade: completed ? ('green' as const) : ('red' as const),
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
    expect(filed.id).toBe(run.id);
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
      extended: false,
      openingId: '',
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
    // 1.d4 is most of what a King's Indian actually meets; 1.b4 is a curiosity.
    expect(share(rep, 'b', true, ['d4'])).toBeGreaterThan(0.5);
    expect(share(rep, 'b', true, ['b4'])).toBeLessThan(0.05);
  });

  it('finds move orders that leaf counts had buried', () => {
    // 1.Nf3 is a common route into these positions, but the repertoire answers
    // it with few lines — counting leaves made it look like a curiosity.
    const rep = kid[0];
    expect(share(rep, 'b', true, ['Nf3'])).toBeGreaterThan(share(rep, 'b', false, ['Nf3']) * 2);
  });

  it('cuts how often a run turns on a reply almost nobody plays', () => {
    const rep = kid[0];
    /** Odds of drawing a line whose rarest opponent move is under `limit`. */
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

    // Sidelines must not vanish — they are prep too — but they should not be a
    // quarter of every run either.
    expect(obscure(true, 0.05)).toBeLessThan(obscure(false, 0.05) * 0.75);
    expect(obscure(true, 0.05)).toBeGreaterThan(0.05);
  });

  it('keeps a prepared sideline in the rotation rather than burying it', () => {
    const rep = kid[0];
    // The exact shape that can catch you out: a rare third move with one answer.
    const sideline = share(rep, 'b', true, ['d4', 'Nf6', 'Nf3', 'g6', 'Bg5']);
    expect(sideline).toBeGreaterThan(0);
    expect(sideline).toBeLessThan(0.05);
  });

  it('does not let your own alternatives inflate a line', () => {
    // Two answers to the same opponent move are one position on the board, so
    // they split that position's odds rather than doubling its pull.
    let rep = createRepertoire('Black — Forks', 'b', 'rep_forks');
    rep = addLine(rep, ['d4', 'Nf6', 'c4', 'g6', 'Nc3', 'Bg7', 'e4', 'd6'], 'seed').rep;
    rep = addLine(rep, ['d4', 'Nf6', 'c4', 'g6', 'Nc3', 'Bg7', 'e4', 'O-O'], 'seed').rep;
    rep = addLine(rep, ['d4', 'Nf6', 'c4', 'g6', 'Nc3', 'Bg7', 'e4', 'c5'], 'seed').rep;
    rep = addLine(rep, ['d4', 'Nf6', 'Bg5', 'Ne4', 'Bf4', 'd5'], 'seed').rep;

    const mainline = share(rep, 'b', true, ['d4', 'Nf6', 'c4']);
    const sideline = share(rep, 'b', true, ['d4', 'Nf6', 'Bg5']);
    // Three of the four leaves are the mainline, but they are one move order.
    expect(mainline + sideline).toBeCloseTo(1, 5);
    expect(mainline).toBeGreaterThan(sideline * 10);
  });

  it('gives the rarest lines back their share when short ones are skipped', () => {
    const rep = kid[0];
    const usable = new Set(
      leafLines(rep)
        .filter((l) => l.sans.filter((_, i) => i % 2 === 1).length >= 4)
        .map((l) => l.tipId),
    );
    const odds = lineOdds(rep, 'b', index, usable);
    const total = [...odds.values()].reduce((sum, n) => sum + n, 0);
    // Skipped lines hand their odds to their siblings instead of losing them.
    expect(total).toBeCloseTo(1, 5);
    expect([...odds.keys()].every((id) => usable.has(id))).toBe(true);
  });

  it('draws evenly with no reference data rather than guessing', () => {
    expect(lineOdds(kid[0], 'b', null).size).toBe(0);
  });
});

describe('what counts as staying in your repertoire', () => {
  const reps = buildSeedRepertoires();
  const kid = reps.find((r) => r.name.includes('King'))!;
  const source = repertoireSource(kid, index);

  /** The position after these moves, as a run sitting on it. */
  function at(sans: string[]): Run {
    return {
      source: 'repertoire',
      sourceLabel: 'King’s Indian',
      repertoireId: kid.id,
      reverse: false,
      leftPrep: false,
      color: 'b',
      fen: walkSan(sans).fens[sans.length],
      id: 'probe',
      played: sans,
      survived: 0,
      over: false,
      target: [],
      hints: 0,
      hintsUsed: 0,
      prepEnded: null,
    };
  }

  it('accepts every prepared answer, not just the one line drawn', () => {
    // 1.d4 Nf6 2.c4 g6 3.Nc3 Bg7 4.e4 d6 — several plans are prepared here.
    const run = at(['d4', 'Nf6', 'c4', 'g6', 'Nc3', 'Bg7']);
    const options = movesHere(source, run);
    expect(options.length).toBeGreaterThan(1);
    for (const san of options) expect(play(source, run, san).ok).toBe(true);
  });

  it('ends the run on a move prepared somewhere else in the repertoire', () => {
    // ...Nh5 is real King's Indian prep — after d5, against a bishop on e3 or
    // f4. It is not prepared against an early Bg5, and the run says so.
    const run = at(['d4', 'Nf6', 'Nf3', 'g6', 'Bg5']);
    expect(movesHere(source, run)).toEqual(['Bg7']);
    const judged = play(source, run, 'Nh5');
    expect(judged.ok).toBe(false);
    if (!judged.ok) expect(judged.expected).toEqual(['Bg7']);

    const elsewhere = at(['d4', 'Nf6', 'c4', 'g6', 'Nc3', 'Bg7', 'e4', 'd6', 'f3', 'O-O', 'Be3', 'e5', 'd5']);
    expect(movesHere(source, elsewhere)).toContain('Nh5');
  });
});

describe('extended mode', () => {
  const rep = whiteRep();
  const source = repertoireSource(rep);

  it('is off by default', () => {
    expect(DEFAULT_OPTIONS.extended).toBe(false);
    const run = startRepertoireRun([rep], 'w', { seed: 1 })!;
    expect(isExtended(run)).toBe(false);
    expect(run.prepEnded).toBeNull();
  });

  it('ends a run at the edge of the prep until the engine takes over', () => {
    const run = finish(source, startRepertoireRun([rep], 'w', { seed: 1 })!);
    expect(isComplete(source, run)).toBe(true);
    // Handed over, the same position is no longer the end of anything.
    const carried = extend(run);
    expect(isExtended(carried)).toBe(true);
    expect(isComplete(source, carried)).toBe(false);
    expect(carried.prepEnded).toBe(run.played.length);
  });

  it('remembers where the prep ended, once', () => {
    const run = extend({ ...startRepertoireRun([rep], 'w', { seed: 1 })!, played: ['d4', 'd5'] });
    expect(run.prepEnded).toBe(2);
    expect(extend({ ...run, played: ['d4', 'd5', 'c4', 'e6'] }).prepEnded).toBe(2);
  });

  it('measures a loss from your own side of the board', () => {
    // White is a pawn up before, level after: White dropped a pawn.
    expect(evalLoss('w', 100, 0)).toBe(100);
    // The same swing helps Black, so Black lost nothing.
    expect(evalLoss('b', 100, 0)).toBe(-100);
    // Black a pawn up (−100) drifting to level is Black's loss.
    expect(evalLoss('b', -100, 0)).toBe(100);
    expect(evalLoss('w', -100, 0)).toBe(-100);
  });

  it('allows an inaccuracy and stops a blunder', () => {
    // The threshold is generous on purpose; past the prep there is no one move.
    expect(BLUNDER_LIMIT).toBeGreaterThanOrEqual(50);
    expect(judgeByEval('w', 20, 20 - BLUNDER_LIMIT).ok).toBe(true);
    expect(judgeByEval('w', 20, 20 - BLUNDER_LIMIT - 1).ok).toBe(false);
    expect(judgeByEval('w', 20, 0).ok).toBe(true);
    expect(judgeByEval('w', 20, -50).ok).toBe(true);
    expect(judgeByEval('w', 20, -60).ok).toBe(true);
    expect(judgeByEval('w', 20, -61).ok).toBe(false);
    expect(judgeByEval('w', 20, -61).lost).toBe(81);
    expect(judgeByEval('b', -20, 300).ok).toBe(false);
  });

  it('never counts finding better than the engine as a loss', () => {
    expect(judgeByEval('w', 10, 400)).toEqual({ ok: true, lost: 0 });
    expect(judgeByEval('b', 10, -400)).toEqual({ ok: true, lost: 0 });
  });

  it('takes your move and the reply together, scoring one move', () => {
    const start = extend(startRepertoireRun([rep], 'w', { seed: 1 })!);
    const next = playExtended(start, 'd4', 'd5');
    expect(next.played).toEqual(['d4', 'd5']);
    expect(next.survived).toBe(start.survived + 1);
    expect(playedIsLegal(next)).toBe(true);
    expect(fenTurn(next.fen)).toBe('w');
  });

  it('accepts a last move with no reply when the game is over', () => {
    const start = extend(startRepertoireRun([rep], 'w', { seed: 1 })!);
    const next = playExtended(start, 'd4', null);
    expect(next.played).toEqual(['d4']);
    expect(fenTurn(next.fen)).toBe('b');
  });

  it('refuses to apply a move that is not legal', () => {
    const start = extend(startRepertoireRun([rep], 'w', { seed: 1 })!);
    expect(playExtended(start, 'e5', null).over).toBe(true);
  });

  it('counts only your own moves as being past the prep', () => {
    const base = startRepertoireRun([rep], 'w', { seed: 1 })!;
    const carried = extend({ ...base, played: ['d4', 'd5'] });
    expect(extendedMoves(carried)).toBe(0);
    expect(extendedMoves({ ...carried, played: ['d4', 'd5', 'c4'] })).toBe(1);
    expect(extendedMoves({ ...carried, played: ['d4', 'd5', 'c4', 'e6'] })).toBe(1);
    expect(extendedMoves({ ...carried, played: ['d4', 'd5', 'c4', 'e6', 'Nc3'] })).toBe(2);
    expect(extendedMoves(base)).toBe(0);
  });

  it('amends the record instead of counting a carried-on run twice', () => {
    const run = startRepertoireRun([rep], 'w', { seed: 1 })!;
    // The line is played out and logged.
    let record = recordRun(EMPTY_RECORD, outcomeOf({ ...run, survived: 4 }, true), 1000);
    expect(record).toMatchObject({ runs: 1, best: 4, survivals: 1 });

    // Carried on, it goes deeper and then blunders — still one run, and the
    // line it already finished stays finished.
    record = recordRun(record, outcomeOf({ ...extend(run), survived: 11 }, false), 2000);
    expect(record).toMatchObject({ runs: 1, best: 11, survivals: 1, lastDepth: 11 });
    expect(record.byLine[outcomeOf(run, false).key]).toMatchObject({
      runs: 1,
      best: 11,
      survivals: 1,
    });

    // Amending twice more does not stack survivals either.
    record = recordRun(record, outcomeOf({ ...extend(run), survived: 14 }, true), 2500);
    expect(record).toMatchObject({ runs: 1, best: 14, survivals: 1 });

    // A genuinely new run still counts as one.
    const other = startRepertoireRun([rep], 'w', { seed: 2 })!;
    expect(other.id).not.toBe(run.id);
    record = recordRun(record, outcomeOf({ ...other, survived: 3 }, false), 3000);
    expect(record).toMatchObject({ runs: 2, best: 14, survivals: 1 });
  });

  it('reads a record saved before runs had an identity', () => {
    const old = { runs: 2, best: 5, lastDepth: 5, lastAt: 9, survivals: 1, byLine: {} };
    const fixed = normalizeRecord(old);
    expect(fixed.last).toBeUndefined();
    // With nothing to amend, the next run counts as its own.
    expect(
      recordRun(fixed, {
        id: 'x',
        key: 'k',
        grade: 'red',
        label: 'L',
        color: 'w',
        depth: 2,
        completed: false,
      }).runs,
    ).toBe(3);
  });
});

describe('the opening catalogue', () => {
  it('ranks openings by how often they are actually played', () => {
    const { catalogue } = index;
    expect(catalogue.length).toBeGreaterThan(100);
    const names = catalogue.slice(0, 12).map((e) => e.name);
    expect(names).toContain('Sicilian Defence');
    expect(names).toContain("Queen's Gambit");
    // Sorted, and a mainline beats a curiosity by a wide margin.
    for (let i = 1; i < catalogue.length; i += 1) {
      expect(catalogue[i - 1].games).toBeGreaterThanOrEqual(catalogue[i].games);
    }
    const sicilian = catalogue.find((e) => e.name === 'Sicilian Defence')!;
    const wing = catalogue.find((e) => e.name === 'Sicilian: Wing Gambit')!;
    expect(sicilian.games).toBeGreaterThan(wing.games * 10);
  });

  it('holds a legal move order for every entry', () => {
    for (const entry of index.catalogue) {
      expect(entry.sans.length).toBeGreaterThanOrEqual(2);
      let fen = START_FEN;
      for (const san of entry.sans) {
        const move = applySan(fen, san);
        expect(move, `${entry.name}: ${entry.sans.join(' ')}`).not.toBeNull();
        fen = move!.after;
      }
    }
  });

  it('names each opening once', () => {
    const names = index.catalogue.map((e) => e.name);
    expect(new Set(names).size).toBe(names.length);
  });

  it('leaves out names that only say what the first move was', () => {
    const names = index.catalogue.map((e) => e.name);
    expect(names).not.toContain("King's Pawn Opening");
    expect(names).not.toContain("Queen's Pawn Opening");
  });

  it('finds an opening by its move order', () => {
    const first = index.catalogue[0];
    expect(openingById(index, first.id)).toEqual(first);
    expect(openingById(index, 'e4 e4 e4')).toBeNull();
  });
});

describe('running through one opening', () => {
  const dragon = index.catalogue.find((e) => e.name.includes('Dragon'))!;

  it('walks you into the opening and then hands over to the book', () => {
    expect(dragon).toBeDefined();
    const run = startOpeningRun(index, dragon, 'b', { seed: 1 })!;
    expect(run.source).toBe('opening');
    expect(run.openingId).toBe(dragon.id);
    expect(run.target).toEqual(dragon.sans);

    const source = openingSource(index, dragon, 'b');
    // Inside the opening its own move order is the only thing that counts.
    expect(movesHere(source, run)).toEqual([dragon.sans[0]]);
    const wrong = play(source, run, dragon.sans[0] === 'e4' ? 'd4' : 'e4');
    expect(wrong.ok).toBe(false);

    // Played out, the judging is the book's — whatever the book happens to say.
    const { fens } = walkSan(dragon.sans);
    const end = fens[dragon.sans.length];
    const book = bookSource(index, 'b');
    expect(source.movesAt(end)).toEqual(book.movesAt(end));
    expect(source.weightsAt(end)).toEqual(book.weightsAt(end));
    // Inside the opening it is not the book's judgement but the opening's.
    expect(source.movesAt(fens[1])).toEqual([dragon.sans[1]]);
    expect(book.movesAt(fens[1]).length).toBeGreaterThan(1);
  });

  it('plays out legally from either side', () => {
    for (const color of ['w', 'b'] as const) {
      const run = startOpeningRun(index, dragon, color, { seed: 3 })!;
      const source = openingSource(index, dragon, color);
      expect(run.color).toBe(color);
      const done = finish(source, run, 7);
      expect(playedIsLegal(done)).toBe(true);
      expect(done.played.slice(0, dragon.sans.length)).toEqual(dragon.sans);
    }
  });

  it('is named after the opening you chose', () => {
    const run = startOpeningRun(index, dragon, 'b', { seed: 2 })!;
    const source = openingSource(index, dragon, 'b');
    expect(source.label).toBe(dragon.name);
    expect(lineName(index, source, run, 99).name).toBe(dragon.name);
  });

  it('files its record under the opening and side', () => {
    const run = startOpeningRun(index, dragon, 'w', { seed: 4 })!;
    expect(outcomeOf(run, false).key).toBe(`opening:${dragon.id}:w`);
  });

  it('refuses to begin without an opening chosen', () => {
    expect(beginRun({ reps: [], index, kind: 'opening', openingId: '', seed: 1 })).toBeNull();
    expect(beginRun({ reps: [], index, kind: 'opening', openingId: 'nonsense', seed: 1 })).toBeNull();
    const ok = beginRun({ reps: [], index, kind: 'opening', openingId: dragon.id, color: 'b', seed: 1 });
    expect(ok?.run.sourceLabel).toBe(dragon.name);
  });

  it('has no opening chosen by default', () => {
    expect(DEFAULT_OPTIONS.openingId).toBe('');
  });
});

describe('stepping outside your prep', () => {
  const rep = whiteRep();
  const source = repertoireSource(rep, index);

  function at(sans: string[]): Run {
    const base = startRepertoireRun([rep], 'w', { seed: 1 })!;
    return { ...base, fen: walkSan(sans).fens[sans.length], played: sans, target: [] };
  }

  it('tells a real move apart from one nobody plays', () => {
    const run = at(['d4', 'd5']);
    // The repertoire plays 2.c4 here. 2.Nf3 is not prepared but is real theory.
    expect(movesHere(source, run)).toEqual(['c4']);
    expect(bookHas(index, run.fen, 'Nf3')).toBe(true);
    expect(bookHas(index, run.fen, 'Na3')).toBe(false);
    expect(play(source, run, 'Nf3').ok).toBe(false);
  });

  it('carries the run on and hands the judging to the book', () => {
    const run = at(['d4', 'd5']);
    const carried = leavePrep(run, 'Nf3');
    expect(carried.leftPrep).toBe(true);
    expect(carried.over).toBe(false);
    expect(carried.survived).toBe(run.survived + 1);
    expect(carried.played).toEqual(['d4', 'd5', 'Nf3']);
    // The drawn line stops steering, since it is not being followed any more.
    expect(carried.target).toEqual([]);
    expect(playedIsLegal(carried)).toBe(true);
  });

  it('refuses a move that is not legal', () => {
    // No white pawn can reach e5 from the start square.
    expect(applySan(at(['d4', 'd5']).fen, 'e5')).toBeNull();
    expect(leavePrep(at(['d4', 'd5']), 'e5').over).toBe(true);
  });

  it('grades the four endings apart', () => {
    const clean = at(['d4', 'd5']);
    const strayed = { ...clean, leftPrep: true };
    expect(gradeOf(clean, true)).toBe('green');
    expect(gradeOf(strayed, true)).toBe('yellow');
    expect(gradeOf(clean, false)).toBe('red');
    expect(gradeOf(strayed, false)).toBe('purple');
    for (const grade of GRADES) expect(gradeLabel(grade)).toBeTruthy();
  });

  it('files the grade with the run', () => {
    const run = at(['d4', 'd5']);
    expect(outcomeOf(run, true).grade).toBe('green');
    expect(outcomeOf(leavePrep(run, 'Nf3'), true).grade).toBe('yellow');
    expect(outcomeOf(leavePrep(run, 'Nf3'), false).grade).toBe('purple');
  });

  it('counts endings by grade, and moves the count when a run is amended', () => {
    const run = at(['d4', 'd5']);
    let record = recordRun(EMPTY_RECORD, outcomeOf({ ...run, survived: 4 }, true), 1000);
    expect(record.grades).toEqual({ green: 1, yellow: 0, red: 0, purple: 0 });

    // The same run carried on and ended out of prep: one run, one grade.
    const strayed = { ...leavePrep(run, 'Nf3'), survived: 9 };
    record = recordRun(record, outcomeOf(strayed, false), 2000);
    expect(record.runs).toBe(1);
    expect(record.grades).toEqual({ green: 0, yellow: 0, red: 0, purple: 1 });

    const other = at(['d4', 'd5']);
    record = recordRun(record, outcomeOf({ ...other, id: 'other', survived: 2 }, false), 3000);
    expect(record.grades).toEqual({ green: 0, yellow: 0, red: 1, purple: 1 });
  });

  it('reads a record saved before grades were counted', () => {
    const old = { runs: 3, best: 7, lastDepth: 1, lastAt: 5, survivals: 2, byLine: {} };
    const fixed = normalizeRecord(old);
    expect(fixed.grades).toEqual({ green: 0, yellow: 0, red: 0, purple: 0 });
    expect(fixed.runs).toBe(3);
  });

  it('starts every run inside its prep', () => {
    expect(startRepertoireRun([rep], 'w', { seed: 1 })!.leftPrep).toBe(false);
    expect(startBookRun(index, 'w', { seed: 1 })!.leftPrep).toBe(false);
  });
});

describe('keeping what a run survived', () => {
  function runOf(over: Partial<Run>): Run {
    return {
      id: 'r', source: 'book', sourceLabel: 'Book', reverse: false, leftPrep: false,
      color: 'w', fen: START_FEN, played: [], survived: 0, over: true, target: [],
      hints: 0, hintsUsed: 0, prepEnded: null, ...over,
    };
  }

  it('only keeps sources that produce theory', () => {
    expect(canKeepLine('opening')).toBe(true);
    expect(canKeepLine('book')).toBe(true);
    // A repertoire run is already playing your own lines back at you.
    expect(canKeepLine('repertoire')).toBe(false);
  });

  it('ends a White line on a White move', () => {
    const run = runOf({ color: 'w', played: ['e4', 'c5', 'Nf3', 'd6'] });
    expect(lineToKeep(run)).toEqual(['e4', 'c5', 'Nf3']);
  });

  it('ends a Black line on a Black move', () => {
    const run = runOf({ color: 'b', played: ['e4', 'c5', 'Nf3'] });
    expect(lineToKeep(run)).toEqual(['e4', 'c5']);
  });

  it('stops where the book stopped judging', () => {
    // Extended mode carried the run four plies past the prep; those were sound
    // but the book never vouched for them.
    const run = runOf({ color: 'w', played: ['e4', 'c5', 'Nf3', 'd6', 'd4', 'cxd4'], prepEnded: 3 });
    expect(lineToKeep(run)).toEqual(['e4', 'c5', 'Nf3']);
  });

  it('keeps nothing from a run that died on its first move', () => {
    expect(lineToKeep(runOf({ color: 'w', played: [] }))).toEqual([]);
    expect(lineToKeep(runOf({ color: 'b', played: ['e4'] }))).toEqual([]);
  });

  it('never includes the move that ended the run', () => {
    // `played` holds correct moves only; the fatal one is reported separately.
    const run = runOf({ color: 'w', played: ['e4', 'c5', 'Nf3'] });
    expect(lineToKeep(run)).not.toContain('Qh5');
  });
});
