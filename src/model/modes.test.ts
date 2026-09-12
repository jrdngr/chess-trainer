import { describe, expect, it } from 'vitest';
import {
  DEFAULT_DRILL,
  DEFAULT_GAP,
  DEFAULT_PUNISH,
  EMPTY_PUNISH_RECORD,
  depthLabel,
  gainLabel,
  normalizePunishRecord,
  recordPunish,
  shareLabel,
} from './modes';

describe('mode defaults', () => {
  it('starts every mode unnarrowed', () => {
    expect(DEFAULT_DRILL.repertoireId).toBe('');
    expect(DEFAULT_PUNISH.repertoireId).toBe('');
    expect(DEFAULT_GAP.repertoireId).toBe('');
    expect(DEFAULT_DRILL.side).toBe('both');
  });

  it('leaves the harder options off', () => {
    expect(DEFAULT_DRILL.weakFirst).toBe(false);
    expect(DEFAULT_PUNISH.timed).toBe(false);
    expect(DEFAULT_PUNISH.announce).toBe(true);
    expect(DEFAULT_GAP.quickFix).toBe(false);
  });
});

describe('the Punish record', () => {
  it('counts what was seen and what was sprung', () => {
    let record = EMPTY_PUNISH_RECORD;
    record = recordPunish(record, true);
    record = recordPunish(record, false);
    expect(record).toMatchObject({ seen: 2, solved: 1 });
  });

  it('keeps the best streak after it breaks', () => {
    let record = EMPTY_PUNISH_RECORD;
    for (const solved of [true, true, true, false, true]) record = recordPunish(record, solved);
    expect(record.best).toBe(3);
    expect(record.streak).toBe(1);
  });

  it('never counts a miss toward the streak', () => {
    const record = recordPunish({ seen: 4, solved: 4, best: 4, streak: 4 }, false);
    expect(record.streak).toBe(0);
    expect(record.best).toBe(4);
  });

  it('fills in a record saved before it had every field', () => {
    expect(normalizePunishRecord({ seen: 3, solved: 2 })).toEqual({
      seen: 3,
      solved: 2,
      best: 0,
      streak: 0,
    });
    expect(normalizePunishRecord(undefined)).toEqual(EMPTY_PUNISH_RECORD);
  });
});

describe('option labels', () => {
  it('names each material threshold', () => {
    expect(gainLabel(2)).toMatch(/material/i);
    expect(gainLabel(3)).toMatch(/piece/i);
    expect(gainLabel(5)).toMatch(/rook/i);
  });

  it('counts depth in moves, not plies', () => {
    expect(depthLabel(8)).toBe('4 moves');
    expect(depthLabel(16)).toBe('8 moves');
  });

  it('says "anything" rather than a fraction of a percent', () => {
    expect(shareLabel(3)).toBe('3% and up');
    expect(shareLabel(0.2)).toBe('Anything played');
  });
});
