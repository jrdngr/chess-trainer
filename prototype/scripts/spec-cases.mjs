/**
 * Writes spec/cases/functions/<area>.json from src/spec/cases/*.cases.ts, and
 * spec/cases/scenarios/<area>.json from src/spec/scenarios/*.scenarios.ts.
 *
 *   npm run spec:cases
 */
import { mkdirSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { caseText } from '../src/spec/caseKit';
import { scenarioText } from '../src/spec/scenarioKit';

const ROOT = join(import.meta.dirname, '..');

async function write(defs, suffix, out, text, count) {
  mkdirSync(out, { recursive: true });
  let total = 0;
  for (const name of readdirSync(defs).filter((n) => n.endsWith(suffix)).sort()) {
    const file = (await import(join(defs, name))).default;
    writeFileSync(join(out, `${file.area}.json`), text(file));
    total += count(file);
    console.log(`${file.area}: ${count(file)}`);
  }
  return total;
}

const cases = await write(
  join(ROOT, 'src/spec/cases'),
  '.cases.ts',
  join(ROOT, '../spec/cases/functions'),
  caseText,
  (file) => file.functions.reduce((n, fn) => n + fn.cases.length, 0),
);
console.log(`${cases} function cases`);
const steps = await write(
  join(ROOT, 'src/spec/scenarios'),
  '.scenarios.ts',
  join(ROOT, '../spec/cases/scenarios'),
  scenarioText,
  (file) => file.scenarios.reduce((n, s) => n + s.steps.length, 0),
);
console.log(`${steps} scenario steps`);
