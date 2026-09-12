import { describe, expect, it } from 'vitest';
import { fenTurn, walkSan } from '../chess/core';
import {
  continuation,
  currentFen,
  fullLine,
  lineName,
  EMPTY_RECORD,
  expectedMoves,
  isComplete,
  isUsersTurn,
  opponentReply,
  play,
  playedIsLegal,
  recordRun,
  revealText,
  startRun,
} from './permadeath';
import { addLine, createRepertoire } from './repertoire';
import { mulberry32 } from './session';
import { referenceIndex } from './referenceIndex';
import { buildSeedRepertoires } from '../store/seed';
import type { Repertoire } from './types';

function whiteRep(): Repertoire {
  let rep = createRepertoire("White — Queen's Gambit", 'w', 'rep_w');
  rep = addLine(rep, ['d4', 'd5', 'c4', 'e6', 'Nc3', 'Nf6', 'cxd5', 'exd5', 'Bg5'], 'seed').rep;
  rep = addLine(rep, ['d4', 'd5', 'c4', 'c6', 'Nf3', 'Nf6', 'Nc3', 'dxc4', 'a4'], 'seed').rep;
  return rep;
}

const rand = () => 0.5;

describe('starting a run', () => {
  it('picks a line long enough to be a game', () => {
    const run = startRun([whiteRep()], { seed: 1, minDecisions: 4 })!;
    expect(run).not.toBeNull();
    expect(run.target.length).toBeGreaterThanOrEqual(7);
    expect(run.survived).toBe(0);
    expect(run.over).toBe(false);
    expect(run.played).toEqual([]);
  });

  it('refuses when no line is long enough', () => {
    const shallow = addLine(createRepertoire('x', 'w', 'r'), ['d4'], 'seed').rep;
    expect(startRun([shallow], { seed: 1, minDecisions: 4 })).toBeNull();
  });

  it('is deterministic for a seed and varies across seeds', () => {
    const reps = buildSeedRepertoires();
    const a = startRun(reps, { seed: 7 })!;
    const b = startRun(reps, { seed: 7 })!;
    expect(a.target).toEqual(b.target);
    const seen = new Set<string>();
    for (let s = 0; s < 40; s += 1) seen.add(startRun(reps, { seed: s })!.target.join(','));
    expect(seen.size).toBeGreaterThan(20);
  });

  it('spreads runs across repertoires rather than favouring the biggest', () => {
    const reps = buildSeedRepertoires();
    const byRep = new Map<string, number>();
    for (let s = 0; s < 90; s += 1) {
      const run = startRun(reps, { seed: s })!;
      byRep.set(run.repertoireId, (byRep.get(run.repertoireId) ?? 0) + 1);
    }
    expect(byRep.size).toBe(reps.length);
    for (const count of byRep.values()) expect(count).toBeGreaterThan(10);
  });

  it('starts on the user move for White and after a reply for Black', () => {
    const white = whiteRep();
    expect(isUsersTurn(white, startRun([white], { seed: 1 })!)).toBe(true);
    const reps = buildSeedRepertoires();
    const black = reps.find((r) => r.color === 'b')!;
    const run = startRun([black], { seed: 2 })!;
    expect(fenTurn(currentFen(black, run))).toBe('w');
  });
});

