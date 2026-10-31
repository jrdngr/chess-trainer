import { applySan, START_FEN, type Color } from "../../chess/core";
import {
  arrowChoices,
  bookChoices,
  goals,
  shownStyles,
  stylePick,
  STYLES,
  type Style,
} from "../../model/boardBuilder";
import {
  extensionRoots,
  keptCurrent,
  layoutGraph,
  orderedKids,
} from "../../model/extensionGraph";
import { treeKinds } from "../../model/extensions";
import {
  analyseAgainstRepertoire,
  buildPlayerTree,
  measureCoverage,
} from "../../model/gameAnalysis";
import { openingTree } from "../../model/openingTree";
import { buildRepairs } from "../../model/repair";
import { referenceIndex } from "../../model/referenceIndex";
import {
  addLine,
  createRepertoire,
  nodeAtLine,
  pathTo,
} from "../../model/repertoire";
import {
  emptyNodeStats,
  EMPTY_SCORE,
  type NodeStats,
  type ScoreState,
} from "../../model/scoring";
import {
  dailyRounds,
  favouriteness,
  niceTicks,
  ratedOpenings,
  ratingOverTime,
  recentRounds,
  rollingAccuracy,
  starredOpenings,
} from "../../model/stats";
import type { ImportedGame, Repertoire } from "../../model/types";
import type { Mistake } from "../../model/mistakes";
import { cases, grid, type CaseFile } from "../caseKit";
import { pinnedClock } from "../scenarioKit";

const index = referenceIndex();
const tree = openingTree(index);
const split = (line: string) => (line ? line.split(" ") : []);
const fenOf = (line: string) =>
  split(line).reduce((f, san) => applySan(f, san)!.after, START_FEN);
const AT = Date.parse("2026-10-01T09:00:00Z");

function rep(
  color: Color,
  lines: string[],
  lost: Record<string, number> = {},
): Repertoire {
  let out = createRepertoire(
    color === "w" ? "White" : "Black",
    color,
    `rep_${color}`,
  );
  for (const line of lines)
    out = pinnedClock(
      () => AT,
      () => addLine(out, split(line), "seed").rep,
    );
  // Engine losses, as the Save sheet records them, on the last move of a line.
  for (const [line, cp] of Object.entries(lost)) {
    const node = nodeAtLine(out, split(line))!;
    out = { ...out, nodes: { ...out.nodes, [node.id]: { ...node, lost: cp } } };
  }
  return out;
}

const game = (
  id: string,
  moves: string,
  result: string,
  userColor: Color,
): ImportedGame => ({
  id,
  source: "lichess",
  white: userColor === "w" ? "me" : "them",
  black: userColor === "b" ? "me" : "them",
  result,
  userColor,
  date: "2026-09-01",
  moves: split(moves),
});

/** Black games: the Najdorf prepared; English Attack, a slip at move 6, and an unprepared 2.c3. */
const GAMES: ImportedGame[] = [
  game("g1", "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5 Nb3 Be6", "0-1", "b"),
  game("g2", "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e6 f3 b5", "1-0", "b"),
  game("g3", "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e6 g4 h6", "1-0", "b"),
  game("g4", "e4 c5 c3 Nf6 e5 Nd5 d4 cxd4", "1/2-1/2", "b"),
  game("g5", "e4 c5 c3 Nf6 e5 Nd5 Nf3 Nc6", "1-0", "b"),
  game("g6", "e4 c5 c3 d5 exd5 Qxd5 d4 Nf6", "0-1", "b"),
  game("g7", "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6", "1-0", "b"),
  game("g8", "d4 Nf6 c4 g6 Nc3 Bg7 e4 O-O", "1-0", "b"),
  game("g9", "e4 e5 Nf3 Nc6 Bb5 a6", "1-0", "w"),
];
const BLACK = rep("b", [
  "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5 Nb3 Be6",
  "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O",
]);

const mistake = (
  line: string,
  played: string,
  expected: string,
  at: number,
): Mistake => ({
  id: "",
  at,
  source: "drill",
  repertoireId: BLACK.id,
  key: "",
  fen: fenOf(line),
  path: split(line),
  played,
  expected,
});

