import { describe, expect, it } from 'vitest';
import { chooseMode, MAX_RUN, modeNeed, rankModes, survivalPlanFor, type ModeNeeds, type RoundMode } from './autopilot';
import { nodeById, openingTree } from './openingTree';
import { referenceIndex } from './referenceIndex';

const quiet: ModeNeeds = { due: 0, unpracticed: 0, growReady: false };

describe("Autopilot's choice of mode", () => {
  it('plays Survival when nothing else asks', () => {
    expect(chooseMode(quiet, [])).toBe('survival');
    // Even round after round: nothing else has work, so the streak cap stays out of it.
    expect(chooseMode(quiet, Array<RoundMode>(MAX_RUN + 2).fill('survival'))).toBe('survival');
  });

  it('only asks for Growth when an opening is ready', () => {
    expect(modeNeed('growth', quiet)).toBe(0);
    expect(modeNeed('growth', { ...quiet, growReady: true })).toBe(1);
  });

  it('asks louder the more cards are due', () => {
    expect(modeNeed('drillPositions', { ...quiet, due: 2 })).toBeLessThan(modeNeed('drillPositions', { ...quiet, due: 20 }));
  });

  it('turns to Drill positions once Survival has had a round and cards are piling up', () => {
    const needs = { ...quiet, due: 12 };
    expect(chooseMode(needs, [])).toBe('survival');
    expect(chooseMode(needs, ['survival'])).toBe('drillPositions');
  });

  it('drills freshly grown lines before Survival', () => {
    expect(chooseMode({ ...quiet, unpracticed: 4 }, ['growth'])).toBe('drillLines');
  });

  it('never runs one mode more than MAX_RUN rounds while another has work', () => {
    const needs = { ...quiet, due: 40, unpracticed: 40 };
    const recent = Array<RoundMode>(MAX_RUN).fill('drillLines');
    const ranked = rankModes(needs, recent);
    expect(ranked[0].mode).not.toBe('drillLines');
    expect(ranked.find((s) => s.mode === 'drillLines')?.score).toBe(0);
  });

  it('settles into a mix rather than one mode, over a session', () => {
    const needs = { due: 20, unpracticed: 3, growReady: true };
    const played: RoundMode[] = [];
    for (let i = 0; i < 12; i += 1) played.push(chooseMode(needs, played));
    expect(new Set(played).size).toBe(4);
    expect(played.filter((m) => m === 'survival').length).toBeGreaterThanOrEqual(3);
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
