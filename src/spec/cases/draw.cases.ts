import { positionKey, walkSan, type Color } from "../../chess/core";
import { autopilotModes } from "../../model/autopilotPrefs";
import {
  byDelta,
  byShare,
  deltaFor,
  deltaTone,
  formatDelta,
  whiteCp,
} from "../../model/evalDelta";
import {
  justRun,
  lineParts,
  lineStaleness,
  markSeen,
  staleness,
  type Seen,
} from "../../model/freshness";
import {
  clockLabel,
  clockSeconds,
  CLOCK_MODES,
  judgeByEval,
  lineOdds,
  lineWeakness,
  opponentReply,
  regionSource,
  resolveColor,
  wayIn,
  weaknessFromCards,
} from "../../model/openingRun";
import { nodeById, openingTree } from "../../model/openingTree";
import { referenceIndex } from "../../model/referenceIndex";
import {
  addLine,
  createRepertoire,
  leafLines,
  nodeAtLine,
} from "../../model/repertoire";
import { cardId, mulberry32 } from "../../model/session";
import { createCard } from "../../model/srs";
import { startSurvival, type SurvivalSteer } from "../../model/survival";
import type { Card, Repertoire } from "../../model/types";
import { cases, grid, range, type CaseFile } from "../caseKit";
import { pinnedClock } from "../scenarioKit";

const index = referenceIndex();
const tree = openingTree(index);
const split = (line: string) => (line ? line.split(" ") : []);
const NOW = Date.parse("2026-10-31T12:00:00Z");

function rep(color: Color, lines: string[]): Repertoire {
  let out = createRepertoire(
    color === "w" ? "White" : "Black",
    color,
    `rep_${color}`,
  );
  for (const line of lines) out = addLine(out, split(line), "seed").rep;
  return out;
}

/** Two Playbooks: one each side, branched where the opponent chooses and where you do. */
const WHITE = rep("w", [
  "e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O",
  "e4 e5 Nf3 Nc6 Bb5 Nf6 O-O",
  "e4 e5 Nf3 d6 d4",
  "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3",
  "e4 c5 Nf3 Nc6 d4 cxd4 Nxd4",
  "e4 c5 Nf3 e6 d4 cxd4 Nxd4",
  "e4 e6 d4 d5 Nc3",
  "e4 e6 d4 d5 e5",
  "e4 c6 d4 d5 e5 Bf5 Nf3",
]);
const BLACK = rep("b", [
  "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6",
  "e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 Nf6",
  "e4 c5 Nc3 Nc6",
  "e4 c5 c3 Nf6",
  "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6",
  "d4 Nf6 c4 g6 Nf3 Bg7 g3 O-O",
  "d4 Nf6 Nf3 g6",
]);
const REPS = [WHITE, BLACK];
const lineOf = (r: Repertoire, tipId: string) =>
  leafLines(r)
    .find((l) => l.tipId === tipId)!
    .sans.join(" ");

/** A Seen as of round 10, with each line last seen in the round given. */
function seenOf(rounds: [string, number][]): Seen {
  let at: Record<string, number> = {};
  for (const [line, round] of rounds) at = markSeen(at, split(line), round);
  return { at, round: 10 };
}

const node = (id: string) => nodeById(tree, id);

