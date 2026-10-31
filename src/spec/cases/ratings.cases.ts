import { openingTree } from "../../model/openingTree";
import { referenceIndex } from "../../model/referenceIndex";
import {
  applyResult,
  creditedNodes,
  EMPTY_SCORE,
  expectedAccuracy,
  rankOf,
  ratingAfter,
  settleRun,
  type MoveResult,
  type ScoreState,
} from "../../model/scoring";
import { cases, grid, range, type CaseFile } from "../caseKit";

/** A rating walked through a run of results, every step recorded. */
function walk(start: number, results: boolean[]): number[] {
  const out: number[] = [];
  let rating = start;
  for (const correct of results)
    out.push((rating = ratingAfter(rating, correct)));
  return out;
}

const tree = openingTree(referenceIndex());
const AT = Date.parse("2026-10-01T09:00:00Z");

/** One answer in a run, as data: the line asked at, right or wrong, and its kind. */
interface Answer {
  line: string;
  correct: boolean;
  kind?: "book" | "ext" | "mistake";
}

/** Each opening's ratings, left out of the per-day stats, which are kept by local day. */
function ratings(state: ScoreState) {
  return Object.fromEntries(
    Object.entries(state.nodes)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([id, s]) => [
        id,
        {
          rating: s.rating,
          rated: s.rated,
          extRating: s.extRating,
          extRated: s.extRated,
          answered: s.answered,
          correct: s.correct,
        },
      ]),
  );
}

/**
 * A run's answers applied one by one, each with the run's earlier answers, then
 * the run settled on the line it ended on: the ratings that moved at each step,
 * and every opening's ratings at the end.
 */
function run(answers: Answer[], ended: string | null) {
  let state = EMPTY_SCORE;
  const earlier: MoveResult[] = [];
  const steps = answers.map((answer, i) => {
    const result: MoveResult = {
      mode: "survival",
      line: answer.line ? answer.line.split(" ") : [],
      color: "w",
      correct: answer.correct,
      rated: answer.kind !== "mistake",
      ...(answer.kind === "ext" || answer.kind === "mistake"
        ? { ext: true }
        : {}),
      at: AT + i * 1000,
    };
    const applied = applyResult(state, tree, result, [...earlier]);
    state = applied.state;
    earlier.push(result);
    return applied.moves;
  });
  const settled =
    ended === null ? null : settleRun(state, tree, earlier, ended.split(" "));
  if (settled) state = settled.state;
  return { steps, settled: settled?.moves ?? null, ratings: ratings(state) };
}

const NAJDORF = "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6";
const way = (n: number) => NAJDORF.split(" ").slice(0, n).join(" ");

const file: CaseFile = {
  area: "ratings",
  functions: [
    cases(
      "scoring.expectedAccuracy",
      "The share of answers a rating expects to be right.",
      expectedAccuracy,
      range(-100, 1100, 25).map((n) => [n] as [number]),
    ),
    cases(
      "scoring.ratingAfter",
      "The rating one result leaves, kept to two decimals and never below the floor.",
      ratingAfter,
      grid([...range(0, 1000, 25), 0.5, 99.99, 849.99, 1200], [true, false]),
    ),
    cases(
      "scoring.ratingAfter (walked)",
      "A rating walked through runs of results.",
      walk,
      [
        [0, Array(60).fill(true)],
        [0, Array(10).fill(false)],
        [400, [true, false, true, true, false, false, true, true, true, false]],
        [850, Array(30).fill(true)],
        [850, Array(5).fill(false)],
      ],
    ),
    cases(
      "scoring.creditedNodes",
      "The openings a line counts for: the deepest the book names along it, and every one above.",
      (line: string) => creditedNodes(tree, line ? line.split(" ") : []),
      [
        [""],
        ["e4"],
        [way(2)],
        [way(4)],
        [NAJDORF],
        ["d4 Nf6 c4 g6 Nc3 Bg7 e4 d6"],
        ["e4 d6 d4 Nf6 Nc3 g6 Nf3 Bg7"],
        ["a3 a6 b3"],
      ],
    ),
    cases(
      "scoring.applyResult (a run)",
      "A run's answers rated into every opening its line has reached, an opening reached late taking the run's earlier answers; then the run settled on the line it ended on.",
      run,
      [
        [
          [
            { line: "", correct: true },
            { line: way(2), correct: true },
            { line: way(4), correct: true },
            { line: way(6), correct: true },
            { line: way(8), correct: false },
          ],
          null,
        ],
        [
          [
            { line: "", correct: true },
            { line: way(2), correct: true },
          ],
          NAJDORF,
        ],
        [
          [
            { line: "", correct: true },
            { line: way(2), correct: false },
          ],
          way(5),
        ],
        [
          [
            { line: way(8), correct: true },
            { line: NAJDORF, correct: true, kind: "ext" },
            { line: NAJDORF + " Be3 e5", correct: false, kind: "ext" },
          ],
          null,
        ],
        [
          [
            { line: way(2), correct: true },
            { line: way(4), correct: true, kind: "mistake" },
            { line: way(6), correct: true },
          ],
          NAJDORF,
        ],
        [[], NAJDORF],
      ],
    ),
    cases(
      "scoring.rankOf",
      "Where a rating stands on the ladder; `rated` decides New or Shaky below the first rung.",
      rankOf,
      grid([...range(0, 1000, 10), 99.99, 249.99, 849.99], [0, 1, 5]),
    ),
  ],
};

export default file;
