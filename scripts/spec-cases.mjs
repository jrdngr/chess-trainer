/**
 * Writes spec/cases/functions/<area>.json from src/spec/cases/*.cases.ts.
 *
 *   npm run spec:cases
 */
import { mkdirSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { caseText } from '../src/spec/caseKit';

const ROOT = join(import.meta.dirname, '..');
const DEFS = join(ROOT, 'src/spec/cases');
const OUT = join(ROOT, 'spec/cases/functions');
mkdirSync(OUT, { recursive: true });

let total = 0;
for (const name of readdirSync(DEFS).filter((n) => n.endsWith('.cases.ts')).sort()) {
  const file = (await import(join(DEFS, name))).default;
  writeFileSync(join(OUT, `${file.area}.json`), caseText(file));
  const count = file.functions.reduce((n, fn) => n + fn.cases.length, 0);
  total += count;
  console.log(`${file.area}: ${file.functions.length} functions, ${count} cases`);
}
console.log(`${total} cases`);
