import { positionKey, sansToMoveText, START_FEN } from "../../chess/core";
import {
  ancestorsOf,
  deepestNodeAlong,
  deepestNodeWithin,
  lineStatus,
  moveLabel,
  nodeById,
  openingTree,
} from "../../model/openingTree";
import {
  deepestName,
  familyName,
  formatGameCount,
  namesAlong,
} from "../../model/reference";
import { referenceIndex } from "../../model/referenceIndex";
import { cases, grid, type CaseFile } from "../caseKit";

const index = referenceIndex();
const tree = openingTree(index);
const split = (line: string) => (line ? line.split(" ") : []);

const LINES = [
  "",
  "e4",
  "e4 c5",
  "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6",
  "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5 Nb3 Be6 f3",
  "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f3",
  "d4 Nf6 c4 g6 Nf3 Bg7 g3 O-O Bg2 d6 O-O",
  "c4 e6 d4 Nf6 Nc3",
  "Nf3 d5 g3",
  "e4 d6 d4 Nf6 Nc3 g6",
  "a3 a6 b3",
];

/** Regions the line cases are read against. */
const REGIONS = [
  "",
  "e4",
  "e4 c5",
  "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6",
  "d4 Nf6 c4 g6",
  "d4 Nf6 c4 e6 Nc3",
].filter((id) => tree.byId.has(id));

const NAMES = [
  "Sicilian Defence: Najdorf Variation",
  "Sicilian Defence",
  "King's Indian Defence: Sämisch Variation",
  "Indian Defence: West Indian Defence",
  "Queen's Gambit Declined",
  "Torre Attack",
  "Not a name in the book",
];

const file: CaseFile = {
  area: "naming",
  functions: [
    cases(
      "core.positionKey",
      "A position's key: the board, side to move, castling and en passant, without the move counters, so transpositions meet.",
      positionKey,
      [
        [START_FEN],
        ["rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2"],
        ["rnbqkb1r/pppp1ppp/5n2/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3"],
      ],
    ),
    cases(
      "core.sansToMoveText",
      "A line written out with move numbers.",
      (line: string) => sansToMoveText(split(line)),
      LINES.map((l) => [l] as [string]),
    ),
    cases(
      "openingTree.moveLabel",
      'A move named after itself: "1.e4", "1...c5".',
      (line: string) => moveLabel(split(line)),
      LINES.filter(Boolean).map((l) => [l] as [string]),
    ),
    cases(
      "reference.deepestName",
      "The deepest name the book gives along a line, and the ply it was given at.",
      (line: string) => deepestName(index, split(line)),
      LINES.map((l) => [l] as [string]),
    ),
    cases(
      "reference.namesAlong",
      "Every name the book gives along a line, shallowest first.",
      (line: string) => namesAlong(index, split(line)),
      LINES.map((l) => [l] as [string]),
    ),
    cases(
      "reference.familyName",
      "The family a name belongs to.",
      (name: string) => familyName(index, name),
      NAMES.map((n) => [n] as [string]),
    ),
    cases(
      "reference.formatGameCount",
      "A game count, short.",
      formatGameCount,
      [
        0, 1, 999, 1000, 1049, 1050, 9999, 10_000, 99_499, 999_999, 1_000_000,
        1_250_000, 9_990_000, 10_000_000, 133_005_000,
      ].map((n) => [n] as [number]),
    ),
    cases(
      "openingTree.deepestNodeAlong",
      "The deepest opening a line goes through: what it is called and where its score goes.",
      (line: string) => deepestNodeAlong(tree, split(line))?.id ?? null,
      LINES.map((l) => [l] as [string]),
    ),
    cases(
      "openingTree.deepestNodeWithin",
      "The deepest opening inside a region that a line goes through, else the region.",
      (region: string, line: string) =>
        deepestNodeWithin(tree, nodeById(tree, region), split(line)).id,
      grid(REGIONS, LINES),
    ),
    cases(
      "openingTree.lineStatus",
      "Whether a line is inside a region, on its way in, or outside it.",
      (region: string, line: string) =>
        lineStatus(tree, nodeById(tree, region), split(line)),
      grid(REGIONS, LINES),
    ),
    cases(
      "openingTree.ancestorsOf",
      "An opening and every one above it, shallowest first.",
      (id: string) => ancestorsOf(tree, id).map((node) => node.id),
      REGIONS.map((id) => [id] as [string]),
    ),
    cases(
      "openingTree.nodeById",
      "A selection by its moves: a catalogue opening; a legal line the catalogue lacks, as a custom opening under the deepest one it passes; anything else, Any opening.",
      (id: string) => {
        const node = nodeById(tree, id);
        return {
          id: node.id,
          name: node.name,
          parentId: node.parentId,
          depth: node.depth,
          custom: node.custom ?? false,
        };
      },
      [
        [""],
        ["e4 c5"],
        ["e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 h3"],
        ["d4 d5 c4 c6 Nf3 Nf6 Nc3"],
        ["a3 a6 b3"],
        ["e4 e4"],
        ["not a line"],
      ],
    ),
    cases(
      "openingTree.node",
      "Every opening in the catalogue, built from the book: its name, ECO, parent, depth, games and how many openings sit directly under it.",
      (id: string) => {
        const node = nodeById(tree, id);
        return {
          name: node.name,
          eco: node.eco ?? null,
          parentId: node.parentId,
          depth: node.depth,
          games: node.games,
          children: node.children.length,
        };
      },
      [...tree.byId.keys()].sort().map((id) => [id] as [string]),
    ),
  ],
};

export default file;
