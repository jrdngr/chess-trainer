import { addLine, createRepertoire } from "../../model/repertoire";
import { openingTree } from "../../model/openingTree";
import { referenceIndex } from "../../model/referenceIndex";
import {
  effectiveLevel,
  narrowingBar,
  rank,
  recentCount,
  recommend,
  reviewNeed,
  saturate,
  steeredRecently,
  testNeed,
  type Candidate,
  type Focus,
} from "../../model/recommend";
import { EMPTY_SCORE, recordRound, seenIn } from "../../model/scoring";
import type { Selection } from "../../model/selection";
import { allItems } from "../../model/session";
import { createCard } from "../../model/srs";
import type { Card, Repertoire } from "../../model/types";
import { cases, grid, range, type CaseFile } from "../caseKit";

const tree = openingTree(referenceIndex());
const T = Date.parse("2026-10-01T09:00:00Z");
const DAY = 86_400_000;

const NAJDORF = "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6";
const DRAGON = "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6";
const ITALIAN = "e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d3";
const QGD = "d4 d5 c4 e6 Nc3 Nf6 Bg5 Be7";

/**
 * A situation for `recommend`, as data: the lines of each side's prep (every
 * move added ten days before), which of its positions have cards and how
 * they stand, and the selection and recent rounds.
 */
interface Situation {
  white: string[];
  black: string[];
  /** Cards for every position whose line starts with one of these; `due` ones fell due a moment ago, the rest in five days. */
  cards: { prefix: string; due: boolean }[];
  selection: Selection;
  recentFocuses: Focus[];
  recentSteered: boolean[];
  starred: string[];
  /** Runs already played in the selection, by the line each ran, a day apart and ending an hour before. */
  played: string[];
}

function rep(color: "w" | "b", lines: string[]): Repertoire {
  let out = createRepertoire(
    color === "w" ? "White" : "Black",
    color,
    `rep_${color}`,
  );
  for (const line of lines) out = addLine(out, line.split(" "), "book").rep;
  for (const node of Object.values(out.nodes)) node.addedAt = T - 10 * DAY;
  return out;
}

function recommendIn(s: Situation) {
  const reps = [rep("w", s.white), rep("b", s.black)].filter(
    (r) => r.rootChildren.length,
  );
  const cards: Record<string, Card> = {};
  for (const item of allItems(reps)) {
    const rule = s.cards.find(
      (c) => item.pathSans.join(" ").startsWith(c.prefix) || c.prefix === "",
    );
    if (!rule) continue;
    const card = createCard(
      item.cardId,
      item.repertoireId,
      item.key,
      item.fen,
      T - DAY,
    );
    cards[item.cardId] = {
      ...card,
      stage: "review",
      interval: 3,
      due: rule.due ? T - 1 : T + 5 * DAY,
    };
  }
  const score = s.played.reduce(
    (score, line, i) =>
      recordRound(score, tree, {
        mode: "run",
        openingId: s.selection.opening,
        color: "w",
        answered: 1,
        correct: 1,
        perfect: false,
        line: line.split(" "),
        at: T - 3_600_000 - (s.played.length - 1 - i) * DAY,
      }),
    EMPTY_SCORE,
  );
  const pick = recommend({
    tree,
    selection: s.selection,
    reps,
    cards,
    repairs: [],
    score,
    seen: seenIn(score),
    starred: s.starred,
    newPerSession: 8,
    recentFocuses: s.recentFocuses,
    recentSteered: s.recentSteered,
    now: T,
  });
  return (
    pick && {
      focus: pick.focus,
      opening: pick.opening.id,
      color: pick.color,
      start: pick.start,
    }
  );
}

const base: Situation = {
  white: [],
  black: [],
  cards: [],
  selection: { color: "random", opening: "" },
  recentFocuses: [],
  recentSteered: [],
  starred: [],
  played: [],
};
const at = (over: Partial<Situation>): [Situation] => [{ ...base, ...over }];
const sicilian =
  tree.root.children
    .find((n) => n.sans.join(" ") === "e4")
    ?.children.find((n) => n.sans.join(" ") === "e4 c5")?.id ?? "";

