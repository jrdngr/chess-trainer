import {
  earned,
  longestStreak,
  milestones,
  nextUp,
  peakRating,
  progress,
  type Milestone,
} from "../../model/milestones";
import { openingTree } from "../../model/openingTree";
import { referenceIndex } from "../../model/referenceIndex";
import {
  EMPTY_SCORE,
  emptyNodeStats,
  ratingChange,
  ratingOn,
  streak,
  type DayTally,
  type NodeStats,
  type ScoreState,
} from "../../model/scoring";
import { EMPTY_SURVIVAL_SCORE, type SurvivalRecord } from "../../model/survival";
import { cases, type CaseFile } from "../caseKit";

const tree = openingTree(referenceIndex());

/** Noon on a day, so the day is the same in every time zone within eleven hours. */
const noon = (key: string) => {
  const [y, m, d] = key.split("-").map(Number);
  return new Date(y, m - 1, d, 12).getTime();
};

/** An opening's or the game's stats from its days: [day, rounds, end-of-day rating or null], and where the rating stands now. */
function stats(
  days: [string, number, number | null][],
  rating = 0,
  rated = days.some(([, , r]) => r !== null) ? 10 : 0,
): NodeStats {
  return {
    ...emptyNodeStats(),
    rating,
    rated,
    days: Object.fromEntries(
      days.map(([key, rounds, r]): [string, DayTally] => [
        key,
        { answered: rounds * 5, correct: rounds * 4, rounds, rating: r },
      ]),
    ),
  };
}

const STREAKS: [string, number, number | null][][] = [
  [],
  [["2026-10-01", 1, null]],
  [
    ["2026-10-01", 1, null],
    ["2026-10-02", 2, null],
    ["2026-10-03", 1, null],
    ["2026-10-05", 1, null],
  ],
  [
    ["2026-10-29", 1, null],
    ["2026-10-30", 1, null],
    ["2026-10-31", 1, null],
  ],
  [
    ["2026-10-29", 1, null],
    ["2026-10-30", 1, null],
  ],
  [
    ["2026-10-28", 1, null],
    ["2026-10-30", 0, null],
    ["2026-10-31", 1, null],
  ],
  // Across a month and a daylight-saving change.
  [
    ["2026-10-30", 1, null],
    ["2026-10-31", 1, null],
    ["2026-11-01", 1, null],
    ["2026-11-02", 1, null],
  ],
];

/** A profile's record, in short: global days, each opening's rated days and rating now, Survival best, rounds by mode. */
interface Profile {
  days: [string, number, number | null][];
  openings: Record<string, [[string, number, number | null][], number]>;
  best: number;
  rounds: Partial<Record<"survival" | "drill" | "growth" | "run" | "repair", number>>;
}

function profile(p: Profile): { score: ScoreState; survival: SurvivalRecord } {
  const global = stats(p.days, 0, 0);
  for (const [mode, n] of Object.entries(p.rounds))
    global.byMode[mode as keyof typeof global.byMode] = {
      ...global.byMode[mode as keyof typeof global.byMode],
      rounds: n,
    };
  return {
    score: {
      ...EMPTY_SCORE,
      global,
      nodes: Object.fromEntries(
        Object.entries(p.openings).map(([id, [days, rating]]) => [
          id,
          stats(days, rating),
        ]),
      ),
    },
    survival: {
      global: { ...EMPTY_SURVIVAL_SCORE, best: p.best },
      openings: {},
    } as SurvivalRecord,
  };
}

const PROFILES: Profile[] = [
  { days: [], openings: {}, best: 0, rounds: {} },
  {
    days: STREAKS[2],
    openings: {
      "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6": [
        [
          ["2026-10-01", 3, 180],
          ["2026-10-02", 3, 260],
        ],
        240,
      ],
      "e4 c5 Nf3 Nc6": [[["2026-10-02", 1, 120]], 120],
      "d4 Nf6 c4 g6 Nc3": [[["2026-10-03", 2, 410]], 400],
      "e4 e5 Nf3 Nc6 Bb5": [[["2026-10-05", 2, 300]], 300],
      "c4": [[["2026-10-05", 2, 900]], 860],
      "not an opening": [[["2026-10-05", 2, 990]], 990],
    },
    best: 23,
    rounds: { survival: 340, drill: 150, growth: 20, run: 5, repair: 3 },
  },
];

