/**
 * The spec's rules and what covers them: reads `docs/spec/*.md` (see its
 * README for the rule format) and checks each rule's cases against what the
 * generators wrote. Used by the coverage report and by a test that fails when
 * a rule names a case that does not exist.
 */

export type Status = "port" | "drop" | "change";

export interface Rule {
  id: string;
  status: Status;
  file: string;
  /** What the rule names in its Cases line, as written. */
  cases: string[];
}

/** What exists to be named: function case sets, scenarios, e2e traces and constants. */
export interface Known {
  functions: Set<string>;
  scenarios: Set<string>;
  traces: Set<string>;
  constants: Set<string>;
}

const HEAD = /^\*\*([A-Z]+-\d+)\*\* · (port|drop|change)\b/;

/** Every rule in one spec file. */
export function rulesIn(file: string, text: string): Rule[] {
  const rules: Rule[] = [];
  let current: Rule | null = null;
  let fenced = false;
  for (const line of text.split("\n")) {
    // An example in a code block is not a rule.
    if (line.startsWith("```")) fenced = !fenced;
    if (fenced) continue;
    const head = HEAD.exec(line);
    if (head) {
      current = { id: head[1], status: head[2] as Status, file, cases: [] };
      rules.push(current);
      continue;
    }
    if (!line.trim()) current = null;
    else if (current && line.startsWith("Cases:")) {
      current.cases.push(...[...line.matchAll(/`([^`]+)`/g)].map((m) => m[1]));
    }
  }
  return rules;
}

/** Whether a case reference names something that exists. */
export function exists(ref: string, known: Known): boolean {
  if (ref.startsWith("e2e:")) return known.traces.has(ref.slice(4));
  if (ref.startsWith("const:")) return known.constants.has(ref.slice(6));
  if (ref.includes("/")) return known.scenarios.has(ref);
  return known.functions.has(ref);
}

/** Function case sets and scenarios by name, from the generated files' text. */
export function knownFrom(
  functionFiles: string[],
  scenarioFiles: string[],
  traceNames: string[],
  constantsText: string,
): Known {
  const functions = new Set<string>();
  for (const text of functionFiles)
    for (const fn of JSON.parse(text).functions) functions.add(fn.fn);
  const scenarios = new Set<string>();
  for (const text of scenarioFiles) {
    const file = JSON.parse(text);
    for (const s of file.scenarios) scenarios.add(`${file.area}/${s.name}`);
  }
  const constants = new Set<string>();
  for (const names of Object.values(
    JSON.parse(constantsText) as Record<string, Record<string, unknown>>,
  )) {
    for (const name of Object.keys(names)) constants.add(name);
  }
  return { functions, scenarios, traces: new Set(traceNames), constants };
}

/** The report: every rule's coverage, and the gaps. */
export function coverageText(rules: Rule[], known: Known): string {
  const ported = rules.filter((r) => r.status === "port");
  const gaps = ported.filter((r) => !r.cases.length);
  const broken = rules.flatMap((r) =>
    r.cases.filter((c) => !exists(c, known)).map((c) => `${r.id}: ${c}`),
  );
  const byFile = new Map<string, Rule[]>();
  for (const rule of rules)
    byFile.set(rule.file, [...(byFile.get(rule.file) ?? []), rule]);
  const lines = [...byFile].map(([file, list]) => {
    const port = list.filter((r) => r.status === "port");
    const covered = port.filter((r) => r.cases.length).length;
    return `${file}: ${covered} of ${port.length} port rules covered`;
  });
  const pct = ported.length
    ? Math.round((100 * (ported.length - gaps.length)) / ported.length)
    : 100;
  return [
    ...lines,
    `${rules.length} rules, ${ported.length} to port, ${pct}% covered`,
    ...(gaps.length
      ? ["", "Rules with no case:", ...gaps.map((r) => `  ${r.id} (${r.file})`)]
      : []),
    ...(broken.length
      ? ["", "Cases that do not exist:", ...broken.map((b) => `  ${b}`)]
      : []),
  ].join("\n");
}
