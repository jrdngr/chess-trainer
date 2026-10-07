import { describe, expect, it } from 'vitest';
import { chooseMode, COLD_EVERY, coldStart, COLD_START_LABEL, rankModes, roundLabel, survivalPlanFor, type RoundMode } from './autopilot';
import { hasWork, missingPrep, SURVIVAL_FLOOR, targetShares, type MixSignals } from './recommend';
import { nodeById, openingTree } from './openingTree';
import { referenceIndex } from './referenceIndex';

/** A settled repertoire: big, drilled, nothing owed, prep holding. */
const solid: MixSignals = {
  lines: 30,
  positions: 120,
  due: 0,
  unseen: 0,
  unpracticed: 0,
  dueLines: 0,
  accuracy: 0.97,
  growReady: false,
};

/** Rounds in a row with the signals held still, and each mode's share of them. */
function session(s: MixSignals, rounds = 40): { played: RoundMode[]; share: (mode: RoundMode) => number } {
  const played: RoundMode[] = [];
  for (let i = 0; i < rounds; i += 1) played.push(chooseMode(s, played));
  return { played, share: (mode) => played.filter((m) => m === mode).length / rounds };
}

describe("Autopilot's mix of modes", () => {
  it('plays Survival when nothing else has work', () => {
    expect(session(solid).share('survival')).toBe(1);
  });

  it('only grows when an opening is ready', () => {
    expect(hasWork('growth', solid)).toBe(false);
    expect(targetShares(solid).growth).toBe(0);
    expect(targetShares({ ...solid, growReady: true }).growth).toBeGreaterThan(0);
  });

  it('grows a lot more while the repertoire is small', () => {
    const small = targetShares({ ...solid, lines: 3, growReady: true }).growth;
    const big = targetShares({ ...solid, lines: 30, growReady: true }).growth;
    expect(small).toBeCloseTo(0.3);
    expect(big).toBeCloseTo(0.05);
  });

  it('drills more with cards due or never drilled', () => {
    expect(targetShares({ ...solid, due: 2 }).drillPositions).toBeLessThan(targetShares({ ...solid, due: 30 }).drillPositions);
    expect(targetShares({ ...solid, unseen: 20 }).drillPositions).toBeGreaterThan(0.15);
  });

  it('drills more, and even with nothing due, while Survival shows the prep missing', () => {
    expect(missingPrep(null)).toBe(0);
    expect(missingPrep(0.97)).toBe(0);
    expect(missingPrep(0.8)).toBe(1);
    const missing = { ...solid, accuracy: 0.8 };
    expect(hasWork('drillPositions', missing)).toBe(true);
    expect(hasWork('drillLines', missing)).toBe(true);
    const shares = targetShares(missing);
    expect(shares.drillPositions).toBeGreaterThan(shares.drillLines);
    expect(shares.drillPositions + shares.drillLines).toBeGreaterThanOrEqual(0.45);
    // With cards and lines due too, Survival is down near its floor.
    expect(targetShares({ ...missing, due: 20, dueLines: 4 }).survival).toBeLessThan(0.5);
  });

  it('never gives Survival less than its floor, however much is owed', () => {
    const everything: MixSignals = { lines: 2, positions: 10, due: 50, unseen: 50, unpracticed: 9, dueLines: 9, accuracy: 0.5, growReady: true };
    const shares = targetShares(everything);
    expect(shares.survival).toBeCloseTo(SURVIVAL_FLOOR);
    expect(shares.survival + shares.growth + shares.drillPositions + shares.drillLines).toBeCloseTo(1);
    expect(session(everything).share('survival')).toBeGreaterThanOrEqual(SURVIVAL_FLOOR);
  });

  it('plays mostly Survival once the prep is solid and a little is due', () => {
    const settled = { ...solid, due: 3, dueLines: 1 };
    const { share } = session(settled);
    expect(share('survival')).toBeGreaterThanOrEqual(0.65);
    expect(share('drillPositions')).toBeGreaterThan(share('drillLines'));
  });

  it('leans toward Drill positions over Drill lines', () => {
    const owed = { ...solid, due: 20, unseen: 10, unpracticed: 4, dueLines: 4 };
    const { share } = session(owed);
    expect(share('drillPositions')).toBeGreaterThan(share('drillLines'));
    expect(share('drillLines')).toBeGreaterThan(0);
  });

  it('halves the mode just played', () => {
    const owed = { ...solid, due: 20 };
    const fresh = rankModes(owed, ['drillPositions', 'survival']).find((m) => m.mode === 'survival')!.score;
    const again = rankModes(owed, ['survival', 'survival']).find((m) => m.mode === 'survival')!.score;
    expect(again).toBeLessThan(fresh);
  });

  it('plays Survival right after every Drill round, however loudly the rest ask', () => {
    const everything: MixSignals = { lines: 2, positions: 10, due: 50, unseen: 50, unpracticed: 9, dueLines: 9, accuracy: 0.5, growReady: true };
    for (const drill of ['drillPositions', 'drillLines'] as RoundMode[]) {
      expect(chooseMode(everything, [drill])).toBe('survival');
      const ranked = rankModes(everything, ['growth', drill]);
      expect(ranked[0].mode).toBe('survival');
      expect(ranked.slice(1).every((m) => m.score === 0)).toBe(true);
    }
    session(everything).played.forEach((mode, i, played) => {
      if ((mode === 'drillPositions' || mode === 'drillLines') && i + 1 < played.length) expect(played[i + 1]).toBe('survival');
    });
  });

  it('drills freshly grown lines right after Growth, and weighs the round as usual otherwise', () => {
    expect(chooseMode({ ...solid, unpracticed: 2, growReady: true }, ['growth'])).toBe('drillLines');
    expect(chooseMode(solid, ['growth'])).toBe('survival');
  });

  it('opens a session on whatever is owed most', () => {
    expect(chooseMode({ ...solid, due: 30, unseen: 10, accuracy: 0.85 }, [])).toBe('drillPositions');
    expect(chooseMode({ ...solid, lines: 3, growReady: true }, [])).toBe('growth');
  });

  it('opens a session with Survival while the prep is solid and little is owed', () => {
    expect(chooseMode(solid, [])).toBe('survival');
    expect(chooseMode({ ...solid, due: 2 }, [])).toBe('survival');
  });
});

