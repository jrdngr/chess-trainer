import { describe, expect, it } from 'vitest';
import type { GrowthRow, Hole } from './growth';
import { growthRows, rowUrgency } from './growth';
import { EMPTY_RECORD, type OpeningRunRecord } from './openingRun';
import { referenceIndex } from './referenceIndex';
import { addLine, createRepertoire } from './repertoire';
import type { RepairItem } from './repair';
import type { Repertoire } from './types';
import {
  candidates,
  drillDraw,
  drillPressure,
  growthPressure,
  NO_ACTIVITY,
  nextUp,
  normalizeActivity,
  noted,
  openingRunPressure,
  planFor,
  rank,
  runColor,
  repairPressure,
  untestedSince,
  type Activity,
  type NextUpInput,
  type NextUpMode,
} from './nextUp';

const index = referenceIndex();

/* ── fixtures ───────────────────────────────────────────────────────────── */

const hole = (): Hole => ({
  path: [],
  fen: '',
  san: 'e5',
  share: 20,
  games: 100,
  after: '',
  nodeId: null,
});

function row(depth: number, topShare: number, name = 'Sicilian Defence', holes = 1): GrowthRow {
  const urgency = rowUrgency(depth, topShare, holes);
  return {
    id: `${name}#${depth}`,
    repertoireId: 'r_w',
    color: 'w',
    name,
    depth,
    topShare,
    starred: false,
    urgency,
    score: urgency,
    holes: Array.from({ length: holes }, hole),
  };
}

function repair(weight: number): RepairItem {
  return {
    id: `x${weight}`,
    kind: 'offprep',
    source: 'games',
    repertoireId: 'r_w',
    color: 'w',
    key: '',
    fen: '',
    path: [],
    lineText: '',
    games: 2,
    results: { wins: 0, draws: 0, losses: 2 },
    played: [],
    expected: [],
    weight,
  };
}

function record(patch: Partial<OpeningRunRecord> = {}): OpeningRunRecord {
  return { ...EMPTY_RECORD, ...patch };
}

function input(patch: Partial<NextUpInput> = {}): NextUpInput {
  return {
    due: 0,
    unseen: 0,
    newPerSession: 8,
    growth: [],
    repairs: [],
    reps: [],
    openingRun: record(),
    activity: { ...NO_ACTIVITY },
    ...patch,
  };
}

/** A repertoire of the shape a real user ends up with: one saved line. */
function thin(color: 'w' | 'b', line: string): Repertoire {
  return addLine(createRepertoire('Test', color, `r_${color}`), line.split(' '), 'reference').rep;
}

const DAY = 86_400_000;
const T = 1_700_000_000_000;

/* ── pressure ───────────────────────────────────────────────────────────── */

describe('pressure', () => {
  it('rises with the size of the drill queue, without ever running away with it', () => {
    expect(drillPressure(4, 0, 8)).toBeLessThan(drillPressure(40, 0, 8));
    // Four hundred due is not twice the emergency two hundred is. Without the
    // ceiling, one abandoned schedule would own the button forever.
    expect(drillPressure(400, 0, 8) - drillPressure(200, 0, 8)).toBeLessThan(0.1);
    expect(drillPressure(400, 0, 8)).toBeLessThanOrEqual(1);
  });

  it('treats unseen positions as worth doing but never urgent', () => {
    expect(drillPressure(0, 50, 8)).toBeLessThan(drillPressure(30, 0, 8));
    expect(drillPressure(0, 0, 8)).toBe(0);
  });

  it('will not count more new positions than a session would introduce', () => {
    expect(drillPressure(0, 200, 4)).toBe(drillPressure(0, 4, 4));
  });

  it('costs a hole by how often you fall into it, not by how many there are', () => {
    const shallow = growthPressure([row(1, 25)]);
    const deep = growthPressure([row(15, 25)]);
    const rare = growthPressure([row(1, 1.5)]);
    expect(shallow).toBeGreaterThan(deep);
    expect(shallow).toBeGreaterThan(rare);
    // A first-move reply a quarter of opponents play is the loudest thing the
    // app can say.
    expect(shallow).toBeGreaterThan(0.7);
    expect(deep).toBeLessThan(0.3);
  });

  it('gives a thin repertoire with holes everywhere a little extra weight', () => {
    expect(growthPressure([row(4, 10), row(4, 10, 'French Defence')])).toBeGreaterThan(
      growthPressure([row(4, 10)]),
    );
  });

  it('is silent when a mode has nothing waiting', () => {
    expect(growthPressure([])).toBe(0);
    expect(repairPressure([])).toBe(0);
  });

  it('weighs repairs both by how bad the worst one is and by how many there are', () => {
    expect(repairPressure([repair(20)])).toBeGreaterThan(repairPressure([repair(2)]));
    expect(repairPressure(Array.from({ length: 12 }, () => repair(2)))).toBeGreaterThan(
      repairPressure([repair(2)]),
    );
    // One position you drifted through once is not a session.
    expect(repairPressure([repair(2.5)])).toBeLessThan(0.3);
  });

  it('asks for a first run, and asks harder the more untested prep has piled up', () => {
    expect(openingRunPressure(0, 0)).toBeGreaterThanOrEqual(0.55);
    expect(openingRunPressure(40, 9)).toBeGreaterThan(openingRunPressure(0, 9));
    expect(openingRunPressure(40, 9)).toBeLessThanOrEqual(1);
  });
});

