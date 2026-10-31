/**
 * The constants half of the spec: every UPPER_CASE value exported from
 * src/model that is plain data, by module. Written to spec/constants.json by
 * `npm run spec:constants`; a unit test fails when the file is out of date.
 */

/** Plain data only: finite numbers, strings, booleans, and arrays or objects of them. */
function plain(value: unknown): boolean {
  if (value === null || typeof value === 'string' || typeof value === 'boolean') return true;
  if (typeof value === 'number') return Number.isFinite(value);
  if (Array.isArray(value)) return value.every(plain);
  if (typeof value === 'object') {
    const proto = Object.getPrototypeOf(value);
    return (proto === Object.prototype || proto === null) && Object.values(value as object).every(plain);
  }
  return false;
}

/** Modules by repo-relative path, as `import.meta.glob` or a script loads them. */
export function collectConstants(mods: Record<string, Record<string, unknown>>): Record<string, Record<string, unknown>> {
  const out: Record<string, Record<string, unknown>> = {};
  for (const path of Object.keys(mods).sort()) {
    if (path.endsWith('.test.ts') || path.includes('/seed/')) continue;
    const mod = mods[path];
    const found: Record<string, unknown> = {};
    for (const name of Object.keys(mod).sort()) {
      if (/^[A-Z][A-Z0-9_]*$/.test(name) && plain(mod[name])) found[name] = mod[name];
    }
    if (Object.keys(found).length) out[path] = found;
  }
  return out;
}

export const constantsText = (mods: Record<string, Record<string, unknown>>) =>
  JSON.stringify(collectConstants(mods), null, 2) + '\n';
