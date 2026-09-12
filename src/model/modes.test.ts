import { describe, expect, it } from 'vitest';
import {
  DEFAULT_DRILL,
  DEFAULT_GAP,
  DEFAULT_REPAIR,
  EMPTY_REPAIR_RECORD,
  gamesLabel,
  kindLabel,
  normalizeRepairRecord,
  recordRepair,
  shareLabel,
} from './modes';

describe('mode defaults', () => {
  it('starts every mode unnarrowed', () => {
    expect(DEFAULT_DRILL.repertoireId).toBe('');
    expect(DEFAULT_REPAIR.repertoireId).toBe('');
    expect(DEFAULT_GAP.repertoireId).toBe('');
    expect(DEFAULT_DRILL.side).toBe('both');
    expect(DEFAULT_REPAIR.kinds).toBe('both');
  });

  it('leaves the narrowing options off', () => {
    expect(DEFAULT_DRILL.weakFirst).toBe(false);
    expect(DEFAULT_REPAIR.lossesOnly).toBe(false);
    expect(DEFAULT_GAP.quickFix).toBe(false);
  });

  it('asks for a position to have come up more than once', () => {
    expect(DEFAULT_REPAIR.minGames).toBe(2);
  });
});

describe('the Repair record', () => {
  it('counts the two kinds of repair separately', () => {
    let record = EMPTY_REPAIR_RECORD;
    record = recordRepair(record, { relearned: true });
    record = recordRepair(record, { added: true });
    record = recordRepair(record, {});
    expect(record).toEqual({ seen: 3, relearned: 1, added: 1 });
  });

  it('counts a wrong answer as seen but not relearned', () => {
    const record = recordRepair(EMPTY_REPAIR_RECORD, { relearned: false });
    expect(record).toEqual({ seen: 1, relearned: 0, added: 0 });
  });

  it('fills in a record saved before it had every field', () => {
    expect(normalizeRepairRecord({ seen: 4 })).toEqual({ seen: 4, relearned: 0, added: 0 });
    expect(normalizeRepairRecord(undefined)).toEqual(EMPTY_REPAIR_RECORD);
  });
});

describe('option labels', () => {
  it('names the two things that can be wrong', () => {
    expect(kindLabel('offprep')).toBe('Off prep');
    expect(kindLabel('unprepared')).toBe('Unprepared');
  });

  it('says "any game" rather than "1+ games"', () => {
    expect(gamesLabel(1)).toBe('Any game');
    expect(gamesLabel(3)).toBe('3+ games');
  });

  it('says "anything" rather than a fraction of a percent', () => {
    expect(shareLabel(3)).toBe('3% and up');
    expect(shareLabel(0.2)).toBe('Anything played');
  });
});