/** One opening's per-day stats: [day, rounds, answered, correct, rating or null]. */
function stats(
  days: [string, number, number, number, number | null][],
  rating = 0,
): NodeStats {
  return {
    ...emptyNodeStats(),
    rating,
    rated: days.some((d) => d[4] !== null) ? 20 : 0,
    days: Object.fromEntries(
      days.map(([k, rounds, answered, correct, r]) => [
        k,
        { rounds, answered, correct, rating: r },
      ]),
    ),
  };
}
const noon = (key: string) => {
  const [y, m, d] = key.split("-").map(Number);
  return new Date(y, m - 1, d, 12).getTime();
};
const HISTORY = stats(
  [
    ["2026-10-20", 2, 10, 8, 120],
    ["2026-10-22", 1, 6, 3, 110],
    ["2026-10-25", 3, 14, 12, 160],
    ["2026-10-29", 1, 5, 5, null],
    ["2026-10-30", 2, 9, 6, 175],
  ],
  175,
);

const SCORE: ScoreState = {
  ...EMPTY_SCORE,
  nodes: {
    "e4 c5": stats([["2026-10-30", 5, 20, 15, 300]], 300),
    "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6": stats(
      [["2026-10-30", 3, 12, 10, 420]],
      420,
    ),
    "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6": stats(
      [["2026-10-28", 1, 5, 2, 90]],
      90,
    ),
    "e4 c5 Nf3 Nc6": stats([["2026-09-01", 4, 12, 9, 200]], 200),
    "d4 Nf6 c4 g6 Nc3": stats([["2026-10-29", 2, 8, 6, 260]], 260),
  },
};

const EXT = rep(
  "b",
  [
    "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5 Nb3 Be6",
    "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 h5",
    "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Bg5 e6 f4 Qb6",
    "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Bg5 Nbd7",
    "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 h3 e5 Nde2 h5 g3 h4",
    "e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 Nf6 Nc3 d6 Bg5 Qa5",
  ],
  { "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Bg5 Nbd7": 120 },
);

