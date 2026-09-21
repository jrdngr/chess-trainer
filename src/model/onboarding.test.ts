import { describe, expect, it } from 'vitest';
import { openingTree } from './openingTree';
import { referenceIndex } from './referenceIndex';
import { familyName } from './reference';
import { NAMED_LATE_IDS, picksFrom, playerOf, selectionFor } from './onboarding';
import { DEFAULT_SELECTION } from './selection';

const NAJDORF = 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6';
const SICILIAN = 'e4 c5';
const RUY = 'e4 e5 Nf3 Nc6 Bb5';
const FRENCH = 'e4 e6';
const LONDON = 'd4 Nf6 Nf3 g6 Bf4';
const KINGS_INDIAN = 'd4 Nf6 c4 g6 Nc3';
const SCOTCH = 'e4 e5 Nf3 Nc6 d4 exd4';

const tree = () => openingTree(referenceIndex());

describe('whose opening it is', () => {
  it('reads the side off the move that earned the name', () => {
    expect(playerOf(['e4'])).toBe('w');
    expect(playerOf(['e4', 'c5'])).toBe('b');
  });

  it('files each opening under the side that plays it', () => {
    const picks = picksFrom(tree(), [NAJDORF, RUY, FRENCH, LONDON, 'e4']);
    expect(picks.map((pick) => `${pick.name}:${pick.color}`)).toEqual([
      'Sicilian Defence: Najdorf Variation:b',
      'Ruy Lopez:w',
      'French Defence:b',
      'London System:w',
      "King's Pawn Game:w",
    ]);
  });

  it("files the King's Indian under Black, named a move late though it is", () => {
    // The book names it at 1.d4 Nf6 2.c4 g6 3.Nc3 — White's reply to the ...g6
    // that makes it a King's Indian — so the last ply says White and lies.
    const [pick] = picksFrom(tree(), [KINGS_INDIAN]);
    expect(pick.name).toBe("King's Indian Defence");
    expect(pick.color).toBe('b');
  });

  it('files the Scotch under White, for the same reason mirrored', () => {
    // Named at 1.e4 e5 2.Nf3 Nc6 3.d4 exd4, one ply past White's 3.d4.
    const [pick] = picksFrom(tree(), [SCOTCH]);
    expect(pick.name).toBe('Scotch Game');
    expect(pick.color).toBe('w');
  });

  it('puts every defence the book names on its own under Black', () => {
    // The guard the King's Indian needed: a family the book calls a Defence,
    // with no variation hanging off the name, is Black's whatever ply it lands
    // on. Names carrying a comma are excluded — "Vienna Gambit, with Max Lange
    // Defence" is the Vienna Gambit, and White's.
    const index = referenceIndex();
    const defences = [...tree().byId.values()].filter(
      (node) =>
        familyName(index, node.name) === node.name &&
        !node.name.includes(',') &&
        /\bDefen[cs]e$/.test(node.name),
    );
    expect(defences.length).toBeGreaterThan(30);
    expect(defences.filter((node) => playerOf(node.sans) !== 'b').map((node) => node.name)).toEqual(
      [],
    );
  });

  it('keeps the late-named corrections pointed at openings the book still has', () => {
    // A correction is keyed by move order. Should the book renumber one, the
    // key would stop matching and the opening would quietly go back to being
    // filed by its last ply.
    const { byId } = tree();
    expect(NAMED_LATE_IDS.filter((id) => !byId.has(id))).toEqual([]);
  });

  it('gives White the lines White chooses inside a Black opening', () => {
    // 6.Be3 against the Najdorf is White's decision, not Black's, and the
    // name attaches on White's move — so it belongs in the White tree.
    const [pick] = picksFrom(tree(), [`${NAJDORF} Be3`]);
    expect(pick.name).toBe('Sicilian Defence: Najdorf Variation, English Attack');
    expect(pick.color).toBe('w');
  });
});

describe('what a pick is worth', () => {
  it('takes the opening’s own move order and not a move more', () => {
    const [pick] = picksFrom(tree(), [NAJDORF]);
    expect(pick.sans).toEqual(NAJDORF.split(' '));
  });

  it('ignores the root: "any opening" is not an opening anyone plays', () => {
    expect(picksFrom(tree(), [''])).toEqual([]);
  });

  it('drops ids the book does not know, and keeps the rest', () => {
    const picks = picksFrom(tree(), ['not an opening', RUY]);
    expect(picks.map((pick) => pick.id)).toEqual([RUY]);
  });

  it('counts an opening picked twice once', () => {
    expect(picksFrom(tree(), [RUY, RUY])).toHaveLength(1);
  });
});

describe('the selection the picks imply', () => {
  it('names the opening when there is only one', () => {
    expect(selectionFor(picksFrom(tree(), [NAJDORF]))).toEqual({ color: 'b', opening: NAJDORF });
  });

  it('keeps the side, but not the opening, when several share one', () => {
    expect(selectionFor(picksFrom(tree(), [NAJDORF, FRENCH]))).toEqual({ color: 'b', opening: '' });
  });

  it('goes random when the picks span both sides', () => {
    const selection = selectionFor(picksFrom(tree(), [NAJDORF, RUY]));
    expect(selection).toEqual({ color: 'random', opening: '' });
  });

  it('says nothing when nothing was picked', () => {
    expect(selectionFor([])).toEqual(DEFAULT_SELECTION);
  });

  it('treats a family and a variation of it as two picks, not one', () => {
    expect(selectionFor(picksFrom(tree(), [SICILIAN, NAJDORF]))).toEqual({
      color: 'b',
      opening: '',
    });
  });
});
