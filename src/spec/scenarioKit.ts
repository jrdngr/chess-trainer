/**
 * Golden scenarios: a whole run driven through a controller, one event at a
 * time, with what each event did — its effects and the session after it —
 * recorded as the prototype's own controller produced it.
 *
 * A scenario is written here as a short script (your moves, the engine's
 * replies). The driver resolves it into the exact controller calls the
 * screen would make, in the screen's order, and the JSON keeps those calls,
 * so the native app replays the calls without any driver of its own. Never
 * edit a file under spec/cases/scenarios by hand: change the script, or the
 * model, and run `npm run spec:cases`.
 */

import { env, setEnv } from '../model/env';

export interface ScenarioStep {
  /** The controller call, `function` plus its data arguments. */
  call: { fn: string } & Record<string, unknown>;
  effects: unknown[];
  /** The session after the call, summarized to what the run decides. */
  after: unknown;
}

export interface Scenario {
  name: string;
  about: string;
  /** Everything the run is begun and played under, as data. */
  setup: unknown;
  steps: ScenarioStep[];
}

export interface ScenarioFile {
  area: string;
  scenarios: Scenario[];
}

export { json } from './caseKit';

/** One step to a line, so a change reads as a short diff. */
export function scenarioText(file: ScenarioFile): string {
  const scenarios = file.scenarios.map((s) => {
    const steps = s.steps.map((step) => `        ${JSON.stringify(step)}`).join(',\n');
    return [
      '    {',
      `      "name": ${JSON.stringify(s.name)},`,
      `      "about": ${JSON.stringify(s.about)},`,
      `      "setup": ${JSON.stringify(s.setup)},`,
      `      "steps": [\n${steps}\n      ]`,
      '    }',
    ].join('\n');
  });
  return `{\n  "area": ${JSON.stringify(file.area)},\n  "scenarios": [\n${scenarios.join(',\n')}\n  ]\n}\n`;
}

/** Run `fn` with the app's clock pinned to `now()`, so anything stamped inside it is the scenario's time. */
export function pinnedClock<T>(now: () => number, fn: () => T): T {
  const was = env.now;
  setEnv({ now });
  try {
    return fn();
  } finally {
    setEnv({ now: was });
  }
}
