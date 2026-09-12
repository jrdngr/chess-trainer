import { describe, expect, it } from 'vitest';
import { fenTurn, walkSan } from '../chess/core';
import {
  bookSource,
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
  recordRun,
  repertoireSource,
  resolveColor,
  revealText,
  startBookRun,
  startRepertoireRun,
  type LineSource,
  type Run,
} from './permadeath';
import { addLine, createRepertoire, displayName } from './repertoire';
import { referenceIndex } from './referenceIndex';
import { mulberry32 } from './session';
import { buildSeedRepertoires } from '../store/seed';
import type { Repertoire } from './types';

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
  it('tracks runs, best depth and survivals', () => {
    let record = EMPTY_RECORD;
    record = recordRun(record, 6, false, 1000);
    expect(record).toEqual({ runs: 1, best: 6, lastDepth: 6, lastAt: 1000, survivals: 0 });
    record = recordRun(record, 3, false, 2000);
    expect(record.best).toBe(6);
    record = recordRun(record, 9, true, 3000);
    expect(record).toEqual({ runs: 3, best: 9, lastDepth: 9, lastAt: 3000, survivals: 1 });
  });
});