describe('playing a run', () => {
  const rep = whiteRep();

  it('accepts a prepared move and counts it', () => {
    const run = startRun([rep], { seed: 1 })!;
    const res = play(rep, run, 'd4');
    expect(res.ok).toBe(true);
    if (res.ok) {
      expect(res.run.survived).toBe(1);
      expect(res.run.over).toBe(false);
      expect(res.run.played).toEqual(['d4']);
    }
  });

  it('ends the run on anything outside the repertoire', () => {
    const run = startRun([rep], { seed: 1 })!;
    const res = play(rep, run, 'e4');
    expect(res.ok).toBe(false);
    if (!res.ok) {
      expect(res.run.over).toBe(true);
      expect(res.expected).toEqual(['d4']);
      expect(res.played).toBe('e4');
    }
  });

  it('accepts a prepared alternative and re-targets onto that branch', () => {
    // A repertoire that deliberately keeps two moves for the user in one
    // position: whichever the user steers into has to count as correct.
    let alt = createRepertoire('alt', 'w', 'rep_alt');
    alt = addLine(alt, ['d4', 'd5', 'c4', 'e6', 'Nc3', 'Nf6', 'Bg5'], 'seed').rep;
    alt = addLine(alt, ['d4', 'd5', 'c4', 'e6', 'Nf3', 'Nf6', 'Bf4'], 'seed').rep;

    let run = startRun([alt], { seed: 1, minDecisions: 3 })!;
    run = (play(alt, run, 'd4') as { run: typeof run }).run;
    run = opponentReply(alt, run, rand);
    run = (play(alt, run, 'c4') as { run: typeof run }).run;
    run = opponentReply(alt, run, rand);

    const options = expectedMoves(alt, run).map((o) => o.san);
    expect(options.sort()).toEqual(['Nc3', 'Nf3']);
    const onTarget = options.find((san) =>
      run.target.includes(expectedMoves(alt, run).find((o) => o.san === san)!.id),
    )!;
    const other = options.find((san) => san !== onTarget)!;

    const res = play(alt, run, other);
    expect(res.ok).toBe(true);
    if (res.ok) {
      expect(res.run.survived).toBe(3);
      // The opponent now follows the branch the user chose, not the original.
      const after = opponentReply(alt, res.run, rand);
      expect(after.played.at(-1)).toBe('Nf6');
      const next = expectedMoves(alt, after).map((o) => o.san);
      expect(next).toEqual([other === 'Nc3' ? 'Bg5' : 'Bf4']);
    }
  });

  it('lets the opponent follow the chosen line', () => {
    let run = startRun([rep], { seed: 1 })!;
    run = (play(rep, run, 'd4') as { run: typeof run }).run;
    const next = opponentReply(rep, run, rand);
    expect(next.played).toEqual(['d4', 'd5']);
    expect(run.target).toContain(next.nodeId);
  });

  it('plays a full run to the end of the line and reports completion', () => {
    let run = startRun([rep], { seed: 1 })!;
    let guard = 0;
    while (!run.over && !isComplete(rep, run) && guard < 40) {
      guard += 1;
      if (isUsersTurn(rep, run)) {
        const expected = expectedMoves(rep, run);
        const res = play(rep, run, expected[0].san);
        expect(res.ok).toBe(true);
        run = res.run;
      } else {
        run = opponentReply(rep, run, rand);
      }
    }
    expect(isComplete(rep, run)).toBe(true);
    expect(run.survived).toBeGreaterThanOrEqual(4);
    expect(playedIsLegal(run)).toBe(true);
    expect(walkSan(run.played).moves).toHaveLength(run.played.length);
  });

  it('reveals the whole secret line, not just what was reached', () => {
    let run = startRun([rep], { seed: 1 })!;
    run = (play(rep, run, 'd4') as { run: typeof run }).run;
    run = opponentReply(rep, run, rand);
    const text = revealText(rep, run);
    expect(text.startsWith('1. d4 d5')).toBe(true);
    // It keeps going past the two moves actually played.
    expect(text.split(' ').length).toBeGreaterThan(5);
  });

  it('keeps the losing move out of the line it reveals', () => {
    let run = startRun([rep], { seed: 1 })!;
    run = (play(rep, run, 'd4') as { run: typeof run }).run;
    run = opponentReply(rep, run, rand);
    const dead = play(rep, run, 'a3');
    expect(dead.ok).toBe(false);
    if (!dead.ok) {
      expect(dead.run.played).not.toContain('a3');
      expect(revealText(rep, dead.run)).not.toContain('a3');
      expect(revealText(rep, dead.run).startsWith('1. d4 d5')).toBe(true);
    }
  });

  it('shows how the line would have continued after a death', () => {
    let run = startRun([rep], { seed: 1 })!;
    run = (play(rep, run, 'd4') as { run: typeof run }).run;
    run = opponentReply(rep, run, rand);
    const dead = play(rep, run, 'a3');
    expect(dead.ok).toBe(false);
    if (!dead.ok) expect(continuation(rep, dead.run).length).toBeGreaterThan(0);
  });
});

