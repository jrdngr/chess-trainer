/**
 * Which spec rules have cases, and which do not.
 *
 *   npm run spec:coverage
 */
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { coverageText, knownFrom, rulesIn } from '../src/spec/coverage';

const ROOT = join(import.meta.dirname, '..');
const read = (dir, suffix) =>
  readdirSync(join(ROOT, dir))
    .filter((name) => name.endsWith(suffix))
    .sort()
    .map((name) => ({ name, text: readFileSync(join(ROOT, dir, name), 'utf8') }));

const known = knownFrom(
  read('../spec/cases/functions', '.json').map((f) => f.text),
  read('../spec/cases/scenarios', '.json').map((f) => f.text),
  read('e2e/traces', '-trace.txt').map((f) => f.name.replace('-trace.txt', '')),
  readFileSync(join(ROOT, '../spec/constants.json'), 'utf8'),
);
const rules = read('../docs/spec', '.md').flatMap((f) => rulesIn(f.name, f.text));
console.log(coverageText(rules, known));
