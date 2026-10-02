import { describe, expect, it } from 'vitest';
import {
  DEFAULT_DRILL,
  DEFAULT_GROWTH,
  shareLabel,
} from './modes';

describe('mode defaults', () => {
  it('asks Growth for replies with a real following, not every oddity', () => {
    expect(DEFAULT_GROWTH.minShare).toBe(1);
    expect(DEFAULT_GROWTH.maxPly).toBe(18);
  });

  it('starts every mode unnarrowed', () => {
    expect(DEFAULT_DRILL.draw).toBe('due');
  });

  it('leaves the narrowing options off', () => {
    expect(DEFAULT_DRILL.weakFirst).toBe(false);
  });

});

describe('option labels', () => {
  it('says "anything" rather than a fraction of a percent', () => {
    expect(shareLabel(3)).toBe('3% and up');
    expect(shareLabel(0.2)).toBe('Anything played');
  });
});
