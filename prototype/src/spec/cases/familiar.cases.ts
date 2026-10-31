import { applySan, START_FEN } from "../../chess/core";
import { roleArrows } from "../../model/answerArrows";
import { movesToDraw, popularReplies } from "../../model/growth";
import { KIN_SETS, kinOf, shortFamily } from "../../model/kin";
import { DEFAULT_GROWTH } from "../../model/modes";
import {
  familiarOffBook,
  nudgeArrows,
  reachable,
  sameMove,
  type NudgePrefs,
} from "../../model/nudge";
import { openingTree } from "../../model/openingTree";
import { referenceIndex } from "../../model/referenceIndex";
import {
  addLine,
  createRepertoire,
  leafLines,
  nodeAtLine,
} from "../../model/repertoire";
import {
  findAt,
  moveLabel,
  offPrepHint,
  sortFinds,
  switchMove,
  tidyPositions,
  type TidyFind,
  type TidyOptions,
} from "../../model/tidy";
import type { Repertoire } from "../../model/types";
import { cases, grid, type CaseFile } from "../caseKit";

const index = referenceIndex();
const tree = openingTree(index);
const after = (line: string) =>
  (line ? line.split(" ") : []).reduce(
    (fen, san) => applySan(fen, san)!.after,
    START_FEN,
  );
const split = (line: string) => (line ? line.split(" ") : []);

function rep(color: "w" | "b", lines: string[]): Repertoire {
  let out = createRepertoire(
    color === "w" ? "White" : "Black",
    color,
    `rep_${color}`,
  );
  for (const line of lines) out = addLine(out, split(line), "seed").rep;
  return out;
}

/** A White Playbook of g3 systems and a Queen's Gambit; a Black one of ...e6 and ...d5. */
const TREES: Record<string, { color: "w" | "b"; lines: string[] }> = {
  white: {
    color: "w",
    lines: [
      "d4 Nf6 c4 e6 g3 d5 Bg2 Be7 Nf3",
      "d4 Nf6 c4 e6 g3 Bb4+ Bd2 Be7 Bg2",
      "c4 e5 Nc3 Nf6 g3 d5 cxd5 Nxd5 Bg2",
      "c4 c5 Nf3 Nc6 g3 g6 Bg2",
      "d4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5",
      "d4 d5 c4 c6 Nf3 Nf6 Nc3 dxc4 a4",
    ],
  },
  black: {
    color: "b",
    lines: [
      "d4 d5 c4 e6 cxd5 exd5 Nc3 Nf6 Nf3 c6",
      "d4 d5 c4 e6 Nc3 Nf6 Bg5 Be7",
      "d4 d5 c4 e6 Nf3 Nf6 g3 Be7",
      "e4 e6 d4 d5 Nc3 Nf6",
      "e4 e6 d4 d5 e5 c5",
    ],
  },
};

/** Positions you might be asked to answer at, by tree: the line to them. */
const AT: Record<string, string[]> = {
  white: [
    "e4",
    "d4 Nf6 c4 g6",
    "d4 Nf6 c4 c5",
    "d4 Nf6 c4 e6 g3 c5",
    "d4 d5 c4 dxc4",
    "c4 e6",
    "c4 Nf6",
    "Nf3 Nf6",
    "c4 g6",
  ],
  black: [
    "d4",
    "d4 d5 c4 e6 cxd5 exd5 Nc3 Nf6 Bg5",
    "d4 d5 Nf3",
    "d4 d5 c4 e6 Nc3 Nf6 cxd5",
    "d4 Nf6 c4 e6 Nc3",
    "e4 e6 d3",
    "e4 e6 d4 d5 exd5",
    "d4 d5 c4 e6 Nf3 Nf6 Bg5",
  ],
};

const PREFS: Record<string, NudgePrefs> = {
  transposition: { priority: "transposition", pawns: false },
  habit: { priority: "habit", pawns: false },
  pawns: { priority: "transposition", pawns: true },
};

const OPTS: TidyOptions = {
  prefs: PREFS.transposition,
  minShare: DEFAULT_GROWTH.minShare,
};

const atCases = (prefs: string[]) =>
  Object.entries(AT).flatMap(([t, lines]) =>
    lines.flatMap((line) =>
      prefs.map((p) => [t, line, p] as [string, string, string]),
    ),
  );

