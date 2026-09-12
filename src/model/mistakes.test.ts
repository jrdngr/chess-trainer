import { describe, expect, it } from 'vitest';
import { addMistake, MISTAKE_LIMIT, recentMistakes, sourceLabel, type Mistake } from './mistakes';

function slip(key: string, played = 'Nf3', source: Mistake['source'] = 'drill') {
  return { source, repertoireId: 'rep_w', key, fen: `${key} w - - 0 1`, played, expected: 'd4' };
}

describe('logging a mistake', () => {
  it('keeps one entry per position, with the latest move played', () => {
    let log: Mistake[] = [];
    log = addMistake(log, slip('a', 'Nf3'));
    log = addMistake(log, slip('a', 'c4'));
    expect(log).toHaveLength(1);
    expect(log[0].played).toBe('c4');
  });

  it('treats the same position in different repertoires as two mistakes', () => {
    let log: Mistake[] = [];
    log = addMistake(log, slip('a'));
    log = addMistake(log, { ...slip('a'), repertoireId: 'rep_b' });
    expect(log).toHaveLength(2);
  });

  it('stamps the time so the newest can be asked about first', () => {
    const log = addMistake([], slip('a'));
    expect(log[0].at).toBeGreaterThan(0);
    expect(log[0].id).toContain('rep_w');
  });

  it('forgets the oldest once the log is full', () => {
    let log: Mistake[] = [];
    for (let i = 0; i < MISTAKE_LIMIT + 25; i += 1) log = addMistake(log, slip(`k${i}`));
    expect(log).toHaveLength(MISTAKE_LIMIT);
    expect(log.some((m) => m.key === 'k0')).toBe(false);
    expect(log.some((m) => m.key === `k${MISTAKE_LIMIT + 24}`)).toBe(true);
  });
});

describe('reading the log back', () => {
  it('returns the newest first', () => {
    const log: Mistake[] = [
      { ...slip('a'), id: 'a', at: 10 },
      { ...slip('b'), id: 'b', at: 30 },
      { ...slip('c'), id: 'c', at: 20 },
    ];
    expect(recentMistakes(log).map((m) => m.id)).toEqual(['b', 'c', 'a']);
  });

  it('filters to one repertoire', () => {
    const log: Mistake[] = [
      { ...slip('a'), id: 'a', at: 1 },
      { ...slip('b'), id: 'b', at: 2, repertoireId: 'other' },
    ];
    expect(recentMistakes(log, 'other').map((m) => m.id)).toEqual(['b']);
  });

  it('does not mutate the log it was given', () => {
    const log: Mistake[] = [
      { ...slip('a'), id: 'a', at: 1 },
      { ...slip('b'), id: 'b', at: 2 },
    ];
    recentMistakes(log);
    expect(log.map((m) => m.id)).toEqual(['a', 'b']);
  });
});

describe('naming the source', () => {
  it('names each mode in words that fit "from …"', () => {
    expect(sourceLabel('play')).toBe('a game you played');
    expect(sourceLabel('openingRun')).toBe('an opening run');
    expect(sourceLabel('drill')).toBe('a drill');
  });
});
