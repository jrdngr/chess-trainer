import { describe, expect, it } from 'vitest';
import { walkSan } from '../chess/core';
import { arrowChoices, bookChoices, goals, shownStyles, stylePick } from './boardBuilder';
import { openingTree } from './openingTree';
import { referenceIndex } from './referenceIndex';
import { BOOK_SHARE } from './survival';

const index = referenceIndex();
const tree = openingTree(index);
const line = (text: string) => (text ? text.split(' ') : []);
const fenOf = (text: string) => walkSan(line(text)).fens.at(-1)!;
const GIUOCO = 'e4 e5 Nf3 Nc6 Bc4 Bc5';

describe('the moves the board offers', () => {
  it('are the book moves, most played first', () => {
    const choices = bookChoices(index, fenOf(''));
    expect(choices[0].san).toBe('e4');
    expect(choices.every((c) => c.share >= BOOK_SHARE)).toBe(true);
    expect(choices.map((c) => c.share)).toEqual([...choices.map((c) => c.share)].sort((a, b) => b - a));
  });

  it('draw three arrows, always with the highlighted move among them', () => {
    const choices = bookChoices(index, fenOf(GIUOCO));
    const last = choices[choices.length - 1].san;
    const arrows = arrowChoices(choices, last);
    expect(arrows).toHaveLength(3);
    expect(arrows.map((a) => a.san)).toContain(last);
  });
});

describe('styles', () => {
  it('highlights the most played move for Popular', () => {
    const choices = bookChoices(index, fenOf(GIUOCO));
    expect(stylePick(index, tree, line(GIUOCO), choices, 'popular')).toBe(choices[0].san);
  });

  it('finds the Evans Gambit for Gambit', () => {
    const choices = bookChoices(index, fenOf(GIUOCO));
    expect(stylePick(index, tree, line(GIUOCO), choices, 'gambit')).toBe('b4');
  });

  it('finds nothing to highlight where nothing fits', () => {
    expect(stylePick(index, tree, [], bookChoices(index, fenOf('')), 'gambit')).toBeNull();
  });

  it('shows only the styles that would change the highlight, and the one picked', () => {
    const picks = { popular: 'c3', solid: 'c3', attack: 'b4', gambit: 'b4', fianchetto: null };
    expect(shownStyles(picks, 'popular')).toEqual(['popular', 'attack', 'gambit']);
    expect(shownStyles(picks, 'solid')).toEqual(['popular', 'solid', 'attack', 'gambit']);
  });
});

describe('goals', () => {
  it('lists the minor pieces at home, castling and the center', () => {
    const g = goals(fenOf(GIUOCO), 'w');
    expect(g.map((x) => [x.label, x.value])).toEqual([
      ['Develop', 'Nb1 Bc1'],
      ['Castle', 'not yet'],
      ['Center', 'e4 vs e5'],
    ]);
  });

  it('says done once castled and developed', () => {
    const g = goals(fenOf('e4 e5 Nf3 Nc6 Bc4 Bc5 O-O Nf6 d3 d6 Nc3 O-O Bg5'), 'w');
    expect(g[0].value).toBe('done');
    expect(g[1].value).toBe('done');
  });
});