/** A Tidy find without node ids. */
const find = (f: TidyFind | null) =>
  f && {
    path: f.path.join(" "),
    mine: f.mine,
    suggestion: f.suggestion,
    kind: f.kind,
    tone: f.tone,
    offBook: f.offBook,
    reason: f.reason,
    against: f.against,
    removes: f.removes,
  };

const file: CaseFile = {
  area: "familiar",
  functions: [
    cases(
      "nudge.sameMove",
      "A habit ignores check, capture and annotation marks: Nxe5 is Ne5.",
      sameMove,
      ["Nxe5", "Bb4+", "Qxf7#", "e4!?", "O-O", "exd5"].map(
        (s) => [s] as [string],
      ),
    ),
    cases(
      "nudge.reachable",
      "Whether a game standing at one position could still arrive at another: pawns only forward (sideways only by capturing), captured pieces stay gone, lost castling stays lost.",
      (from: string, to: string) => reachable(after(from), after(to)),
      [
        ["", "e4 e5 Nf3 Nc6"],
        ["e4", "d4 d5"],
        ["d4 d5 c4 e6 cxd5", "d4 d5 c4 e6 Nc3"],
        ["e4 e5 Ke2", "e4 e5 Nf3 Nc6"],
        ["e4 e5 Nf3 Nc6", "e4 e5"],
        ["d4 d5 c4 c6", "d4 d5 c4 e6"],
        ["d4 d5 c4 e6", "d4 d5 c4 e6 Nc3 c6"],
        ["e4 d5 exd5", "e4 e5"],
      ],
    ),
    cases(
      "kin.kinOf",
      "The families whose habits count together with a family's own: the family and every kin set it is in.",
      (family: string) => [...kinOf(family)].sort(),
      [
        "English Opening",
        "Catalan Opening",
        "Queen's Gambit Declined",
        "Sicilian Defence",
        "Not a family",
      ].map((f) => [f] as [string]),
    ),
    cases(
      "kin.KIN_SETS",
      "Every kin set: openings whose habits carry across.",
      (i: number) => ({
        ...KIN_SETS[i],
        short: KIN_SETS[i].families.map(shortFamily),
      }),
      KIN_SETS.map((_, i) => [i] as [number]),
    ),
    cases(
      "nudge.nudgeArrows",
      "Growth's familiarity colors at a position: green for the most familiar move (transposes, heads toward, a habit or setup, your usual pawns, in the priority's order), put on the board in its own arrow, the same piece's, or the third; red for a drawn move that closes off your lines or that you keep passing on. Each with its reason and pill. Your first move is left plain.",
      (t: string, line: string, p: string) => {
        const fen = after(line);
        const r = rep(TREES[t].color, TREES[t].lines);
        return nudgeArrows(
          r,
          index,
          split(line),
          fen,
          movesToDraw(index, fen),
          popularReplies(index, fen, DEFAULT_GROWTH.minShare),
          PREFS[p],
          DEFAULT_GROWTH.minShare,
        ).map((m) =>
          m.tone ? `${m.san} ${m.tone} [${m.pill}] ${m.reason}` : m.san,
        );
      },
      atCases(["transposition", "habit", "pawns"]),
    ),
    cases(
      "nudge.nudgeArrows (append)",
      "As Growth calls it: a familiar move not already drawn is added alongside the others, and a familiar move the book lacks is marked not in the book.",
      (t: string, line: string) => {
        const fen = after(line);
        const r = rep(TREES[t].color, TREES[t].lines);
        const extra = familiarOffBook(
          r,
          index,
          split(line),
          fen,
          PREFS.transposition,
          DEFAULT_GROWTH.minShare,
        );
        return nudgeArrows(
          r,
          index,
          split(line),
          fen,
          movesToDraw(index, fen),
          [
            ...popularReplies(index, fen, DEFAULT_GROWTH.minShare),
            ...extra.map((san) => ({ san, share: 0 })),
          ],
          PREFS.transposition,
          DEFAULT_GROWTH.minShare,
          new Set(extra),
          true,
        ).map((m) =>
          m.tone ? `${m.san} ${m.tone} [${m.pill}] ${m.reason}` : m.san,
        );
      },
      atCases(["transposition"]).map(([t, l]) => [t, l] as [string, string]),
    ),
    cases(
      "nudge.familiarOffBook",
      "Legal moves the book leaves out or ranks under the minimum share that are familiar anyway; habitsOnly looks at habits and setups only.",
      (t: string, line: string, habitsOnly: boolean) =>
        familiarOffBook(
          rep(TREES[t].color, TREES[t].lines),
          index,
          split(line),
          after(line),
          PREFS.transposition,
          DEFAULT_GROWTH.minShare,
          { habitsOnly },
        ),
      atCases(["x"]).flatMap(([t, l]) => [
        [t, l, false] as [string, string, boolean],
        [t, l, true] as [string, string, boolean],
      ]),
    ),
    cases(
      "answerArrows.roleArrows",
      "Growth's answer arrows: blue for the move strong players choose most, then the engine's best two by eval, purple and lighter purple; when they agree the engine's next takes its place. Before the engine weighs anything only blue is drawn; past the book all three are the engine's, in the order given until weighed.",
      (
        line: string,
        deltas: Record<string, number> | null,
        pastBook: boolean,
      ) => {
        const fen = after(line);
        const listed = pastBook
          ? popularReplies(index, fen, 0).map(({ san }) => ({ san }))
          : popularReplies(index, fen, 1);
        return roleArrows(fen, listed, (san) =>
          deltas ? (deltas[san] ?? null) : null,
        ).map((a) => `${a.san} ${a.role}`);
      },
      [
        ["e4 c5", null, false],
        ["e4 c5", { Nf3: -10, Nc3: -30, c3: -5, d4: -60 }, false],
        ["e4 c5", { Nf3: -40, Nc3: -30, c3: -5 }, false],
        ["d4 d5 c4 e6", { Nc3: 0, Nf3: -3, cxd5: -20, g3: -8 }, false],
        ["e4 e5", null, true],
        ["e4 e5", { Nf3: -10, Bc4: -15, Nc3: -12 }, true],
      ],
    ),
    cases(
      "tidy.scan",
      "A Tidy scan of a whole Playbook: every position you chose at (a transposition once), each compared with the book's moves and your habits; finds with the most to remove first, then the earliest. Each find: your move, the switch, why it is familiar, why yours works against your lines, and what switching removes.",
      (t: string) => {
        const r = rep(TREES[t].color, TREES[t].lines);
        const todo = tidyPositions([r], tree, tree.root);
        return {
          positions: todo.length,
          finds: sortFinds(
            todo
              .map(({ node }) => findAt(r, index, node, OPTS))
              .filter((f): f is TidyFind => f !== null),
          ).map(find),
        };
      },
      Object.keys(TREES).map((t) => [t] as [string]),
    ),
    cases(
      "tidy.offPrepHint",
      "The end screen's hint on a miss: the move played over the board, if it is closer to the rest of your lines than your prepared move. A habit here needs no test against the times you passed it up.",
      (t: string, line: string, played: string, expected: string) =>
        find(
          offPrepHint(
            rep(TREES[t].color, TREES[t].lines),
            index,
            after(line),
            played,
            expected,
            OPTS,
          ),
        ),
      [
        ["black", "d4 d5 c4 e6 Nc3 Nf6 Bg5", "c6", "Be7"],
        ["black", "d4 d5 c4 e6 Nc3", "Be7", "Nf6"],
        ["black", "d4 d5 c4 e6 Nf3 Nf6 g3", "c6", "Be7"],
        ["black", "e4 e6 d4 d5 Nc3", "Bb4", "Nf6"],
        ["white", "d4 d5 c4 e6", "Nf3", "Nc3"],
        ["white", "c4 c5 Nf3 Nc6", "d4", "g3"],
        ["white", "c4 e5", "g3", "Nc3"],
        ["white", "e4", "e4", "d4"],
      ],
    ),
    cases(
      "tidy.switchMove",
      "Switching your move at a position: the new move becomes yours and preferred there, and the old move goes with everything under it. Null when the move is not legal.",
      (t: string, line: string, san: string) => {
        const r = rep(TREES[t].color, TREES[t].lines);
        const node = nodeAtLine(r, split(line));
        const out = node ? switchMove(r, node.id, san) : null;
        return out && leafLines(out).map((l) => l.sans.join(" "));
      },
      [
        ["white", "d4 d5 c4 e6 Nc3", "Nf3"],
        ["white", "c4 e5 Nc3", "g3"],
        ["black", "d4 d5 c4 e6 Nc3 Nf6 Bg5 Be7", "c6"],
        ["black", "e4 e6", "Ke7"],
      ],
    ),
    cases(
      "tidy.moveLabel",
      'A move with its number, from the plies before it: "6.g3", "6...Nf6".',
      moveLabel,
      grid([0, 1, 10, 11], ["g3"]),
    ),
  ],
};

export default file;
