import {
  bookItems,
  isHead,
  lineName,
  mixLabels,
  myLines,
  nextMoves,
  recentItems,
  repMoves,
  searchItems,
  shelfRows,
  SHELVES,
  shortName,
  suggestions,
  type BrowseItem,
  type BrowseRow,
} from "../../model/browse";
import { openingTree } from "../../model/openingTree";
import { nameLevels, pickerCatalog, sideForPick } from "../../model/picker";
import { referenceIndex } from "../../model/referenceIndex";
import { addLine, createRepertoire } from "../../model/repertoire";
import {
  EMPTY_SCORE,
  emptyNodeStats,
  type ScoreState,
} from "../../model/scoring";
import type { Repertoire } from "../../model/types";
import { cases, type CaseFile } from "../caseKit";

const index = referenceIndex();
const tree = openingTree(index);
const catalog = pickerCatalog(tree);
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

const PLAYBOOKS: Record<string, Repertoire[]> = {
  empty: [],
  "e4 player": [
    rep("w", [
      "e4 e5 Nf3 Nc6 Bb5 a6 Ba4",
      "e4 c5 Nf3 d6 d4 cxd4 Nxd4",
      "e4 e6 d4 d5 Nc3",
    ]),
    rep("b", [
      "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6",
      "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5",
      "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6",
    ]),
  ],
  "d4 player": [
    rep("w", [
      "d4 d5 c4 e6 Nc3 Nf6 Bg5",
      "d4 d5 c4 c6 Nf3 Nf6 Nc3",
      "d4 Nf6 c4 e6 Nc3 Bb4 Qc2",
    ]),
    rep("b", ["e4 c6 d4 d5 e5 Bf5", "e4 c6 d4 d5 Nc3 dxe4 Nxe4 Bf5"]),
  ],
};
const BOOKS = Object.keys(PLAYBOOKS);

/** A list as rows, opened to a depth: heads as "# Head", rows as "label [side] moves", children indented. */
function written(items: BrowseItem[], depth = 1, indent = ""): string[] {
  const out: string[] = [];
  for (const item of items) {
    if (isHead(item)) {
      out.push(`${indent}# ${item.head}`);
      continue;
    }
    out.push(`${indent}${row(item)}`);
    if (depth > 0 && item.open)
      out.push(...written(item.open(), depth - 1, `${indent}  `));
  }
  return out;
}
const row = (r: BrowseRow) =>
  `${r.label} [${r.side}] ${r.sans.join(" ")}${r.why ? ` (${r.why.kind}: ${r.why.text})` : ""}${r.open ? " ›" : ""}`;

