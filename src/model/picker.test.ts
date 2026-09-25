import { describe, expect, it } from 'vitest';
import { applySan, START_FEN } from '../chess/core';
import { buildBookIndex } from './book';
import { openingTree } from './openingTree';
import { nameLevels, pickerCatalog, sideForPick, sortEntries } from './picker';
import { BRANCH_SIDES, FAMILY_GROUPS, FAMILY_SHARPNESS, SHARPNESS_OVERRIDES } from './pickerData';

const tree = openingTree(buildBookIndex());
const catalog = pickerCatalog(tree);
const entry = (key: string) => {
  const found = catalog.byKey.get(key);
  if (!found) throw new Error(`No entry ${key}`);
  return found;
};
const groupOfBranch = (family: string, branch: string) =>
  catalog.familyByName.get(family)!.groups!.find((group) => group.entries.some((e) => e.key === branch))!;

describe('nameLevels', () => {
  it('splits a name into family, branch and lines', () => {
    expect(nameLevels('Sicilian Defence', 'Sicilian Defence: Najdorf Variation, English Attack')).toEqual([
      'Sicilian Defence',
      'Sicilian Defence: Najdorf Variation',
      'Sicilian Defence: Najdorf Variation, English Attack',
    ]);
  });

  it('keeps a family with a comma in its name whole', () => {
    expect(nameLevels('Vienna Gambit, with Max Lange Defence', 'Vienna Gambit, with Max Lange Defence')).toEqual([
      'Vienna Gambit, with Max Lange Defence',
    ]);
  });
});

describe('hand-written data', () => {
  it('names only families, lines and move orders the book has', () => {
    for (const family of Object.keys(FAMILY_SHARPNESS)) expect(catalog.familyByName.has(family), family).toBe(true);
    for (const key of Object.keys(SHARPNESS_OVERRIDES)) expect(catalog.byKey.has(key), key).toBe(true);
    for (const key of Object.keys(BRANCH_SIDES)) expect(catalog.byKey.has(key), key).toBe(true);
    for (const [family, split] of Object.entries(FAMILY_GROUPS)) {
      expect(catalog.familyByName.has(family), family).toBe(true);
      for (const group of split.groups) {
        for (const line of group.from) {
          let fen: string | null = START_FEN;
          for (const san of line.split(' ')) fen = fen ? (applySan(fen, san)?.after ?? null) : null;
          expect(fen, `${family}: ${line}`).not.toBeNull();
        }
      }
    }
  });

  it('rates every family the book has', () => {
    for (const family of catalog.families) expect(FAMILY_SHARPNESS, family.entry.key).toHaveProperty([family.entry.key]);
  });
});

describe('catalogue', () => {
  it('nests lines under their branch and family', () => {
    const line = entry('Sicilian Defence: Najdorf Variation, English Attack');
    expect(line.parent?.key).toBe('Sicilian Defence: Najdorf Variation');
    expect(line.parent?.parent?.key).toBe('Sicilian Defence');
    expect(line.level).toBe(2);
  });

  it('files first moves into their sections', () => {
    expect(catalog.familyByName.get('Sicilian Defence')!.firstMove).toBe('e4');
    expect(catalog.familyByName.get("King's Indian Defence")!.firstMove).toBe('d4');
    expect(catalog.familyByName.get('English Opening')!.firstMove).toBe('flank');
  });

  it('gives every entry a sharpness and difficulty from 1 to 5', () => {
    for (const e of catalog.byKey.values()) {
      expect(e.sharpness).toBeGreaterThanOrEqual(1);
      expect(e.sharpness).toBeLessThanOrEqual(5);
      expect(e.difficulty).toBeGreaterThanOrEqual(1);
      expect(e.difficulty).toBeLessThanOrEqual(5);
    }
  });

  it('carries an override down into the lines under it', () => {
    expect(entry('Ruy Lopez: Berlin Defence').sharpness).toBe(1);
    expect(entry('Ruy Lopez: Marshall Attack').sharpness).toBe(5);
    expect(entry('Sicilian Defence: Najdorf Variation, English Attack').sharpness).toBe(5);
  });
});

describe('groups', () => {
  it('puts a branch in the deepest group its move order passes', () => {
    expect(groupOfBranch('Sicilian Defence', 'Sicilian Defence: Najdorf Variation').label).toBe('Open Sicilian');
    expect(groupOfBranch('Sicilian Defence', 'Sicilian Defence: Nyezhmetdinov-Rossolimo Attack').label).toBe('2.Nf3 sidelines');
  });

  it('notes a transposition from another group', () => {
    const open = groupOfBranch('Sicilian Defence', 'Sicilian Defence: Najdorf Variation');
    expect(open.alsoVia.get('Sicilian Defence: Najdorf Variation')).toContain('Closed and Grand Prix');
  });

  it('leaves out a group that leads into this one wholesale', () => {
    const open = groupOfBranch('Sicilian Defence', 'Sicilian Defence: Najdorf Variation');
    // 2.d4 cxd4 3.Nf3 reaches every Open Sicilian; saying so on every row says nothing.
    expect(open.alsoVia.get('Sicilian Defence: Najdorf Variation')).not.toContain('Smith-Morra Gambit');
  });

  it('folds a group of one into the rest', () => {
    const labels = catalog.familyByName.get('Sicilian Defence')!.groups!.map((group) => group.label);
    expect(labels).not.toContain('Alapin');
    expect(labels[labels.length - 1]).toBe('Other second moves');
  });
});

describe('sides', () => {
  it('sets the side of the opening a pick names', () => {
    expect(sideForPick(catalog, entry('Sicilian Defence').node)).toBe('b');
    expect(sideForPick(catalog, entry('Sicilian Defence: Alapin Variation').node)).toBe('w');
    expect(sideForPick(catalog, entry('Ruy Lopez').node)).toBe('w');
  });

  it('plays a line from its branch side', () => {
    expect(sideForPick(catalog, entry('Sicilian Defence: Najdorf Variation, English Attack').node)).toBe('b');
  });

  it('corrects a branch the book names a move late', () => {
    expect(entry('Sicilian Defence: Taimanov Variation').side).toBe('b');
  });

  it('leaves the side alone for any opening', () => {
    expect(sideForPick(catalog, tree.root)).toBeNull();
  });
});

describe('sortEntries', () => {
  const branches = entry('Sicilian Defence').children;

  it('puts starred first whatever the sort', () => {
    const najdorf = entry('Sicilian Defence: Najdorf Variation');
    const sorted = sortEntries(branches, 'calmest', [najdorf.node.id]);
    expect(sorted[0]).toBe(najdorf);
  });

  it('orders by sharpness and difficulty', () => {
    const sharp = sortEntries(branches, 'sharpest', []);
    expect(sharp[0].sharpness).toBe(5);
    const easy = sortEntries(branches, 'easiest', []);
    expect(easy[0].difficulty).toBeLessThanOrEqual(easy[easy.length - 1].difficulty);
  });
});
