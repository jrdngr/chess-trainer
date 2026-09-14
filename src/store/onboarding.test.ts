import { beforeEach, describe, expect, it } from 'vitest';
import { DEFAULT_SELECTION } from '../model/selection';
import { countNodes } from '../model/repertoire';
import { DEFAULT_SETTINGS, needsOnboarding, repertoireList, useStore } from './useStore';

const NAJDORF = 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6';
const SICILIAN = 'e4 c5';
const RUY = 'e4 e5 Nf3 Nc6 Bb5';

/** A profile as it comes out of a fresh install, or a full reset. */
beforeEach(() => {
  useStore.setState({
    ready: true,
    repertoires: {},
    repertoireOrder: [],
    cards: {},
    log: [],
    importedGames: [],
    mistakes: [],
    settings: { ...DEFAULT_SETTINGS, favoriteOpenings: [], selection: { ...DEFAULT_SELECTION } },
  });
});

const state = () => useStore.getState();
const repFor = (color: 'w' | 'b') => repertoireList(state()).find((rep) => rep.color === color);

describe('the opening question', () => {
  it('is asked of a fresh profile', () => {
    expect(needsOnboarding(state())).toBe(true);
  });

  it('is not asked again once answered', () => {
    state().finishOnboarding([NAJDORF]);
    expect(needsOnboarding(state())).toBe(false);
  });

  it('is not asked again when waved away, and nothing is built', () => {
    state().finishOnboarding([]);
    expect(needsOnboarding(state())).toBe(false);
    expect(state().repertoireOrder).toHaveLength(0);
    expect(state().settings.selection).toEqual(DEFAULT_SELECTION);
  });

  it('is not asked of a profile that already has prep in it', () => {
    state().addRepertoire('Imported from another device', 'w');
    expect(needsOnboarding(state())).toBe(false);
  });
});

describe('answering it', () => {
  it('stars every pick', () => {
    state().finishOnboarding([NAJDORF, RUY]);
    expect(state().settings.favoriteOpenings).toEqual([NAJDORF, RUY]);
  });

  it('builds one tree per side, named for the side', () => {
    state().finishOnboarding([NAJDORF, RUY]);
    expect(repertoireList(state()).map((rep) => rep.color).sort()).toEqual(['b', 'w']);
    expect(repFor('b')!.name).toContain('Black');
  });

  it('adds the opening’s own move order and nothing else', () => {
    state().finishOnboarding([NAJDORF]);
    expect(countNodes(repFor('b')!)).toBe(10);
    expect(repFor('w')).toBeUndefined();
  });

  it('shares the moves two picks have in common', () => {
    state().finishOnboarding([SICILIAN, NAJDORF]);
    // 1.e4 c5 is the first two moves of the Najdorf, not two more.
    expect(countNodes(repFor('b')!)).toBe(10);
  });

  it('leaves the player somewhere to answer from', () => {
    state().finishOnboarding([NAJDORF]);
    const black = repFor('b')!;
    // The line ends on Black's move, so the last thing in it is an answer of
    // the player's own — a position Drill can ask about.
    const last = Object.values(black.nodes).find((node) => node.children.length === 0)!;
    expect(last.san).toBe('a6');
  });

  it('points the selection at a single pick', () => {
    state().finishOnboarding([NAJDORF]);
    expect(state().settings.selection).toEqual({ color: 'b', opening: NAJDORF });
  });

  it('keeps the side when the picks agree on one', () => {
    state().finishOnboarding([NAJDORF, 'e4 e6']);
    expect(state().settings.selection).toEqual({ color: 'b', opening: '' });
  });

  it('ignores an opening the book does not know', () => {
    state().finishOnboarding(['not an opening']);
    expect(state().repertoireOrder).toHaveLength(0);
    expect(state().settings.favoriteOpenings).toHaveLength(0);
    expect(state().settings.onboarded).toBe(true);
  });

  it('adds to a side that already has a tree rather than making a second one', () => {
    const existing = state().addRepertoire('Black', 'b');
    state().addLine(existing, ['e4', 'e5'], 'manual');
    state().finishOnboarding([NAJDORF]);
    expect(repertoireList(state()).filter((rep) => rep.color === 'b')).toHaveLength(1);
    // 1.e4 is already there, so the Najdorf costs nine moves rather than ten.
    expect(countNodes(state().repertoires[existing])).toBe(11);
  });
});