describe('runs against the seeded repertoires', () => {
  const reps = buildSeedRepertoires();

  it('every seed produces a legal, finishable run', () => {
    for (let s = 0; s < 25; s += 1) {
      const run0 = startRun(reps, { seed: s })!;
      const rep = reps.find((r) => r.id === run0.repertoireId)!;
      let run = run0;
      const pick = mulberry32(s + 1);
      let guard = 0;
      while (!run.over && !isComplete(rep, run) && guard < 80) {
        guard += 1;
        if (isUsersTurn(rep, run)) {
          const expected = expectedMoves(rep, run);
          expect(expected.length).toBeGreaterThan(0);
          run = play(rep, run, expected[0].san).run;
        } else {
          run = opponentReply(rep, run, pick);
        }
      }
      expect(run.over).toBe(false);
      expect(playedIsLegal(run)).toBe(true);
      expect(run.survived).toBeGreaterThanOrEqual(4);
    }
  });
});

describe('naming the line at the end of a run', () => {
  const reps = buildSeedRepertoires();
  const index = referenceIndex();

  function finish(seed: number) {
    const run0 = startRun(reps, { seed })!;
    const rep = reps.find((r) => r.id === run0.repertoireId)!;
    let run = run0;
    const pick = mulberry32(seed + 1);
    let guard = 0;
    while (!run.over && !isComplete(rep, run) && guard < 80) {
      guard += 1;
      if (isUsersTurn(rep, run)) run = play(rep, run, expectedMoves(rep, run)[0].san).run;
      else run = opponentReply(rep, run, pick);
    }
    return { rep, run };
  }

  it('never labels a line with a name so generic it says nothing', () => {
    const generic = /^(King's|Queen's) Pawn Opening$|^Réti Opening$|^English Opening$|^Queen's Pawn Opening$/;
    const bad: string[] = [];
    for (let seed = 0; seed < 40; seed += 1) {
      const { rep, run } = finish(seed);
      const label = lineName(index, rep, run);
      if (generic.test(label.name)) bad.push(`${label.name} <- ${fullLine(rep, run).slice(0, 8).join(' ')}`);
    }
    expect(bad).toEqual([]);
  });

  it('falls back to the repertoire when the database only knows the opening vaguely', () => {
    const { rep, run } = finish(0);
    // A depth no real variation reaches forces the fallback path.
    const label = lineName(index, rep, run, 99);
    expect(label.specific).toBe(false);
    expect(label.name).toBe(run.repertoireName);
  });

  it('names the variation, not just the opening', () => {
    const specific = new Set<string>();
    let named = 0;
    for (let seed = 0; seed < 40; seed += 1) {
      const { rep, run } = finish(seed);
      const label = lineName(index, rep, run);
      specific.add(label.name);
      if (label.specific) named += 1;
    }
    // Most runs should get a real variation name, not the fallback.
    expect(named / 40).toBeGreaterThan(0.95);
    // Distinct variations, not one blanket label per repertoire.
    expect(specific.size).toBeGreaterThan(6);
    expect([...specific].some((n) => /Mar del Plata|Yugoslav|Botvinnik|Sämisch|Benoni/.test(n))).toBe(true);
  });

  it('names a run that ended early the same way', () => {
    const run0 = startRun(reps, { seed: 3 })!;
    const rep = reps.find((r) => r.id === run0.repertoireId)!;
    // Die on the very first decision; the line is still named in full.
    let run = run0;
    if (!isUsersTurn(rep, run)) run = opponentReply(rep, run, () => 0.5);
    const dead = play(rep, run, 'Na3').ok ? null : play(rep, run, 'Na3');
    const target = dead && !dead.ok ? dead.run : run;
    expect(lineName(index, rep, target).name.length).toBeGreaterThan(3);
  });
});

describe('the record', () => {
  it('tracks runs, best depth and survivals', () => {
    let record = EMPTY_RECORD;
    record = recordRun(record, 6, false, 1000);
    expect(record).toEqual({ runs: 1, best: 6, lastDepth: 6, lastAt: 1000, survivals: 0 });
    record = recordRun(record, 3, false, 2000);
    expect(record.best).toBe(6);
    expect(record.lastDepth).toBe(3);
    record = recordRun(record, 9, true, 3000);
    expect(record).toEqual({ runs: 3, best: 9, lastDepth: 9, lastAt: 3000, survivals: 1 });
  });
});
