import { describe, expect, it } from 'vitest';
import file from '../../spec/constants.json?raw';
import { constantsText } from './constants';

describe('spec/constants.json', () => {
  it('matches the model, or run npm run spec:constants', () => {
    const loaded = import.meta.glob<Record<string, unknown>>(['../model/**/*.ts', '!../model/**/*.test.ts'], { eager: true });
    const mods = Object.fromEntries(Object.entries(loaded).map(([path, mod]) => [path.replace('../', 'src/'), mod]));
    expect(constantsText(mods)).toBe(file);
  });
});
