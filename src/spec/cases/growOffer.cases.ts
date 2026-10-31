import {
  growOfferAt,
  offerOpening,
  practiceCap,
  practiceOwed,
  practiceText,
  readyToGrow,
} from "../../model/growOffer";
import { nodeById, openingTree } from "../../model/openingTree";
import { referenceIndex } from "../../model/referenceIndex";
import { addLine, createRepertoire } from "../../model/repertoire";
import type { RoundRecord } from "../../model/scoring";
import type { Repertoire } from "../../model/types";
import { cases, grid, range, type CaseFile } from "../caseKit";

const index = referenceIndex();
const tree = openingTree(index);
const ADDED = Date.parse("2026-09-01T09:00:00Z");
const GROWTH = { minShare: 1, maxPly: 18 };

/**
 * An end of prep, as data: your prep (every move added on one day), the
 * opening the offer is about, the line to where the prep ran out, and how
 * many clean finishes each of your lines in the opening has had since.
 */
interface End {
  color: "w" | "b";
  lines: string[];
  opening: string;
  played: string;
  finishes: number;
  stub?: boolean;
}

function rep(color: "w" | "b", lines: string[]): Repertoire {
  let out = createRepertoire(
    color === "w" ? "White" : "Black",
    color,
    `rep_${color}`,
  );
  for (const line of lines) out = addLine(out, line.split(" "), "seed").rep;
  for (const node of Object.values(out.nodes)) node.addedAt = ADDED;
  return out;
}

/** `finishes` clean rounds of every line, a day apart after the prep was added. */
function rounds(end: End): RoundRecord[] {
  return end.lines.flatMap((line, l) =>
    range(1, end.finishes).map((n) => ({
      mode: "survival" as const,
      openingId: end.opening,
      color: end.color,
      answered: 4,
      correct: 4,
      perfect: true,
      line: line.split(" "),
      at: ADDED + n * 86_400_000 + l,
    })),
  );
}

/** Repertoire node ids are made up per session, so the offer is written without them. */
const noIds = (value: unknown) =>
  JSON.parse(
    JSON.stringify(value ?? null, (key, v) =>
      key === "nodeId"
        ? undefined
        : key === "opening" && v && typeof v === "object"
          ? v.id
          : v,
    ),
  );

function offer(end: End) {
  return noIds(
    growOfferAt({
      rep: rep(end.color, end.lines),
      index,
      tree,
      opening: nodeById(tree, end.opening),
      played: end.played.split(" "),
      rounds: rounds(end),
      growth: GROWTH,
      starred: [],
      stub: end.stub,
    }),
  );
}

const KID = "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6";
const ITALIAN = "e4 e5 Nf3 Nc6 Bc4 Bc5";
const ENDS: [End][] = [
  // A reply your prep has no answer to: grow this line, right here.
  [
    {
      color: "b",
      lines: [KID],
      opening: "d4 Nf6 c4 g6",
      played: `${KID} Nf3`,
      finishes: 0,
    },
  ],
  // Ended on your own last move, theirs still to come.
  [
    {
      color: "b",
      lines: [KID],
      opening: "d4 Nf6 c4 g6",
      played: KID,
      finishes: 0,
    },
  ],
  // Every line finished clean three times: the opening is offered, with why.
  [
    {
      color: "b",
      lines: [KID],
      opening: "d4 Nf6 c4 g6",
      played: KID,
      finishes: 3,
    },
  ],
  [
    {
      color: "b",
      lines: [KID],
      opening: "d4 Nf6 c4 g6",
      played: KID,
      finishes: 2,
    },
  ],
  [
    {
      color: "w",
      lines: [ITALIAN, "e4 e5 Nf3 Nc6 Bc4 Nf6 d3"],
      opening: "e4 e5 Nf3 Nc6 Bc4",
      played: ITALIAN,
      finishes: 3,
    },
  ],
  // A stub: the opening saved as its own moves, which asked nothing.
  [
    {
      color: "w",
      lines: ["e4 e5 Nf3 Nc6 Bc4"],
      opening: "e4 e5 Nf3 Nc6 Bc4",
      played: "e4 e5 Nf3 Nc6 Bc4",
      finishes: 0,
      stub: true,
    },
  ],
  [
    {
      color: "b",
      lines: ["d4 Nf6 c4 g6"],
      opening: "d4 Nf6 c4 g6",
      played: "d4 Nf6 c4 g6",
      finishes: 0,
      stub: true,
    },
  ],
];

const file: CaseFile = {
  area: "growOffer",
  functions: [
    cases(
      "growOffer.growOfferAt",
      "What a clean end of prep offers: the opening, once every line is finished clean (or a stub), else Grow this line where the prep ran out; null with nowhere to grow. Each end is given as data (see `End` in the case file).",
      offer,
      ENDS,
    ),
    cases(
      "growOffer.readyToGrow",
      "Every line in the opening finished clean three times since it last changed.",
      (end: End) =>
        readyToGrow(
          rep(end.color, end.lines),
          tree,
          nodeById(tree, end.opening),
          rounds(end),
        ),
      ENDS,
    ),
    cases(
      "growOffer.practiceOwed",
      "An opening’s lines, how many are short of three clean finishes, and the cap.",
      (end: End) =>
        practiceOwed(
          rep(end.color, end.lines),
          tree,
          nodeById(tree, end.opening),
          rounds(end),
        ),
      ENDS,
    ),
    cases(
      "growOffer.practiceCap",
      "How many unpracticed lines an opening may carry before Growth points back.",
      practiceCap,
      range(0, 14).map((n) => [n] as [number]),
    ),
    cases(
      "growOffer.practiceText",
      "What Growth's card says an opening is owed.",
      practiceText,
      grid(["King's Indian Defence"], [0, 1, 2, 5]),
    ),
    cases(
      "growOffer.offerOpening",
      "The opening an offer is about: the one the round started inside, or the selection, or the family a round from move one ended in.",
      (region: string, entered: string | null, played: string) =>
        offerOpening(
          tree,
          nodeById(tree, region),
          entered === null ? null : nodeById(tree, entered),
          played.split(" "),
        ).id,
      [
        ["", null, KID],
        ["", null, `${KID} Nf3 O-O Be2 e5`],
        ["", "d4 Nf6 c4 g6", KID],
        ["d4 Nf6 c4 g6", null, KID],
        ["", null, ITALIAN],
        ["e4", null, ITALIAN],
      ],
    ),
  ],
};

export default file;