describe('untested prep', () => {
  it('counts every move when no run has ever been made', () => {
    const rep = thin('w', 'e4 c5 Nf3');
    expect(untestedSince([rep], null)).toBe(Object.keys(rep.nodes).length);
  });

  it('counts nothing once a run has happened since the moves were added', () => {
    const rep = thin('w', 'e4 c5 Nf3');
    expect(untestedSince([rep], Date.now() + DAY)).toBe(0);
  });
});

/* ── what is on offer ───────────────────────────────────────────────────── */

describe('candidates', () => {
  it('offers Opening Run on a brand new install, where nothing else can run', () => {
    const offered = candidates(input()).map((c) => c.mode);
    expect(offered).toEqual(['openingRun']);
    expect(nextUp(input()).mode).toBe('openingRun');
  });

  it('never offers a mode with nothing to work on', () => {
    const offered = candidates(input({ due: 12, repairs: [repair(6)] })).map((c) => c.mode);
    expect(offered).toContain('drill');
    expect(offered).toContain('repair');
    expect(offered).not.toContain('growth');
  });

});

/* ── the ranking ────────────────────────────────────────────────────────── */

describe('ranking', () => {
  it('leads with the loudest mode when nothing has been done yet', () => {
    // Everything is equally stale on a new install, so pressure decides alone.
    expect(nextUp(input({ due: 120, growth: [row(14, 1.2)] })).mode).toBe('drill');
    expect(nextUp(input({ due: 6, growth: [row(1, 28)] })).mode).toBe('growth');
  });

  it('sends you somewhere else once you have just done a mode', () => {
    const work = { due: 60, growth: [row(5, 12)], repairs: [repair(9), repair(6)] };
    expect(nextUp(input(work)).mode).toBe('drill');
    expect(nextUp(input({ ...work, activity: { ...NO_ACTIVITY, drill: T } })).mode).not.toBe(
      'drill',
    );
  });

  it('comes back to a standing backlog rather than rotating away from it forever', () => {
    // Drill something huge, then do everything else. It is due again.
    const activity: Activity = { drill: T, repair: T + DAY, growth: T + 2 * DAY };
    const pick = nextUp(
      input({
        due: 200,
        growth: [row(9, 4)],
        repairs: [repair(4)],
        openingRun: record({ runs: 3, lastAt: T + 3 * DAY }),
        activity,
      }),
    );
    expect(pick.mode).toBe('drill');
  });

  it('never picks a mode with nothing waiting, however long it has been neglected', () => {
    // Growth is the stalest thing there is — it has never been done — and there
    // is still nothing in it to do.
    const pick = nextUp(
      input({ due: 3, openingRun: record({ runs: 40, lastAt: T }), activity: { ...NO_ACTIVITY, drill: T } }),
    );
    expect(pick.mode).not.toBe('growth');
  });

  it('treats two modes you have never done as equally stale', () => {
    const ranked = rank(
      candidates(
        input({
          due: 40,
          growth: [row(6, 10)],
          repairs: [repair(5)],
          activity: { ...NO_ACTIVITY, drill: T },
        }),
      ),
    );
    const growth = ranked.find((c) => c.mode === 'growth')!;
    const repairRank = ranked.find((c) => c.mode === 'repair')!;
    // Neither has been done, so neither is pushed down by the other: their
    // scores stand in the same ratio as their pressures.
    expect(growth.score / growth.pressure).toBeCloseTo(repairRank.score / repairRank.pressure, 10);
  });

  it('brings every mode with work in it round, given a few sittings', () => {
    const work = {
      due: 45,
      growth: [row(3, 14)],
      repairs: [repair(8), repair(5), repair(3)],
      openingRun: record({ runs: 2, lastAt: T }),
    };
    let activity: Activity = { ...NO_ACTIVITY };
    let openingRun = work.openingRun;
    const visited: NextUpMode[] = [];

    for (let i = 0; i < 6; i += 1) {
      const pick = nextUp(input({ ...work, openingRun, activity }));
      visited.push(pick.mode);
      const at = T + (i + 1) * 1000;
      if (pick.mode === 'openingRun') openingRun = record({ runs: 3, lastAt: at });
      else activity = noted(activity, pick.mode, at);
    }

    expect(new Set(visited).size).toBe(4);
  });

  it('is stable: the same state always gives the same answer', () => {
    const state = input({ due: 20, growth: [row(6, 10)], repairs: [repair(5)] });
    expect(nextUp(state).mode).toBe(nextUp(state).mode);
  });

  it('recommends what the player actually has, on a real thin repertoire', () => {
    // One saved Sicilian line as White, never drilled, never run. Every reply
    // to 1.e4 except 1...c5 is unanswered, and that is the shallowest work
    // there is.
    const rep = thin('w', 'e4 c5 Nf3 d6 d4');
    const rows = growthRows([rep], index);
    expect(rows.length).toBeGreaterThan(0);
    const pick = nextUp(
      input({
        due: 4,
        reps: [rep],
        growth: rows,
        activity: { ...NO_ACTIVITY, drill: T },
        openingRun: record({ runs: 1, lastAt: T }),
      }),
    );
    expect(pick.mode).toBe('growth');
  });
});

