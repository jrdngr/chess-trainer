import { applySan, START_FEN } from "../../chess/core";
import {
  favoritesIn,
  pickFavorite,
  resolveFavorite,
  ANY_FAVORITE,
} from "../../model/anyFavorite";
import {
  addsToFit,
  choicesAt,
  growthRows,
  holeShare,
  movesToFit,
  optionsAt,
  pastTheBook,
  rowUrgency,
} from "../../model/growth";
import { nodeById, openingTree } from "../../model/openingTree";
import { referenceIndex } from "../../model/referenceIndex";
import { addLine, createRepertoire } from "../../model/repertoire";
import { mulberry32 } from "../../model/session";
import {
  colorLabel,
  colorsOf,
  lineInRegion,
  type Selection,
} from "../../model/selection";
import type { Repertoire } from "../../model/types";
import { cases, grid, range, type CaseFile } from "../caseKit";

const index = referenceIndex();
const tree = openingTree(index);
const after = (line: string) =>
  line.split(" ").reduce((fen, san) => applySan(fen, san)!.after, START_FEN);

function rep(color: "w" | "b", lines: string[]): Repertoire {
  let out = createRepertoire(
    color === "w" ? "White" : "Black",
    color,
    `rep_${color}`,
  );
  for (const line of lines) out = addLine(out, line.split(" "), "seed").rep;
  return out;
}

/** Repertoire node ids are made up per session, so rows are written without them. */
const noIds = (value: unknown) =>
  JSON.parse(
    JSON.stringify(value, (key, v) => (key === "nodeId" ? undefined : v)),
  );

const PREPS: { color: "w" | "b"; lines: string[] }[] = [
  { color: "b", lines: ["d4 Nf6 c4 g6 Nc3 Bg7 e4 d6"] },
  {
    color: "b",
    lines: ["e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6", "d4 Nf6 c4 e6"],
  },
  { color: "w", lines: ["e4 e5 Nf3 Nc6 Bc4"] },
  { color: "w", lines: ["e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d3", "e4 c5 c3"] },
];
const OPTIONS = [{}, { minShare: 5 }, { maxPly: 8 }, { starred: ["e4 c5"] }];

/** Region ids the selection cases use: the root, a first move, a family and a variation. */
const regionIds = [
  "",
  "e4",
  "e4 c5",
  "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6",
  "d4 Nf6 c4 g6",
].filter((id) => tree.byId.has(id) || id === "");
const FAVORITES = [
  "e4 c5",
  "e4 e5 Nf3 Nc6 Bc4",
  "d4 Nf6 c4 g6",
  "d4 d5 c4",
].filter((id) => tree.byId.has(id));

const FENS = [
  START_FEN,
  after("e4"),
  after("e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6"),
  after("d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5"),
  after(
    "e4 e5 Nf3 Nc6 Bb5 Nf6 O-O Nxe4 Re1 Nd6 Nxe5 Be7 Bf1 Nxe5 Rxe5 O-O d4 Bf6 Re2 b6",
  ),
];

const file: CaseFile = {
  area: "growth",
  functions: [
    cases(
      "growth.holeShare",
      "How often a hole comes up, for ranking: a kept reply counts at least the prepared floor.",
      holeShare,
      grid([0.5, 3, 15, 40], [false, true]).map(
        ([share, kept]) =>
          [{ share, kept }] as [{ share: number; kept: boolean }],
      ),
    ),
    cases(
      "growth.movesToFit",
      "How many answers a hole this deep is worth: the plies left to the horizon, halved, never under one.",
      movesToFit,
      grid(range(0, 24), [8, 18]),
    ),
    cases(
      "growth.addsToFit",
      "What one batch may add from this depth, capped.",
      addsToFit,
      grid(range(0, 24), [8, 18]),
    ),
    cases(
      "growth.rowUrgency",
      "How badly a row wants doing, 0..1: depth first, then how often the reply is played, then breadth.",
      rowUrgency,
      grid([0, 1, 2, 4, 8, 14], [0, 1, 5, 20, 60], [1, 3, 8]),
    ),
    cases(
      "growth.optionsAt",
      "The book's answers at a position, best first.",
      (fen: string, limit: number) => optionsAt(index, fen, limit),
      grid(FENS, [1, 4]),
    ),
    cases(
      "growth.choicesAt",
      "The answers offered at a hole; undefined past the book while the engine works.",
      (fen: string) => choicesAt(index, fen, 4) ?? "undefined",
      FENS.map((fen) => [fen] as [string]),
    ),
    cases(
      "growth.pastTheBook",
      "Whether the book has no reply here.",
      (fen: string) => pastTheBook(index, fen),
      FENS.map((fen) => [fen] as [string]),
    ),
    cases(
      "growth.growthRows",
      "Growth's rows for a prep: each family with its holes, ranked by urgency.",
      (prep: (typeof PREPS)[number], opts: object) =>
        noIds(growthRows([rep(prep.color, prep.lines)], index, opts)),
      grid(PREPS, OPTIONS),
    ),
    cases(
      "selection.colorsOf",
      "The sides a selection covers.",
      colorsOf,
      (["w", "b", "random"] as const).map((c) => [c] as ["w" | "b" | "random"]),
    ),
    cases(
      "selection.colorLabel",
      "A side's name.",
      colorLabel,
      (["w", "b", "random"] as const).map((c) => [c] as ["w" | "b" | "random"]),
    ),
    cases(
      "selection.lineInRegion",
      "Whether a line is inside a region, or can still get there.",
      (region: string, line: string) =>
        lineInRegion(tree, nodeById(tree, region), line ? line.split(" ") : []),
      grid(regionIds, [
        "",
        "e4",
        "e4 c5",
        "e4 e5",
        "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6",
        "d4 Nf6 c4 g6 Nc3 Bg7",
        "e4 d6 d4 Nf6 Nc3 g6",
      ]),
    ),
    cases(
      "anyFavorite.favoritesIn",
      "Your favorites with the side each is played from, in the selection’s sides.",
      (ids: string[], color: Selection["color"]) =>
        favoritesIn(tree, ids, color).map((fav) => ({
          id: fav.node.id,
          side: fav.side,
        })),
      grid([FAVORITES, FAVORITES.slice(0, 1), []], [
        "w",
        "b",
        "random",
      ] as const),
    ),
    cases(
      "anyFavorite.pickFavorite",
      "The favorite a round lands on: played longest ago first, each next half as likely, never the last one while another is there.",
      (ids: string[], last: string | null, roll: number) => {
        const favorites = favoritesIn(tree, ids, "random");
        const lastAt = (id: string) => ids.indexOf(id) * 1000;
        return (
          pickFavorite(favorites, lastAt, last, () => roll)?.node.id ?? null
        );
      },
      grid(
        [FAVORITES, FAVORITES.slice(0, 1)],
        [null, FAVORITES[0]],
        [0, 0.3, 0.5, 0.6, 0.8, 0.95, 0.999],
      ),
    ),
    cases(
      "anyFavorite.resolveFavorite",
      "One round's selection under Any favorite, from a seeded picker: a side, then a favorite of it.",
      (color: Selection["color"], ids: string[], seed: number) => {
        const rand = mulberry32(seed);
        return resolveFavorite(
          tree,
          { color, opening: ANY_FAVORITE },
          ids,
          (id) => ids.indexOf(id),
          null,
          rand,
        );
      },
      grid(["w", "b", "random"] as const, [FAVORITES, []], [1, 2, 3, 4]),
    ),
  ],
};

export default file;
