/**
 * Golden function cases: inputs are chosen here, in code, and the expected
 * outputs are always what the prototype's own functions return. Never edit a
 * file under spec/cases by hand: change the inputs here, or the model, and
 * run `npm run spec:cases`.
 *
 * Each `*.cases.ts` file in src/spec/cases default-exports a `CaseFile`. Every
 * case is `{ args, out }`: the arguments the function was called with, and
 * what it returned, as JSON. The native app's tests load the same files and
 * call its own functions with the same arguments.
 */

export interface FunctionCases {
  /** The function's name in the prototype, `module.function`. */
  fn: string;
  /** What the cases are for, in a line. */
  about: string;
  cases: { args: unknown[]; out: unknown }[];
}

export interface CaseFile {
  /** The spec area these belong to, which names the output file. */
  area: string;
  functions: FunctionCases[];
}

/** Record a function's answer for each set of arguments. */
export function cases<A extends unknown[], R>(
  fn: string,
  about: string,
  call: (...args: A) => R,
  inputs: A[],
): FunctionCases {
  return { fn, about, cases: inputs.map((args) => ({ args, out: json(call(...args)) })) };
}

/**
 * Undefined becomes null, -0 becomes 0, and the numbers JSON has no word for
 * become the strings "Infinity", "-Infinity" and "NaN", so the file reads the
 * same in any language.
 */
export function json(value: unknown): unknown {
  return JSON.parse(JSON.stringify(value === undefined ? null : value, (_key, v) => {
    if (typeof v !== 'number') return v;
    if (Object.is(v, -0)) return 0;
    return Number.isFinite(v) ? v : String(v);
  }));
}

/** Numbers from `from` to `to` by `step`, rounded to the step's decimals. */
export function range(from: number, to: number, step = 1): number[] {
  const decimals = (String(step).split('.')[1] ?? '').length;
  const out: number[] = [];
  for (let x = from; x <= to + step / 2; x += step) out.push(Number(x.toFixed(decimals)));
  return out;
}

/** Every combination of the given lists, as argument tuples. */
export function grid<T extends (readonly unknown[])[]>(...lists: T): { -readonly [K in keyof T]: T[K][number] }[] {
  return lists.reduce<unknown[][]>((acc, list) => acc.flatMap((prefix) => list.map((x) => [...prefix, x])), [[]]) as never;
}

/** One case to a line, so a change reads as a short diff. */
export function caseText(file: CaseFile): string {
  const fns = file.functions.map((fn) => {
    const rows = fn.cases.map((c) => `      ${JSON.stringify(c)}`).join(',\n');
    return `    {\n      "fn": ${JSON.stringify(fn.fn)},\n      "about": ${JSON.stringify(fn.about)},\n      "cases": [\n${rows}\n      ]\n    }`;
  });
  return `{\n  "area": ${JSON.stringify(file.area)},\n  "functions": [\n${fns.join(',\n')}\n  ]\n}\n`;
}