const short = (m: Milestone) =>
  `${m.id} ${m.label} ${m.value}/${m.target}${m.color ? ` ${m.color}` : ""}`;

const file: CaseFile = {
  area: "home",
  functions: [
    cases(
      "scoring.streak",
      "Your current streak on a day: days in a row with a round, counting back from that day, or from the day before when that day has none yet.",
      (days: [string, number, number | null][], today: string) =>
        streak(stats(days, 0, 0), noon(today)),
      [
        [STREAKS[0], "2026-10-31"],
        [STREAKS[3], "2026-10-31"],
        [STREAKS[4], "2026-10-31"],
        [STREAKS[4], "2026-11-01"],
        [STREAKS[5], "2026-10-31"],
        [STREAKS[6], "2026-11-02"],
      ],
    ),
    cases(
      "milestones.longestStreak",
      "The longest run of days in a row with a round, ever; a day with no rounds breaks it.",
      (days: [string, number, number | null][]) =>
        longestStreak(stats(days, 0, 0)),
      STREAKS.map((s) => [s] as [typeof s]),
    ),
    cases(
      "milestones.peakRating",
      "The highest an opening's rating has stood: its end-of-day ratings and where it is now; 0 if never rated.",
      (days: [string, number, number | null][], rating: number) =>
        peakRating(stats(days, rating)),
      [
        [[], 0],
        [[["2026-10-01", 1, 300]], 250],
        [[["2026-10-01", 1, 300]], 420],
        [
          [
            ["2026-10-01", 1, 300],
            ["2026-10-02", 1, null],
            ["2026-10-03", 1, 120],
          ],
          100,
        ],
      ],
    ),
    cases(
      "scoring.ratingChange",
      "How far a rating moved over the last days: now, less where it stood at the end of the last day at or before then that moved it (the start, 0, if none).",
      (days: [string, number, number | null][], rating: number, today: string) =>
        ratingChange(stats(days, rating), 7, noon(today)),
      [
        [[["2026-10-30", 1, 200]], 200, "2026-10-31"],
        [
          [
            ["2026-10-20", 1, 150],
            ["2026-10-30", 1, 200],
          ],
          200,
          "2026-10-31",
        ],
        [
          [
            ["2026-10-20", 1, 150],
            ["2026-10-24", 1, 260],
            ["2026-10-30", 1, 200],
          ],
          200,
          "2026-10-31",
        ],
        [[["2026-10-01", 1, 300]], 300, "2026-10-31"],
      ],
    ),
    cases(
      "scoring.ratingOn",
      "Where a rating stood at the end of a day.",
      (key: string) =>
        ratingOn(
          stats([
            ["2026-10-01", 1, 120],
            ["2026-10-03", 1, null],
            ["2026-10-05", 1, 90],
          ]),
          key,
        ),
      ["2026-09-30", "2026-10-01", "2026-10-04", "2026-10-05", "2026-11-01"].map(
        (k) => [k] as [string],
      ),
    ),
    cases(
      "milestones.milestones",
      "Every milestone with how far along it is: streaks 3/7/30 (longest ever), Survival best 10/20/30, a first opening at each tier from Familiar (peak rating), 3/5/10 families at Familiar or better, and 100/500/1k/5k rounds.",
      (p: Profile) => {
        const { score, survival } = profile(p);
        return milestones(score, survival, tree).map(short);
      },
      PROFILES.map((p) => [p] as [Profile]),
    ),
    cases(
      "milestones.nextUp",
      "The unearned milestones closest to done, first; ties keep the list's order. Earned is value at or past the target.",
      (p: Profile, count: number) => {
        const { score, survival } = profile(p);
        const list = milestones(score, survival, tree);
        return {
          earned: list.filter(earned).map((m) => m.id),
          next: nextUp(
            list.filter((m) => m.kind !== "streak"),
            count,
          ).map((m) => `${m.id} ${progress(m).toFixed(3)}`),
        };
      },
      PROFILES.map((p) => [p, 3] as [Profile, number]),
    ),
  ],
};

export default file;
