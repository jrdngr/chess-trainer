/**
 * Writes spec/constants.json (see src/spec/constants.ts).
 *
 *   npm run spec:constants
 */
import { readdirSync, writeFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { collectConstants, constantsText } from '../src/spec/constants';

const ROOT = join(import.meta.dirname, '..');

function modules(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return modules(path);
    return entry.name.endsWith('.ts') ? [path] : [];
  });
}

const mods = {};
for (const path of modules(join(ROOT, 'src/model'))) {
  if (path.endsWith('.test.ts')) continue;
  mods[relative(ROOT, path).replace(/\\/g, '/')] = await import(path);
}
writeFileSync(join(ROOT, 'spec/constants.json'), constantsText(mods));
const out = collectConstants(mods);
const count = Object.values(out).reduce((n, m) => n + Object.keys(m).length, 0);
console.log(`wrote ${count} constants from ${Object.keys(out).length} modules to spec/constants.json`);