const file: CaseFile = {
  area: "picker",
  functions: [
    cases(
      "picker.entry",
      "Every opening the picker lists, built from the book: its label, level (family, branch, line), side, sharpness (hand-rated), difficulty (1 to 5, ranked by how many lines you would need to know, among its level), games, whether the book names it on its own, and how many entries sit under it.",
      (key: string) => {
        const e = catalog.byKey.get(key)!;
        return {
          label: e.label,
          level: e.level,
          side: e.side,
          sharpness: e.sharpness,
          difficulty: e.difficulty,
          games: e.games,
          node: e.node.id,
          exact: e.exact,
          children: e.children.length,
        };
      },
      [...catalog.byKey.keys()].sort().map((k) => [k] as [string]),
    ),
    cases(
      "picker.family",
      "Each family: its first move, and for the big ones the hand-made groups (with the position that defines each, the entries in it, and the other groups an entry can also be reached by).",
      (name: string) => {
        const f = catalog.familyByName.get(name)!;
        return {
          firstMove: f.firstMove,
          groups:
            f.groups?.map((g) => ({
              label: g.label,
              node: g.node?.id ?? null,
              sharpness: g.sharpness,
              entries: g.entries.map((e) => e.label),
              alsoVia: Object.fromEntries(g.alsoVia),
            })) ?? null,
        };
      },
      catalog.families.map((f) => [f.entry.key] as [string]).sort(),
    ),
    cases(
      "picker.nameLevels",
      "A book name as the keys of every level it names, shallowest first; a name with no colon is a family on its own.",
      nameLevels,
      [
        [
          "Sicilian Defence",
          "Sicilian Defence: Najdorf Variation, English Attack",
        ],
        ["Sicilian Defence", "Sicilian Defence"],
        [
          "Queen's Gambit Declined",
          "Queen's Gambit Declined: Exchange Variation, Positional Variation",
        ],
        ["King's Indian Attack, with e6", "King's Indian Attack, with e6"],
      ],
    ),
    cases(
      "picker.sideForPick",
      "The side a pick sets: the entry's side, or for an unlisted line, the side whose opening it is.",
      (id: string) => sideForPick(catalog, tree.byId.get(id) ?? tree.root),
      [
        "",
        "e4",
        "e4 c5",
        "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3",
        "e4 c5 Nf3 e6 d4 cxd4 Nxd4 Nc6",
        "d4 Nf6 c4 g6 Nc3",
        "c4",
      ].map((id) => [id] as [string]),
    ),
    cases(
      "browse.shortName",
      'A name without the word every opening has: "Najdorf" for "Najdorf Variation".',
      shortName,
      [
        "Najdorf Variation",
        "Sicilian Defence",
        "Ruy Lopez",
        "Italian Game",
        "English Opening",
        "Variation",
      ].map((s) => [s] as [string]),
    ),
    cases(
      "browse.lineName",
      "The name a line shows under in the picker: family and its deepest named entry, short.",
      (line: string) => lineName(tree, catalog, split(line)),
      [
        "",
        "e4",
        "e4 c5",
        "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6",
        "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5 Nb3 Be6 f3",
        "d4 d5 c4 c6 Nf3 Nf6 Nc3 dxc4 a4 Bf5",
        "a3 a6 b3",
      ].map((l) => [l] as [string]),
    ),
    cases(
      "browse.bookItems",
      "Browse's Book list: every family under 1.e4, 1.d4 and Flank openings, most played first, each opened one level (groups, or its branches).",
      () => written(bookItems(catalog)),
      [[]],
    ),
    cases(
      "browse.shelfRows",
      "Each shelf's openings, as rows; names the book no longer has are left out.",
      (id: string) =>
        written(shelfRows(catalog, SHELVES.find((s) => s.id === id)!), 0),
      SHELVES.map((s) => [s.id] as [string]),
    ),
    cases(
      "browse.myLines",
      "My lines: each side, then your openings (favorites first), their variations, and the lines of an opening with none.",
      (book: string, favorites: string[]) =>
        written(myLines(PLAYBOOKS[book], index, tree, favorites), 2),
      [
        ["empty", []],
        ["e4 player", []],
        ["e4 player", ["d4 Nf6 c4 g6 Nc3"]],
        ["d4 player", []],
      ],
    ),
    cases(
      "browse.recentItems",
      "Recent: the openings you played lately, newest first, under Today, This week and Earlier.",
      (played: [string, number][]) => {
        const now = new Date(2026, 9, 31, 18).getTime();
        const score: ScoreState = {
          ...EMPTY_SCORE,
          nodes: Object.fromEntries(
            played.map(([id, hoursAgo]) => [
              id,
              { ...emptyNodeStats(), lastAt: now - hoursAgo * 3_600_000 },
            ]),
          ),
        };
        return written(recentItems(tree, catalog, score, now), 0);
      },
      [
        [[]],
        [
          [
            ["e4 c5", 1],
            ["d4 Nf6 c4 g6 Nc3", 30],
            ["e4 e5 Nf3 Nc6 Bb5", 200],
            ["c4", 3],
            ["not an opening", 2],
          ],
        ],
      ],
    ),
    cases(
      "browse.searchItems",
      "Search by name, ECO, moves or initials: your own lines first, then the book, shallowest and most played first.",
      (query: string, book: string) =>
        written(
          searchItems(query, PLAYBOOKS[book], index, tree, catalog, 12),
          0,
        ),
      [
        ["", "e4 player"],
        ["najdorf", "e4 player"],
        ["qga", "d4 player"],
        ["B90", "empty"],
        ["e4 c6", "d4 player"],
        ["kid", "e4 player"],
        ["zzzz", "empty"],
      ],
    ),
    cases(
      "browse.nextMoves",
      "The board's Next moves list: the book's moves from a position, most played first, with their share, the name each goes to, and whether your Playbook plays it.",
      (line: string, book: string) =>
        nextMoves(
          index,
          tree,
          catalog,
          split(line),
          repMoves(PLAYBOOKS[book]),
        ).map((m) => `${m.label} ${m.share} ${m.name}${m.mine ? " *" : ""}`),
      [
        ["", "e4 player"],
        ["e4", "e4 player"],
        ["e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3", "e4 player"],
        ["d4 d5 c4", "d4 player"],
        ["a3 a6 b3 b6 c3", "empty"],
      ],
    ),
    cases(
      "browse.suggestions",
      "Suggestions: one list, each with why it is there (fills a hole, like what you play, your style), by a blended score (need + 0.6 fit + 0.35 style), never three of one reason in a row.",
      (book: string) =>
        written(suggestions(PLAYBOOKS[book], index, tree, catalog, 15), 0),
      BOOKS.map((b) => [b] as [string]),
    ),
    cases(
      "browse.mixLabels",
      "Rows dealt out best first, but never three of the same reason in a row.",
      (kinds: ("hole" | "like" | "style")[]) =>
        mixLabels(
          kinds.map((kind, i) => ({
            key: `${i}`,
            label: `${i}`,
            sans: [],
            side: "w",
            why: { kind, text: "" },
          })),
        ).map((r) => `${r.key}:${r.why!.kind}`),
      [
        [["hole", "hole", "hole", "like", "style"]],
        [["hole", "hole", "hole", "hole"]],
        [["like", "hole", "like", "like", "like", "style"]],
      ],
    ),
  ],
};

export default file;
