import { playerOf, selectionFor } from "../../model/onboarding";
import { familiesIn } from "../../model/openings";
import { nodeById, openingTree } from "../../model/openingTree";
import { referenceIndex } from "../../model/referenceIndex";
import { leafLines, pathTo } from "../../model/repertoire";
import { DEFAULT_SELECTION } from "../../model/selection";
import {
  countOwnMoves,
  seedFor,
  setOpenings,
  STARTER_SETS,
  type SeedOpening,
} from "../../model/starterSets";
import type { Repertoire } from "../../model/types";
import {
  DEFAULT_SETTINGS,
  onboarded,
  repertoireList,
  type OnboardingLine,
} from "../../store/useStore";
import { cases, type CaseFile } from "../caseKit";
import { pinnedClock } from "../scenarioKit";

const index = referenceIndex();
const tree = openingTree(index);
const AT = Date.parse("2026-10-01T09:00:00Z");
const split = (line: string) => (line ? line.split(" ") : []);

/** A profile as it comes out of a fresh install. */
const FRESH = {
  repertoires: {},
  repertoireOrder: [],
  events: [],
  settings: {
    ...DEFAULT_SETTINGS,
    favoriteOpenings: [],
    selection: { ...DEFAULT_SELECTION },
  },
};

/** A Playbook without node ids: each side's lines, where each move came from, and what the Playbook lists. */
function written(rep: Repertoire) {
  return {
    color: rep.color,
    name: rep.name,
    lines: leafLines(rep).map((line) =>
      pathTo(rep, line.tipId)
        .map((move) => (move.source ? `${move.san}(${move.source})` : move.san))
        .join(" "),
    ),
    openings: familiesIn(rep, index).map((o) => o.name),
  };
}

/** What finishing onboarding with these openings and board lines puts in. */
function finish(openings: SeedOpening[], board: OnboardingLine[] = []) {
  const out = pinnedClock(
    () => AT,
    () => onboarded(FRESH, openings, board),
  );
  return {
    playbook: repertoireList(out).map(written),
    favorites: out.settings.favoriteOpenings,
    selection: out.settings.selection,
    onboarded: out.settings.onboarded,
    events: out.events.map((e) => {
      const { at: _at, repertoireId: _id, ...rest } = e as unknown as Record<
        string,
        unknown
      >;
      return rest;
    }),
  };
}

const setSeeds = (id: string) =>
  setOpenings(STARTER_SETS.find((set) => set.id === id)!).map(
    ({ id, color }) => ({ sans: split(id), color }),
  );

const file: CaseFile = {
  area: "onboarding",
  functions: [
    cases(
      "onboarding.playerOf",
      "Whose opening a line is: whoever played its last move, except the two the book names a move late.",
      (line: string) => playerOf(split(line)),
      [
        "e4",
        "e4 c5",
        "e4 e5 Nf3 Nc6 Bb5",
        "d4 Nf6 c4 g6 Nc3",
        "d4 Nf6 c4 g6 Nc3 d5",
        "e4 e5 Nf3 Nc6 d4 exd4",
        "e4 e5 Nf3 Nc6 d4",
      ].map((l) => [l] as [string]),
    ),
    cases(
      "onboarding.selectionFor",
      "The selection the picks imply: one side if all picks are one side, else random; one pick is that opening, several are Any favorite; none is the default.",
      (lines: string[]) =>
        selectionFor(
          lines.map((line) => {
            const sans = split(line);
            return {
              id: line,
              name: nodeById(tree, line).name,
              color: playerOf(sans),
              sans,
            };
          }),
        ),
      [
        [[]],
        [["e4 c5"]],
        [["e4 c5", "d4 Nf6 c4 g6 Nc3"]],
        [["e4 c5", "e4 e5 Nf3 Nc6 Bb5"]],
        [["e4 e5 Nf3 Nc6 Bb5"]],
      ],
    ),
    cases(
      "starterSets.set",
      "Each starter set: its name and description, and each slot's openings with the name shown, the side that plays it and how many of your own moves it holds.",
      (id: string) => {
        const set = STARTER_SETS.find((s) => s.id === id)!;
        return {
          name: set.name,
          description: set.description,
          openings: setOpenings(set).map((o) => ({
            slot: o.slot,
            id: o.id,
            name: o.label ?? nodeById(tree, o.id).name,
            color: o.color,
            moves: countOwnMoves([{ sans: split(o.id), color: o.color }]),
          })),
          moves: countOwnMoves(
            setOpenings(set).map((o) => ({ sans: split(o.id), color: o.color })),
          ),
        };
      },
      STARTER_SETS.map((s) => [s.id] as [string]),
    ),
    cases(
      "starterSets.countOwnMoves",
      "How many of your own moves lines hold: one per position a side answers, so shared moves and transpositions count once.",
      (lines: [string, "w" | "b"][]) =>
        countOwnMoves(lines.map(([l, color]) => ({ sans: split(l), color }))),
      [
        [[["e4 c5", "b"]]],
        [[["e4 c5", "w"]]],
        [
          [
            ["e4 e5 Nf3 Nc6 Bb5", "w"],
            ["e4 e5 Nf3 Nc6 Bc4", "w"],
          ],
        ],
        [
          [
            ["d4 Nf6 c4 e6 Nc3", "w"],
            ["c4 e6 d4 Nf6 Nc3", "w"],
          ],
        ],
        [[]],
      ],
    ),
    cases(
      "starterSets.seedFor",
      "An opening picked on its own goes to the side that plays it, unless a side is given.",
      (line: string, color: "w" | "b" | null) =>
        seedFor(split(line), color ?? undefined),
      [
        ["e4 c5", null],
        ["d4 Nf6 c4 g6 Nc3", null],
        ["e4 c5", "w"],
      ],
    ),
    cases(
      "onboarding.onboarded (a starter set)",
      "Finishing onboarding with a starter set: each opening goes in as exactly its own moves, named and starred where the book names it, with the selection it implies.",
      (id: string) => finish(setSeeds(id)),
      STARTER_SETS.map((s) => [s.id] as [string]),
    ),
    cases(
      "onboarding.onboarded",
      "Finishing onboarding: picked openings go in as their own moves and are starred; lines played on the board go in whole, marked as played on the board, and starred only through a picked opening; illegal move orders are left out; skipping puts nothing in but is still an answer.",
      (picks: string[], board: [string, "w" | "b"][]) =>
        finish(
          picks.map((line) => seedFor(split(line))),
          board.map(([line, color]) => ({ sans: split(line), color })),
        ),
      [
        [[], []],
        [["e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6"], []],
        [["e4 c5", "e4 e5 Nf3 Nc6 Bb5", "d4 Nf6 c4 g6 Nc3"], []],
        [["e4 e4 e4"], []],
        [[], [["e4 e5 Nf3 Nc6 Bc4 Bc5 c3", "w"]]],
        [
          ["e4 e5"],
          [
            ["e4 e5 Nf3 Nc6 Bb5 a6", "b"],
            ["d4 d5 c4 e6 Nc3 Nf6", "b"],
          ],
        ],
      ],
    ),
  ],
};

export default file;
