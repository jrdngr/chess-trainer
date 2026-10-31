import { applySan, START_FEN } from "../../chess/core";
import {
  bookLength,
  lineKinds,
  moveKind,
  movedBy,
} from "../../model/extensions";
import { addMistake, recentMistakes, type Mistake } from "../../model/mistakes";
import {
  growthSource,
  sourceLabel,
  SOURCE_LABELS,
} from "../../model/moveSource";
import { familiesIn, linesOf, openingsIn, type DerivedOpening } from "../../model/openings";
import { withFloor } from "../../model/prepFloor";
import { referenceIndex } from "../../model/referenceIndex";
import {
  addLine,
  createRepertoire,
  decisionPoints,
  leafLines,
  nodeAtLine,
  pruneCount,
  pruneLine,
} from "../../model/repertoire";
import { allItems } from "../../model/session";
import type { MoveSource, Repertoire } from "../../model/types";
import { cases, grid, range, type CaseFile } from "../caseKit";
import { pinnedClock } from "../scenarioKit";

const index = referenceIndex();
const after = (line: string) =>
  (line ? line.split(" ") : []).reduce(
    (fen, san) => applySan(fen, san)!.after,
    START_FEN,
  );
const AT = Date.parse("2026-10-01T09:00:00Z");

function rep(color: "w" | "b", lines: string[]): Repertoire {
  let out = createRepertoire(
    color === "w" ? "White" : "Black",
    color,
    `rep_${color}`,
  );
  for (const line of lines) out = addLine(out, line.split(" "), "seed").rep;
  return out;
}

/** A tree written without its node ids: every line, and every position you answer with its options, preferred first. */
function shape(r: Repertoire) {
  return {
    lines: leafLines(r).map((line) => line.sans.join(" ")),
    positions: decisionPoints(r).map((point) => ({
      path: point.pathSans.join(" "),
      options: point.options.map((o) => `${o.san}${o.preferred ? "*" : ""}`),
    })),
    items: allItems([r]).length,
  };
}

const TREES: { color: "w" | "b"; lines: string[] }[] = [
  {
    color: "b",
    lines: [
      "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6",
      "d4 Nf6 c4 g6 Nf3 Bg7 g3 O-O",
      "e4 c5 Nf3 d6",
    ],
  },
  {
    color: "w",
    lines: [
      "e4 e5 Nf3 Nc6 Bc4",
      "e4 e5 Nf3 Nf6 Nxe5",
      "e4 c5 Nf3 d6 d4",
      "e4 c5 c3",
    ],
  },
  // A transposition: the same position by two move orders is one position to answer.
  { color: "w", lines: ["d4 Nf6 c4 e6 Nc3", "c4 e6 d4 Nf6 Nc3"] },
];

/** Playbooks as the Playbook tab and the openings list read them. */
const LISTED: { color: "w" | "b"; lines: string[] }[] = [
  ...TREES,
  { color: "b", lines: ["e4 e5"] },
  { color: "b", lines: ["e4 e5 Nf3 Nc6 Bc4 Bc5", "e4 e5 Nf3 Nc6 Bb5 a6"] },
  {
    color: "b",
    lines: ["e4 e5 Nf3 Nc6 Bc4 Bc5", "e4 e5 Nf3 Nc6 Bb5 a6", "e4 e5 Qh5 Nc6"],
  },
  {
    color: "w",
    lines: ["e4 c5 Nf3 d6", "e4 e5 Nf3 Nc6 Bb5 a6", "e4 e6 d4 d5 Nc3"],
  },
  {
    color: "b",
    lines: [
      "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5",
      "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f3 O-O Be3 e5",
      "d4 Nf6 c4 g6 Nc3 d5 cxd5 Nxd5",
      "d4 Nf6 Nf3 g6 Bf4 Bg7",
      "d4 Nf6 Bg5 Ne4",
    ],
  },
  {
    color: "w",
    lines: [
      "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3",
      "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Bg5",
      "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6 Be3",
      "e4 c5 Nf3 Nc6 d4 cxd4 Nxd4",
    ],
  },
];

