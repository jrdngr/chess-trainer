import { beforeEach, describe, expect, it } from 'vitest';
import { ANY_FAVORITE } from '../model/anyFavorite';
import { DEFAULT_SELECTION } from '../model/selection';
import { countNodes } from '../model/repertoire';
import { seedFor, setSeed, starterSet } from '../model/starterSets';
import type { Repertoire } from '../model/types';
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
const seed = (line: string) => seedFor(line.split(' '));
const repFor = (color: 'w' | 'b') => repertoireList(state()).find((rep) => rep.color === color);

describe('the opening question', () => {
  it('is asked of a fresh profile', () => {
    expect(needsOnboarding(state())).toBe(true);
  });

  it('is not asked again once answered', () => {
    state().finishOnboarding([seed(NAJDORF)]);
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
    state().finishOnboarding([seed(NAJDORF), seed(RUY)]);
    expect(state().settings.favoriteOpenings).toEqual([NAJDORF, RUY]);
  });

  it('builds one tree per side, named for the side', () => {
    state().finishOnboarding([seed(NAJDORF), seed(RUY)]);
    expect(repertoireList(state()).map((rep) => rep.color).sort()).toEqual(['b', 'w']);
    expect(repFor('b')!.name).toContain('Black');
  });

  it('adds the opening and a few of your moves past it', () => {
    state().finishOnboarding([seed(NAJDORF)]);
    const black = repFor('b')!;
    expect(lineIn(black, NAJDORF)).toBe(true);
    expect(countNodes(black)).toBeGreaterThan(10);
    expect(repFor('w')).toBeUndefined();
  });

  it('gives each of your positions one answer', () => {
    state().finishOnboarding([seed(SICILIAN), seed(NAJDORF)]);
    const black = repFor('b')!;
    for (const node of Object.values(black.nodes)) {
      if (node.children.length === 0) continue;
      const replyColor = black.nodes[node.children[0]].fenBefore.split(' ')[1];
      if (replyColor === 'b') expect(node.children).toHaveLength(1);
    }
  });

  it('points the selection at a single pick', () => {
    state().finishOnboarding([seed(NAJDORF)]);
    expect(state().settings.selection).toEqual({ color: 'b', opening: NAJDORF });
  });

  it('keeps the side when the picks agree on one', () => {
    state().finishOnboarding([seed(NAJDORF), seed('e4 e6')]);
    expect(state().settings.selection).toEqual({ color: 'b', opening: ANY_FAVORITE });
  });

  it('ignores an opening the book does not know', () => {
    state().finishOnboarding([{ sans: ['not', 'an', 'opening'], color: 'w' }]);
    expect(state().repertoireOrder).toHaveLength(0);
    expect(state().settings.favoriteOpenings).toHaveLength(0);
    expect(state().settings.onboarded).toBe(true);
  });

  it('adds to a side that already has a tree rather than making a second one', () => {
    const existing = state().addRepertoire('Black', 'b');
    state().addLine(existing, ['e4', 'e5'], 'manual');
    state().finishOnboarding([seed(NAJDORF)]);
    expect(repertoireList(state()).filter((rep) => rep.color === 'b')).toHaveLength(1);
    expect(lineIn(state().repertoires[existing], NAJDORF)).toBe(true);
  });

  it('builds a whole starter set', () => {
    const set = starterSet('solid')!;
    state().finishOnboarding(setSeed(set), set.plays);
    expect(repertoireList(state()).map((rep) => rep.color).sort()).toEqual(['b', 'w']);
    // The Berlin, not the book's 3...a6, against the Ruy Lopez.
    expect(lineIn(repFor('b')!, 'e4 e5 Nf3 Nc6 Bb5 Nf6')).toBe(true);
    expect(lineIn(repFor('b')!, 'e4 e5 Nf3 Nc6 Bb5 a6')).toBe(false);
  });
});

/** Whether a move order is in a tree from its root. */
function lineIn(rep: Repertoire, line: string): boolean {
  let children = rep.rootChildren;
  for (const san of line.split(' ')) {
    const next = children.map((id) => rep.nodes[id]).find((node) => node.san === san);
    if (!next) return false;
    children = next.children;
  }
  return true;
}

describe('a Playbook played on the board', () => {
  it('stars what was played without adding a move to it', () => {
    const repId = state().ensureRepertoire('w');
    state().addLine(repId, RUY.split(' '), 'board');
    const before = countNodes(state().repertoires[repId]);
    state().finishOnboarding([seed(RUY)], [], { seed: false });
    expect(countNodes(state().repertoires[repId])).toBe(before);
    expect(state().settings.favoriteOpenings).toContain(RUY);
    expect(needsOnboarding(state())).toBe(false);
  });

  it('adds a picked opening as exactly its own moves', () => {
    state().finishOnboarding([seed('d4 d5 c4')], [], { seed: false });
    const rep = Object.values(state().repertoires).find((r) => r.color === 'w')!;
    expect(countNodes(rep)).toBe(3);
    expect(state().settings.favoriteOpenings).toContain('d4 d5 c4');
  });

  it('keeps what the engine said of a saved move', () => {
    const repId = state().ensureRepertoire('w');
    state().addLine(repId, ['e4', 'e5', 'Qh5'], 'board', undefined, [undefined, undefined, 120]);
    const queen = Object.values(state().repertoires[repId].nodes).find((node) => node.san === 'Qh5');
    expect(queen?.lost).toBe(120);
  });
});