const file: CaseFile = {
  area: "draw",
  functions: [
    cases(
      "openingRun.lineOdds",
      "How often each of your lines comes up: where the opponent chooses, by how often strong players choose each move, with every prepared reply given at least the prepared floor; where you choose between your own moves, evenly. Lines a run cannot use are dropped before anything is split.",
      (color: Color, only: string[] | null) => {
        const r = color === "w" ? WHITE : BLACK;
        const eligible = only
          ? new Set(only.map((l) => nodeAtLine(r, split(l))!.id))
          : undefined;
        return Object.fromEntries(
          [...lineOdds(r, color, index, eligible)]
            .map(([id, p]) => [lineOf(r, id), Number(p.toFixed(4))] as const)
            .sort((a, b) => b[1] - a[1]),
        );
      },
      [
        ["w", null],
        ["b", null],
        [
          "w",
          [
            "e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O",
            "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3",
          ],
        ],
      ],
    ),
    cases(
      "survival.startSurvival (draw)",
      "The line a run is drawn on, seed by seed: the side, the line the opponent steers along, and the moves played for you when the run starts inside. My lines leans popular or weak; My gaps walks to a reply you have no answer to; Ignore my lines draws on the book alone.",
      (
        steer: SurvivalSteer,
        lean: "popular" | "weak" | null,
        color: Color | "random",
        at: string,
        enter: boolean,
      ) =>
        pinnedClock(
          () => NOW,
          () =>
            range(1, 12).map((seed) => {
              const s = startSurvival({
                steer,
                lean: lean ?? undefined,
                tree,
                reps: REPS,
                node: node(at),
                toward: node(at),
                enter,
                color,
                seed,
              })!;
              return `${s.state.run.color} [${s.state.run.played.join(" ")}] ${s.state.run.target.join(" ")}`;
            }),
        ),
      [
        ["lines", "popular", "w", "", false],
        ["lines", "popular", "b", "", false],
        ["lines", "weak", "random", "", false],
        ["lines", "popular", "w", "e4 c5", true],
        ["lines", "popular", "b", "d4 Nf6 c4 g6", true],
        ["gaps", null, "w", "e4", false],
        ["gaps", null, "b", "e4 c5", false],
        ["book", null, "w", "e4 e6", false],
      ],
    ),
    cases(
      "survival.startSurvival (shares)",
      "Over 400 seeds, how often each first reply comes up on My lines, popular: close to the line odds.",
      (color: Color, plies: number) =>
        pinnedClock(
          () => NOW,
          () => {
            const counts: Record<string, number> = {};
            for (const seed of range(1, 400)) {
              const s = startSurvival({
                steer: "lines",
                lean: "popular",
                tree,
                reps: REPS,
                node: tree.root,
                color,
                seed,
              })!;
              const k = s.state.run.target.slice(0, plies).join(" ");
              counts[k] = (counts[k] ?? 0) + 1;
            }
            return Object.fromEntries(
              Object.entries(counts).sort((a, b) => b[1] - a[1]),
            );
          },
        ),
      [
        ["w", 2],
        ["b", 1],
        ["b", 2],
      ],
    ),
    cases(
      "survival.startSurvival (fresh)",
      "The line last run is not drawn again while another is there, and the one left longest is preferred: draws over 12 seeds with the given lines seen in rounds before round 10.",
      (seen: [string, number][]) =>
        pinnedClock(
          () => NOW,
          () =>
            range(1, 12).map((seed) =>
              startSurvival({
                steer: "lines",
                lean: "popular",
                tree,
                reps: REPS,
                node: node("e4 e5"),
                color: "w",
                seed,
                seen: seenOf(seen),
              })!.state.run.target.join(" "),
            ),
        ),
      [
        [[]],
        [[["e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O", 10]]],
        [
          [
            ["e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O", 10],
            ["e4 e5 Nf3 Nc6 Bb5 Nf6 O-O", 9],
          ],
        ],
      ],
    ),
    cases(
      "openingRun.opponentReply",
      "Off the drawn line, the opponent replies by weight, among replies that keep the run going where there are any: counts over 300 rolls.",
      (color: Color, at: string, region: string) => {
        const r = color === "w" ? WHITE : BLACK;
        const source = regionSource(tree, node(region), r, color);
        const begun = startSurvival({
          steer: "lines",
          lean: "popular",
          tree,
          reps: REPS,
          node: node(region),
          color,
          seed: 1,
        })!;
        const counts: Record<string, number> = {};
        const rand = mulberry32(7);
        const played = split(at);
        const base = {
          ...begun.state.run,
          target: [],
          played,
          fen: walkSan(played).fens.at(-1)!,
        };
        for (const _ of range(1, 300)) {
          const run = opponentReply(source, base, rand);
          const san = run.played.at(-1) ?? "(none)";
          counts[san] = (counts[san] ?? 0) + 1;
        }
        return Object.fromEntries(
          Object.entries(counts).sort((a, b) => b[1] - a[1]),
        );
      },
      [
        ["w", "e4", ""],
        ["w", "e4 e5 Nf3", ""],
        ["b", "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6", ""],
        ["b", "d4 Nf6", "d4 Nf6 c4 g6"],
      ],
    ),
    cases(
      "openingRun.wayIn",
      "The way into an opening along a line: its moves up to the first that reaches a position the opening names; empty when the line never gets there.",
      (aim: string, line: string) => wayIn(tree, node(aim), split(line)),
      [
        ["", "e4 c5 Nf3"],
        ["e4 c5", "e4 c5 Nf3 d6"],
        [
          "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6",
          "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5",
        ],
        [
          "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6",
          "e4 c5 Nf3 a6 d4 cxd4 Nxd4 Nf6 Nc3 d6",
        ],
        ["e4 c5", "d4 d5 c4"],
      ],
    ),
    cases(
      "openingRun.weaknessFromCards",
      "How badly a position wants practice: never studied 1.5; a card 1, plus 1.2 a lapse, twice what its ease is under 2.5, 1 while learning, 1 when due, twice its wrong share; plus 2 for each game your games went off prep there (up to 3).",
      (card: Partial<Card> | null, slips: number) =>
        pinnedClock(
          () => NOW,
          () => {
            const key = positionKey(
              "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
            );
            const cards: Record<string, Card> = card
              ? {
                  [cardId("rep_w", key)]: {
                    ...createCard(
                      cardId("rep_w", key),
                      "rep_w",
                      key,
                      "",
                      NOW + 86_400_000,
                    ),
                    ...card,
                  },
                }
              : {};
            const w = weaknessFromCards(
              cards,
              slips
                ? [
                    {
                      kind: "offprep",
                      repertoireId: "rep_w",
                      key,
                      games: slips,
                    },
                  ]
                : [],
              NOW,
            );
            return Number(w("rep_w", key).toFixed(3));
          },
        ),
      [
        [null, 0],
        [null, 1],
        [null, 5],
        [{}, 0],
        [{ stage: "review", ease: 2.5, correct: 3 }, 0],
        [
          { stage: "review", ease: 1.9, lapses: 2, correct: 2, incorrect: 2 },
          0,
        ],
        [{ stage: "learning", due: NOW - 1 }, 0],
        [{ stage: "review", ease: 2.5, correct: 3 }, 2],
      ],
    ),
    cases(
      "openingRun.lineWeakness",
      "A line's appetite: the mean over its positions; a line with none asks 1.",
      (values: number[]) =>
        lineWeakness(
          "r",
          values.map((_, i) => `${i}`),
          (_r, k) => values[Number(k)],
        ),
      [[[]], [[1.5]], [[1, 2, 6]]],
    ),
    cases(
      "openingRun.judgeByEval",
      "Past the prep a move is judged by what it gives away from your side (never less than nothing): over 80cp is a blunder.",
      (color: Color, before: number, after: number) =>
        judgeByEval(color, before, after),
      [
        ["w", 30, -50],
        ["w", 30, -51],
        ["w", 30, 120],
        ["b", 30, 110],
        ["b", 30, 111],
        ["b", 30, -200],
      ],
    ),
    cases(
      "openingRun.clock",
      "The per-move clock's settings: Off, 10s and 30s.",
      (mode: (typeof CLOCK_MODES)[number]) => ({
        seconds: clockSeconds(mode),
        label: clockLabel(mode),
      }),
      CLOCK_MODES.map((m) => [m] as [(typeof CLOCK_MODES)[number]]),
    ),
    cases(
      "openingRun.resolveColor",
      "Random is resolved once, up front: White under 0.5.",
      (choice: Color | "random", roll: number) =>
        resolveColor(choice, () => roll),
      grid(["w", "b", "random"] as const, [0, 0.499, 0.5, 0.99]),
    ),
    cases(
      "freshness.staleness",
      "How long ago a position was last seen, 0 this round to 1 at 3 rounds or never.",
      (last: number | null) =>
        Number(
          staleness(
            { at: last === null ? {} : { k: last }, round: 10 },
            "k",
          ).toFixed(4),
        ),
      [[null], [10], [9], [8], [7], [2]],
    ),
    cases(
      "freshness.lineParts",
      "A line read in two parts: its tail from the last place it parts from another line, which makes it this line, and its head before that, which makes it this opening (as position counts).",
      (line: string) => {
        const p = lineParts(WHITE, nodeAtLine(WHITE, split(line))!.id);
        return { head: p.head.length, tail: p.tail.length };
      },
      leafLines(WHITE).map((l) => [l.sans.join(" ")] as [string]),
    ),
    cases(
      "freshness.lineStaleness",
      "A line's freshness: its tail's mean staleness, times half plus half its head's. And whether it was just run: every position of its tail seen this round.",
      (line: string, seen: [string, number][]) => {
        const s = seenOf(seen);
        const tip = nodeAtLine(WHITE, split(line))!.id;
        return {
          stale: Number(lineStaleness(s, WHITE, tip).toFixed(4)),
          justRun: justRun(s, WHITE, tip),
        };
      },
      [
        ["e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O", []],
        [
          "e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O",
          [["e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O", 10]],
        ],
        [
          "e4 e5 Nf3 Nc6 Bb5 Nf6 O-O",
          [["e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O", 10]],
        ],
        [
          "e4 e5 Nf3 Nc6 Bb5 Nf6 O-O",
          [["e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O", 8]],
        ],
        ["e4 c6 d4 d5 e5 Bf5 Nf3", [["e4 e5 Nf3 d6 d4", 9]]],
      ],
    ),
    cases(
      "evalDelta.whiteCp",
      "An engine score as centipawns from White's side, a mate in n folded to 100000 − n.",
      (cp: number | null, mate: number | null) => whiteCp({ cp, mate }),
      [
        [35, null],
        [null, 3],
        [null, -2],
        [null, null],
      ],
    ),
    cases(
      "evalDelta.deltaFor",
      "What a move does to the eval bar, from the mover's side; shown in pawns (0.0 under 10cp, at most 9.9) and toned good, bad or even.",
      (color: Color, position: number, after: number) => {
        const d = deltaFor(color, position, after);
        return { delta: d, shown: formatDelta(d), tone: deltaTone(d) };
      },
      [
        ["w", 30, 32],
        ["w", 30, 10],
        ["w", 30, 45],
        ["b", 30, 10],
        ["b", 30, 300],
        ["w", 0, 5000],
      ],
    ),
    cases(
      "evalDelta.order",
      "Growth's answers in the engine's order (best shown delta first, ties to the more played, unweighed last in the order they came) and in strong players' order (most played first, ties to the engine).",
      (moves: [string, number, number | null][]) => {
        const list = moves.map(([san, share]) => ({ san, share }));
        const delta = (san: string) => moves.find((m) => m[0] === san)![2];
        return {
          engine: byDelta(list, delta).map((m) => m.san),
          share: byShare(list, delta).map((m) => m.san),
        };
      },
      [
        [
          [
            ["Nf3", 0.5, -12],
            ["Nc3", 0.2, -8],
            ["c3", 0.1, -14],
            ["d4", 0.1, null],
            ["Bc4", 0.1, -40],
          ],
        ],
        [
          [
            ["a", 0, 3],
            ["b", 0, -3],
            ["c", 0, null],
            ["d", 0, 25],
          ],
        ],
      ],
    ),
    cases(
      "autopilotPrefs.autopilotModes",
      "How an Autopilot round plays each mode, whatever the mode's own setup says; only the move scores and board glow follow Autopilot's settings.",
      (moveScores: boolean, boardGlow: boolean) =>
        autopilotModes({ moveScores, boardGlow }),
      grid([true, false], [true, false]),
    ),
  ],
};

export default file;