const SITUATIONS: [Situation][] = [
  at({}),
  at({ black: [NAJDORF] }),
  at({ black: [NAJDORF], cards: [{ prefix: "", due: false }] }),
  at({ black: [NAJDORF], cards: [{ prefix: "", due: true }] }),
  at({
    black: [NAJDORF, DRAGON],
    cards: [{ prefix: NAJDORF.slice(0, 20), due: true }],
  }),
  at({
    black: [NAJDORF, DRAGON],
    cards: [{ prefix: "", due: true }],
    recentFocuses: ["review", "review"],
  }),
  at({
    black: [NAJDORF, DRAGON],
    cards: [{ prefix: "", due: false }],
    recentFocuses: ["test", "test", "test"],
  }),
  at({
    white: [ITALIAN, QGD],
    black: [NAJDORF],
    cards: [{ prefix: "d4", due: true }],
  }),
  at({
    white: [ITALIAN, QGD],
    black: [NAJDORF],
    cards: [{ prefix: "d4", due: true }],
    selection: { color: "w", opening: "" },
  }),
  at({
    white: [ITALIAN, QGD],
    black: [NAJDORF],
    cards: [{ prefix: "d4", due: true }],
    selection: { color: "b", opening: "" },
  }),
  at({
    white: [ITALIAN],
    black: [NAJDORF, DRAGON],
    cards: [{ prefix: "", due: true }],
    selection: { color: "b", opening: sicilian },
  }),
  at({
    white: [ITALIAN],
    black: [NAJDORF, DRAGON],
    cards: [{ prefix: "", due: true }],
    selection: { color: "b", opening: sicilian },
    recentSteered: [true],
  }),
  at({
    white: [ITALIAN, QGD],
    cards: [{ prefix: "", due: true }],
    starred: [QGD.split(" ").slice(0, 4).join(" ")],
  }),
  // With runs behind it, a Test has had its say, and the due cards come round.
  at({
    black: [NAJDORF],
    cards: [{ prefix: "", due: true }],
    played: [NAJDORF],
  }),
  at({
    black: [NAJDORF, DRAGON],
    cards: [{ prefix: NAJDORF.slice(0, 20), due: true }],
    played: [DRAGON, NAJDORF],
  }),
  at({
    black: [NAJDORF, DRAGON],
    cards: [{ prefix: "", due: false }],
    played: [DRAGON, NAJDORF],
  }),
  at({
    white: [ITALIAN, QGD],
    black: [NAJDORF],
    cards: [{ prefix: "d4", due: true }],
    played: [NAJDORF, ITALIAN, QGD],
  }),
  at({
    white: [ITALIAN, QGD],
    black: [NAJDORF],
    cards: [{ prefix: "d4", due: true }],
    played: [NAJDORF, ITALIAN, QGD],
    recentFocuses: ["review", "review"],
  }),
  at({
    white: [ITALIAN],
    black: [NAJDORF, DRAGON],
    cards: [{ prefix: "", due: true }],
    selection: { color: "b", opening: sicilian },
    played: [NAJDORF, DRAGON],
  }),
  at({
    white: [ITALIAN, QGD],
    cards: [{ prefix: "", due: true }],
    starred: [QGD.split(" ").slice(0, 4).join(" ")],
    played: [ITALIAN, QGD],
  }),
];

const candidate = (
  focus: Focus,
  openingId: string,
  need: number,
  lastAt: number | null,
  level = 0,
  starred = false,
): Omit<Candidate, "score"> => ({
  focus,
  openingId,
  color: "w",
  need,
  work: 4,
  lastAt,
  starred,
  level,
});

const file: CaseFile = {
  area: "recommend",
  functions: [
    cases(
      "recommend.saturate",
      "Diminishing returns on a count: `half` scores 0.5.",
      saturate,
      grid([0, 1, 2, 4, 10, 24, 100, 400], [4, 10, 24]),
    ),
    cases(
      "recommend.reviewNeed",
      "Review debt: due cards lead, unseen positions are worth doing but never urgent.",
      reviewNeed,
      grid([0, 1, 5, 24, 100], [0, 2, 8, 50], [0, 4, 8]),
    ),
    cases(
      "recommend.testNeed",
      "How loudly a Test asks: more for prep added since, scaled by how long its lines were left.",
      testNeed,
      grid([0, 1, 5, 10, 40], [false, true], [0, 0.5, 1]),
    ),
    cases(
      "recommend.narrowingBar",
      "The share of its parent’s work a variation must hold to be steered toward.",
      narrowingBar,
      range(0, 5).map((n) => [n] as [number]),
    ),
    cases(
      "recommend.effectiveLevel",
      "A star is worth one level.",
      effectiveLevel,
      grid(range(0, 4), [false, true]),
    ),
    cases(
      "recommend.recentCount",
      "How many of the last few rounds were this focus.",
      recentCount,
      grid(
        [
          [],
          ["test"],
          ["review", "review"],
          ["test", "review", "test", "review", "test", "review", "review"],
        ] as Focus[][],
        ["test", "review"] as Focus[],
      ),
    ),
    cases(
      "recommend.steeredRecently",
      "Whether one of the last few rounds was steered below the selection.",
      steeredRecently,
      [
        [[]],
        [[true]],
        [[true, false, false]],
        [[true, false, false, false]],
        [[false, false, true]],
      ],
    ),
    cases(
      "recommend.rank",
      "Candidates scored and sorted: need, staleness against the others, depth and the brake.",
      rank,
      [
        [
          [
            candidate("test", "a", 0.6, null),
            candidate("review", "b", 0.6, null),
          ],
          [],
        ],
        [
          [
            candidate("test", "a", 0.6, T),
            candidate("review", "b", 0.5, T - DAY),
          ],
          [],
        ],
        [
          [
            candidate("test", "a", 0.6, T),
            candidate("review", "b", 0.5, T - DAY),
          ],
          ["review", "review"],
        ],
        [
          [
            candidate("review", "a", 0.6, null, 0),
            candidate("review", "b", 0.6, null, 2),
            candidate("review", "c", 0.6, null, 2, true),
          ],
          ["test"],
        ],
        [
          [
            candidate("review", "a", 0.3, T - 3 * DAY),
            candidate("review", "b", 0.3, T - 2 * DAY),
            candidate("review", "c", 0.3, T - DAY),
          ],
          [],
        ],
      ],
    ),
    cases(
      "recommend.recommend",
      "The one thing to start, from a situation (see `recommendIn` in the case file): prep by side, cards, selection and recent rounds.",
      recommendIn,
      SITUATIONS,
    ),
  ],
};

export default file;