/** An opening as listed, without node ids. */
function listed(r: Repertoire, o: DerivedOpening): unknown {
  return {
    name: o.name,
    eco: o.eco ?? null,
    path: o.path.join(" "),
    moves: o.moves,
    removes: o.removes,
    lines: o.lines,
    depth: o.depth,
    variations: o.variations.map((v) => listed(r, v)),
    nested: (o.nested ?? []).length,
  };
}

const LINES = [
  ["e4 e5 Nf3 Nc6 Bc4", "w"],
  ["e4 e5 Nf3 Nc6 Bc4 Bc5 b4", "w"],
  ["e4 e5 Qh5 Nc6 Bc4", "w"],
  ["e4 e5 a3", "w"],
  ["d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nc6 d5 Ne7", "b"],
  ["e4 c5 Nf3 a6 c3 b5", "b"],
  ["e4 g5 d4 h6", "b"],
] as const;

const mistake = (key: string, played: string): Omit<Mistake, "id" | "at"> => ({
  source: "drill",
  repertoireId: "rep_w",
  key,
  fen: "",
  path: [],
  played,
  expected: "e4",
});

/** Mistakes logged one after another, a second apart: the log after each. */
function logged(entries: [string, string][], limit?: number) {
  let log: Mistake[] = [];
  let at = AT;
  const all = entries.map(([key, played]) => {
    at += 1000;
    log = pinnedClock(
      () => at,
      () => addMistake(log, mistake(key, played)),
    );
    return log.map((m) => `${m.key}:${m.played}`);
  });
  return limit === undefined ? all : all.at(-1)!.length;
}