describe('a Survival round from a recommendation', () => {
  const tree = openingTree(referenceIndex());
  const sicilian = nodeById(tree, 'e4 c5');

  it('leans on popular lines for a test and weak ones for a review', () => {
    expect(survivalPlanFor({ focus: 'test', opening: sicilian, color: 'b', start: 'first' })).toEqual({
      color: 'b',
      toward: sicilian.id,
      enter: false,
      lean: 'popular',
    });
    expect(survivalPlanFor({ focus: 'review', opening: sicilian, color: 'b', start: 'inside' }).lean).toBe('weak');
    expect(survivalPlanFor({ focus: 'review', opening: sicilian, color: 'b', start: 'inside' }).enter).toBe(true);
  });
});

describe('Cold Start', () => {
  const tree = openingTree(referenceIndex());
  const qg = nodeById(tree, 'd4 d5 c4');
  const inside = { focus: 'review' as const, opening: qg, color: 'w' as const, start: 'inside' as const };
  const insides = Array.from({ length: COLD_EVERY - 1 }, () => 'inside' as const);

  it('starts from move one once the last runs all started inside', () => {
    const cold = coldStart(inside, insides);
    expect(cold).toEqual({ ...inside, start: 'first' });
    expect(survivalPlanFor(cold)).toMatchObject({ toward: qg.id, enter: false });
  });

  it('leaves the run inside until then', () => {
    expect(coldStart(inside, [])).toBe(inside);
    expect(coldStart(inside, insides.slice(1))).toBe(inside);
  });

  it('counts any run from move one, so a selection that mostly starts there is never pushed', () => {
    expect(coldStart(inside, ['first', ...insides.slice(1)])).toBe(inside);
    expect(coldStart(inside, [...insides.slice(1), 'first'])).toBe(inside);
  });

  it('comes round every fourth run when every run would start inside', () => {
    const starts: ('first' | 'inside')[] = [];
    for (let i = 0; i < 12; i++) starts.push(coldStart(inside, starts).start);
    expect(starts.filter((s) => s === 'first')).toHaveLength(12 / COLD_EVERY);
    expect(starts.slice(0, COLD_EVERY)).toEqual([...insides, 'first']);
  });

  it('is announced by its own name, wherever its start came from', () => {
    expect(roundLabel('survival', 'first')).toBe(COLD_START_LABEL);
    expect(roundLabel('survival', 'inside')).toBe('Survival');
    expect(roundLabel('drillLines')).toBe('Drill lines');
  });
});
