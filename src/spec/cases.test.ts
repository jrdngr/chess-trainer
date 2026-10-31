import { describe, expect, it } from 'vitest';
import { caseText, type CaseFile } from './caseKit';
import { scenarioText, type ScenarioFile } from './scenarioKit';

const defs = import.meta.glob<{ default: CaseFile }>('./cases/*.cases.ts', { eager: true });
const files = import.meta.glob<string>('../../spec/cases/functions/*.json', { eager: true, query: '?raw', import: 'default' });
const scenarioDefs = import.meta.glob<{ default: ScenarioFile }>('./scenarios/*.scenarios.ts', { eager: true });
const scenarioFiles = import.meta.glob<string>('../../spec/cases/scenarios/*.json', {
  eager: true,
  query: '?raw',
  import: 'default',
});

function fresh<F extends { area: string }>(kind: string, defs: Record<string, { default: F }>, files: Record<string, string>, text: (file: F) => string) {
  describe(`spec/cases/${kind}`, () => {
    for (const [path, mod] of Object.entries(defs)) {
      const file = mod.default;
      it(`${file.area} matches the model, or run npm run spec:cases`, () => {
        const written = files[`../../spec/cases/${kind}/${file.area}.json`];
        expect(written, `${path} has no file yet`).toBeDefined();
        expect(text(file)).toBe(written);
      });
    }

    it('has no file without its definition', () => {
      const areas = Object.values(defs).map((mod) => mod.default.area);
      for (const path of Object.keys(files)) {
        expect(areas).toContain(path.split('/').pop()!.replace('.json', ''));
      }
    });
  });
}

fresh('functions', defs, files, caseText);
fresh('scenarios', scenarioDefs, scenarioFiles, scenarioText);