const file: CaseFile = {
  area: "playbook",
  functions: [
    cases(
      "repertoire.shape",
      "A Playbook tree as lines and the positions you answer, preferred move marked *; a transposition is one position with its options merged.",
      (t: (typeof TREES)[number]) => shape(rep(t.color, t.lines)),
      TREES.map((t) => [t] as [(typeof TREES)[number]]),
    ),
    cases(
      "repertoire.pruneLine",
      "Removing a line takes the moves that only led to it, up to the first real branch: the lines left, and how many moves went.",
      (t: (typeof TREES)[number], line: string) => {
        const r = rep(t.color, t.lines);
        const node = nodeAtLine(r, line.split(" "))!;
        return {
          removed: pruneCount(r, node.id),
          left: shape(pruneLine(r, node.id)).lines,
        };
      },
      [
        [TREES[0], "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6"],
        [TREES[0], "d4 Nf6 c4 g6 Nc3"],
        [TREES[0], "e4 c5 Nf3 d6"],
        [TREES[1], "e4 c5 c3"],
        [TREES[1], "e4"],
      ],
    ),
    cases(
      "openings.familiesIn",
      "The Playbook tab's list: one row per family the tree holds lines in, a family of its own nested inside another listed on its own, rows with no lines of their own left out; a Black row the book names after White's moves is called by Black's first move when that is unambiguous.",
      (t: (typeof LISTED)[number]) => {
        const r = rep(t.color, t.lines);
        return familiesIn(r, index).map((o) => listed(r, o));
      },
      LISTED.map((t) => [t] as [(typeof LISTED)[number]]),
    ),
    cases(
      "openings.openingsIn",
      "Every opening in a tree, biggest first, with its variations: named regions, waypoints that only lead somewhere dropped.",
      (t: (typeof LISTED)[number]) => {
        const r = rep(t.color, t.lines);
        return openingsIn(r, index).map((o) => listed(r, o));
      },
      LISTED.map((t) => [t] as [(typeof LISTED)[number]]),
    ),
    cases(
      "openings.linesOf",
      "Each line of a listed family, named for where it goes, with the move it splits off at when two share a name, and what deleting it removes.",
      (t: (typeof LISTED)[number]) => {
        const r = rep(t.color, t.lines);
        return familiesIn(r, index).map((o) => ({
          family: o.name,
          lines: linesOf(r, o, index).map(({ tipId: _tip, ...line }) => ({
            ...line,
            path: line.path.join(" "),
          })),
        }));
      },
      LISTED.map((t) => [t] as [(typeof LISTED)[number]]),
    ),
    cases(
      "extensions.moveKind",
      "What one of your moves is: book (at least 5% of strong games and not a mistake), rare, a mistake (gives away over 80cp), or past the book.",
      (line: string, san: string, lost: number | null) =>
        moveKind(index, after(line), san, lost ?? undefined),
      [
        ["", "e4", null],
        ["", "a3", null],
        ["", "e4", 120],
        ["", "e4", 80],
        ["e4 e5", "Qh5", null],
        ["e4 e5", "Nf3", null],
        ["e4 e5", "Nf3", 81],
        [
          "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nc6 d5 Ne7 Ne1 Nd7 Nd3 f5 Bd2 Nf6 f3 f4 g4 g5",
          "Kh1",
          null,
        ],
      ],
    ),
    cases(
      "extensions.lineKinds",
      "Each move of a line by kind for one side: the opponent's always book, and once yours leaves the book every later one of yours is an extension.",
      (line: string, color: "w" | "b") =>
        lineKinds(index, line.split(" "), color),
      LINES.map(([l, c]) => [l, c] as [string, "w" | "b"]),
    ),
    cases(
      "extensions.bookLength",
      "Where a line becomes an extension.",
      (line: string, color: "w" | "b") =>
        bookLength(lineKinds(index, line.split(" "), color)),
      LINES.map(([l, c]) => [l, c] as [string, "w" | "b"]),
    ),
    cases(
      "extensions.movedBy",
      "Whether a ply is played by a side.",
      movedBy,
      grid(range(0, 5), ["w", "b"] as const),
    ),
    cases(
      "prepFloor.withFloor",
      "The opponent's shares at a position: each reply you prepared lifted to at least 15%, lifted ones sharing at most half, the rest scaled to make room.",
      withFloor,
      [
        [
          [90, 8, 2],
          [false, false, true],
        ],
        [
          [90, 8, 2],
          [false, true, true],
        ],
        [
          [50, 30, 10, 5, 3, 2],
          [false, true, true, true, true, true],
        ],
        [
          [40, 40, 20],
          [true, true, true],
        ],
        [
          [0, 0],
          [false, true],
        ],
        [[], []],
        [[100], [true]],
      ],
    ),
    cases(
      "moveSource.sourceLabel",
      "Where a move came from, in a word or two; a move with none was entered by hand.",
      sourceLabel,
      [
        ...(Object.keys(SOURCE_LABELS) as MoveSource[]).map(
          (s) => [s] as [MoveSource | undefined],
        ),
        [undefined],
      ],
    ),
    cases(
      "moveSource.growthSource",
      "Growth's label for a move: Growth when the book has it, Engine past it.",
      (line: string, san: string) => growthSource(index)(after(line), san),
      [
        ["", "e4"],
        ["", "a3"],
        ["e4 e5", "Ke2"],
        [
          "e4 e5 Nf3 Nc6 Bb5 Nf6 O-O Nxe4 Re1 Nd6 Nxe5 Be7 Bf1 Nxe5 Rxe5 O-O d4 Bf6 Re2 b6",
          "Nc3",
        ],
      ],
    ),
    cases(
      "mistakes.addMistake",
      "The mistakes log: newest last, one entry per position (the latest miss there), at most 200.",
      logged,
      [
        [
          [
            ["a", "h3"],
            ["b", "a3"],
            ["a", "g3"],
            ["c", "f3"],
          ],
        ],
        [range(1, 205).map((n) => [`k${n}`, "a3"] as [string, string]), 200],
      ],
    ),
    cases(
      "mistakes.recentMistakes",
      "A repertoire's mistakes, newest first.",
      (repertoireId: string | null) =>
        recentMistakes(
          [
            { ...mistake("a", "h3"), id: "rep_w#a", at: 3 },
            {
              ...mistake("b", "h3"),
              repertoireId: "rep_b",
              id: "rep_b#b",
              at: 2,
            },
            { ...mistake("c", "h3"), id: "rep_w#c", at: 5 },
          ],
          repertoireId ?? undefined,
        ).map((m) => m.id),
      [[null], ["rep_w"], ["rep_b"]],
    ),
  ],
};

export default file;
