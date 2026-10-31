import { describe, expect, it } from 'vitest';
import { caseText, type CaseFile } from './caseKit';

const defs = import.meta.glob<{ default: CaseFile }>('./cases/*.cases.ts', { eager: true });
const files = import.meta.glob<string>('../../spec/cases/functions/*.json', { eager: true, query: '?raw', import: 'default' });

describe('spec/cases/functions', () => {
  for (const [path, mod] of Object.entries(defs)) {
    const file = mod.default;
    it(`${file.area} matches the model, or run npm run spec:cases`, () => {
      const written = files[`../../spec/cases/functions/${file.area}.json`];
      expect(written, `${path} has no file yet`).toBeDefined();
      expect(caseText(file)).toBe(written);
    });
  }

  it('has no file without its definition', () => {
    const areas = Object.values(defs).map((mod) => mod.default.area);
    for (const path of Object.keys(files)) {
      expect(areas).toContain(path.split('/').pop()!.replace('.json', ''));
    }
  });
});