const file: CaseFile = {
  area: "tools",
  functions: [
    cases(
      "gameAnalysis.buildPlayerTree",
      "Your games as a tree of the positions you reached (first 24 plies), with how often, your results, and what you chose at your turns.",
      (color: Color) => {
        const t = buildPlayerTree(GAMES, color);
        return {
          games: t.games,
          positions: [...t.nodes.values()]
            .filter((n) => n.games >= 2)
            .map(
              (n) =>
                `${n.path.join(" ")} ${n.games}g ${n.wins}/${n.draws}/${n.losses}${n.choices.size ? ` [${[...n.choices].map(([s, c]) => `${s}:${c}`).join(" ")}]` : ""}`,
            ),
        };
      },
      [["b"], ["w"]],
    ),
    cases(
      "gameAnalysis.analyseAgainstRepertoire",
      "Your games against your Playbook: gaps (reached at least twice with nothing prepared), deviations (you played something other than your prep), and prepared lines that never came up.",
      (minGames: number) =>
        analyseAgainstRepertoire(buildPlayerTree(GAMES, "b"), BLACK, {
          minGames,
        }).map(
          (f) =>
            `${f.kind} ${f.path.join(" ")} games ${f.games} played ${f.played.map((p) => `${p.san}:${p.count}`).join(",")} expected ${f.expected.join(",")}`,
        ),
      [[1], [2]],
    ),
    cases(
      "gameAnalysis.measureCoverage",
      "How long your games stayed in your prep: games in prep for at least 6 plies, the rest, and the average ply they left it.",
      (color: Color) =>
        measureCoverage(
          GAMES.filter((g) => g.userColor === color),
          color === "b" ? BLACK : rep("w", ["e4 e5 Nf3 Nc6 Bc4"]),
        ),
      [["b"], ["w"]],
    ),
    cases(
      "repair.buildRepairs",
      "Positions your games or your mistakes log say you got wrong: off prep (you had a move and played another) and unprepared (reached at least twice with nothing), never your first move of the game; weighted by games, off prep 1.5×, and what they cost you. A logged mistake counts as an off-prep position seen in a couple of games unless your games already have it. Autopilot counts every off-prep one as due (AUTO-18).",
      (withMistakes: boolean) =>
        buildRepairs(GAMES, [BLACK], {
          mistakes: withMistakes
            ? [
                mistake("d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3", "c5", "O-O", AT),
                mistake(
                  "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3",
                  "e6",
                  "e5",
                  AT + 1,
                ),
              ].map((m) => ({
                ...m,
                key: m.fen.split(" ").slice(0, 4).join(" "),
                id: `${m.repertoireId}#x`,
              }))
            : [],
        }).map(
          (r) =>
            `${r.kind} ${r.source} ${r.path.join(" ")} games ${r.games} played ${r.played.map((p) => p.san).join(",")} expected ${r.expected.join(",")} weight ${r.weight.toFixed(2)}`,
        ),
      [[false], [true]],
    ),
    cases(
      "stats.series",
      "The Stats charts for one opening over a window: rounds a day, the rating at each day's end (held through days it did not move), and accuracy over the 7 days ending each day (days with nothing left out).",
      (days: number, today: string) => ({
        rounds: dailyRounds(HISTORY, days, noon(today)).map(
          (p) => `${p.key}:${p.value}`,
        ),
        rating: ratingOverTime(HISTORY, days, noon(today)).map(
          (p) => `${p.value}`,
        ),
        accuracy: rollingAccuracy(HISTORY, days, noon(today)).map(
          (p) => `${p.value.toFixed(3)}`,
        ),
        recent: recentRounds(HISTORY, days, noon(today)),
      }),
      [
        [7, "2026-10-31"],
        [14, "2026-10-31"],
        [30, "2026-10-31"],
      ],
    ),
    cases(
      "stats.favouriteness",
      'How an opening ranks among its siblings by rounds in the last 30 days, "your second favorite Sicilian"; siblings never played are left out.',
      (id: string) => {
        const f = favouriteness(tree, SCORE, id, 30, noon("2026-10-31"));
        return (
          f && {
            rank: f.rank,
            of: f.of,
            parent: f.parent?.id ?? null,
            siblings: f.siblings.map((s) => `${s.node.id}:${s.rounds}`),
          }
        );
      },
      [
        ["e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6"],
        ["e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6"],
        ["e4 c5"],
        ["e4 e5"],
      ],
    ),
    cases(
      "stats.ladders",
      "Stats' two ladders: your favorites, best rated first, unrated ones kept at the bottom; and every other opening Survival has rated, best first.",
      (starred: string[]) => ({
        favorites: starredOpenings(tree, SCORE, starred).map((r) => r.node.id),
        rated: ratedOpenings(tree, SCORE, starred).map((r) => r.node.id),
      }),
      [[[]], [["e4 c5", "e4 e5 Nf3 Nc6 Bb5", "d4 Nf6 c4 g6 Nc3"]]],
    ),
    cases(
      "stats.niceTicks",
      "Round chart ticks up to a maximum.",
      niceTicks,
      [[0], [1], [4], [7], [12], [37], [100], [433]].map(
        ([n]) => [n] as [number],
      ),
    ),
    cases(
      "extensionGraph.layoutGraph",
      "The Extensions review's graph of one opening: columns are half-moves, rows go depth first, your move first then book moves, rare, mistakes; their replies by share; a move into a position drawn higher up ends in a join; past 16 plies a +N cell. The Extensions filter keeps only paths to an extension.",
      (extOnly: boolean) => {
        const kinds = treeKinds(EXT, index);
        const root = nodeAtLine(EXT, ["e4"])!;
        return layoutGraph(EXT, index, kinds, root.id, { extOnly }).map(
          (row) =>
            `${row.parent ? `${row.parent.row}.${row.parent.col}` : "-"} @${row.start}: ${row.cells
              .map((c) =>
                c.kind === "book"
                  ? c.label
                  : `${c.label}(${c.kind}${c.joinRow !== undefined ? ` ${c.joinRow}` : ""})`,
              )
              .join(" ")}`,
        );
      },
      [[false], [true]],
    ),
    cases(
      "extensionGraph.extensionRoots",
      "Every extension's first move off the book, top of the tree first: what Keep and Remove act on.",
      () => {
        const kinds = treeKinds(EXT, index);
        return extensionRoots(EXT, kinds).map(
          (n) =>
            `${pathTo(EXT, n.id)
              .map((m) => m.san)
              .join(" ")} (${kinds.get(n.id)})`,
        );
      },
      [[]],
    ),
    cases(
      "extensionGraph.orderedKids",
      "A position's moves in the order the graph draws them.",
      (line: string) => {
        const kinds = treeKinds(EXT, index);
        return orderedKids(
          EXT,
          index,
          kinds,
          nodeAtLine(EXT, split(line))!.id,
        ).map((n) => n.san);
      },
      [
        ["e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6"],
        ["e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3"],
        ["e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Bg5"],
        ["e4 c5"],
      ],
    ),
    cases(
      "extensionGraph.keptCurrent",
      "A kept extension stays reviewed until a move under it is added after the keep.",
      (keptAt: number | null, addedLater: number) => {
        const root = nodeAtLine(
          EXT,
          split("e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Bg5 Nbd7"),
        )!;
        const nodes = Object.fromEntries(
          Object.entries(EXT.nodes).map(([id, n]) => [
            id,
            { ...n, addedAt: 100 },
          ]),
        );
        nodes[root.id] = {
          ...nodes[root.id],
          keptAt: keptAt ?? undefined,
          addedAt: addedLater,
        };
        const r = { ...EXT, nodes };
        return keptCurrent(r, r.nodes[root.id]);
      },
      [
        [null, 100],
        [200, 100],
        [200, 300],
        [50, 100],
      ],
    ),
    cases(
      "boardBuilder.bookChoices",
      "Play on the board's choices: the book's moves at 5% or more, most played first.",
      (line: string) =>
        bookChoices(index, fenOf(line)).map(
          (c) => `${c.san} ${c.share.toFixed(3)}`,
        ),
      [
        [""],
        ["e4"],
        ["d4 Nf6 c4 g6"],
        [
          "e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7 Re1 b5 Bb3 d6 c3 O-O h3 Nb8 d4 Nbd7 c4 c6 cxb5 axb5",
        ],
      ],
    ),
    cases(
      "boardBuilder.stylePick",
      "The move each style highlights among the book moves (Popular, Solid, Attack, Gambit, Fianchetto), or none when nothing fits; most played breaks ties. A style is shown when it would pick a different move, or is the one picked.",
      (line: string) => {
        const choices = bookChoices(index, fenOf(line));
        const picks = Object.fromEntries(
          STYLES.map((s) => [
            s.id,
            stylePick(index, tree, split(line), choices, s.id),
          ]),
        ) as Record<Style, string | null>;
        return {
          picks,
          shown: shownStyles(picks, "popular"),
          arrows: arrowChoices(choices, picks.gambit ?? picks.fianchetto).map(
            (c) => c.san,
          ),
        };
      },
      [
        [""],
        ["e4"],
        ["e4 e5"],
        ["e4 e5 Nf3 Nc6"],
        ["d4"],
        ["d4 d5"],
        ["e4 c5"],
        ["d4 Nf6 c4"],
      ],
    ),
    cases(
      "boardBuilder.goals",
      "The opening's three jobs for a side, read off the position: minor pieces still at home, castled or not, center pawns against the other side's.",
      (line: string, color: Color) =>
        goals(fenOf(line), color).map((g) => `${g.label}: ${g.value}`),
      grid(
        [
          "",
          "e4 e5 Nf3 Nc6 Bc4 Bc5 O-O Nf6 d3",
          "d4 d5 c4 dxc4 e4 e5 Nf3 exd4 Bxc4 Nc6 O-O Be6",
        ],
        ["w", "b"] as Color[],
      ),
    ),
  ],
};

export default file;
