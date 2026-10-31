import { describe, expect, it } from 'vitest';
import { exists, knownFrom, rulesIn } from './coverage';
import constants from '../../spec/constants.json?raw';

const specs = import.meta.glob<string>('../../docs/spec/*.md', { eager: true, query: '?raw', import: 'default' });
const functions = import.meta.glob<string>('../../spec/cases/functions/*.json', { eager: true, query: '?raw', import: 'default' });
const scenarios = import.meta.glob<string>('../../spec/cases/scenarios/*.json', { eager: true, query: '?raw', import: 'default' });
const traces = Object.keys(import.meta.glob('../../e2e/traces/*-trace.txt', { query: '?raw' })).map((path) =>
  path.split('/').pop()!.replace('-trace.txt', ''),
);

const known = knownFrom(Object.values(functions), Object.values(scenarios), traces, constants);
const rules = Object.entries(specs).flatMap(([path, text]) => rulesIn(path.split('/').pop()!, text));

describe('docs/spec', () => {
  it('has rules', () => {
    expect(rules.length).toBeGreaterThan(0);
  });

  it('never uses a rule id twice', () => {
    const ids = rules.map((rule) => rule.id);
    expect(ids.filter((id, i) => ids.indexOf(id) !== i)).toEqual([]);
  });

  it('names only cases that exist', () => {
    const broken = rules.flatMap((rule) => rule.cases.filter((ref) => !exists(ref, known)).map((ref) => `${rule.id}: ${ref}`));
    expect(broken).toEqual([]);
  });
});