/* ── starting it ────────────────────────────────────────────────────────── */

describe('the draw a recommended drill uses', () => {
  it('keeps your own choice when it would find something', () => {
    expect(drillDraw('new', 0, 12)).toBe('new');
    expect(drillDraw('due', 30, 0)).toBe('due');
    expect(drillDraw('cram', 0, 0)).toBe('cram');
  });

  it('corrects a choice that would open onto an empty session', () => {
    expect(drillDraw('new', 30, 0)).toBe('due');
    expect(drillDraw('due', 0, 12)).toBe('new');
  });
});

/* ── the record of what you have done ───────────────────────────────────── */

describe('activity', () => {
  it('reads a save from before any of it was recorded as "never"', () => {
    expect(normalizeActivity(undefined)).toEqual(NO_ACTIVITY);
    expect(normalizeActivity({ drill: T })).toEqual({ ...NO_ACTIVITY, drill: T });
  });

  it('stamps one mode without touching the others', () => {
    expect(noted(NO_ACTIVITY, 'growth', T)).toEqual({ ...NO_ACTIVITY, growth: T });
  });
});

/* ── what the recommendation decides for you ────────────────────────────── */

describe('the plan a recommendation starts a mode on', () => {
  it('never sends a run out on a random colour', () => {
    // Random is an answer to "surprise me" and not to "what needs work" — and
    // a plan holds for the whole visit, so a random colour would also mean the
    // second run contradicts the first for no reason.
    for (const reps of [[], [thin('w', 'e4 e5 Nf3')], [thin('b', 'd4 Nf6 c4 g6')]]) {
      const plan = planFor('openingRun', input({ reps }));
      expect(plan.openingRun?.color).toMatch(/^[wb]$/);
    }
  });

  it('picks the side with prep no run has asked about yet', () => {
    const white = thin('w', 'e4 e5 Nf3 Nc6 Bb5');
    const black = thin('b', 'd4 Nf6');
    // Both sides untested, White has more of it.
    expect(runColor(input({ reps: [white, black] }))).toBe('w');
    expect(runColor(input({ reps: [black, white] }))).toBe('w');
  });

  it('falls to the larger side once everything has been run', () => {
    const white = thin('w', 'e4 e5');
    const black = thin('b', 'd4 Nf6 c4 g6 Nc3');
    // A last run after every move was added leaves nothing untested either way.
    const after = input({ reps: [white, black], openingRun: record({ lastAt: Date.now() + 1000 }) });
    expect(untestedSince(after.reps, after.openingRun.lastAt)).toBe(0);
    expect(runColor(after)).toBe('b');
  });

  it('settles on one side when there is nothing to go on at all', () => {
    // Not a coin toss: a fresh install has no signal, and a colour that changes
    // under the player between runs is worse than one that does not.
    expect(runColor(input())).toBe('w');
    expect(runColor(input())).toBe('w');
  });

  it('corrects a draw that would open onto nothing', () => {
    expect(planFor('drill', input({ preferredDraw: 'new', unseen: 0, due: 5 })).drill?.draw).toBe(
      'due',
    );
    expect(planFor('drill', input({ preferredDraw: 'due', due: 0, unseen: 5 })).drill?.draw).toBe(
      'new',
    );
  });

  it('leaves a draw that works alone', () => {
    expect(planFor('drill', input({ preferredDraw: 'cram', due: 5 })).drill?.draw).toBe('cram');
    expect(planFor('drill', input({ preferredDraw: 'due', due: 5 })).drill?.draw).toBe('due');
  });

  it('has no opinion about the modes whose options it cannot reason about', () => {
    expect(planFor('growth', input())).toEqual({});
    expect(planFor('repair', input())).toEqual({});
  });

  it('only ever decides options the reasoning actually implies', () => {
    // The rest stay the player's. Nothing about "what now" says how many new
    // positions a session should introduce.
    const plan = planFor('drill', input({ due: 5, preferredDraw: 'due' }));
    expect(Object.keys(plan.drill ?? {})).toEqual(['draw']);
    expect(Object.keys(planFor('openingRun', input()).openingRun ?? {})).toEqual(['color']);
  });
});
