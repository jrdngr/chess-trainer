import { expectedAccuracy, rankOf, ratingAfter } from '../../model/scoring';
import { cases, grid, range, type CaseFile } from '../caseKit';

/** A rating walked through a run of results, every step recorded. */
function walk(start: number, results: boolean[]): number[] {
  const out: number[] = [];
  let rating = start;
  for (const correct of results) out.push((rating = ratingAfter(rating, correct)));
  return out;
}

const file: CaseFile = {
  area: 'ratings',
  functions: [
    cases('scoring.expectedAccuracy', 'The share of answers a rating expects to be right.', expectedAccuracy, range(-100, 1100, 25).map((n) => [n] as [number])),
    cases('scoring.ratingAfter', 'The rating one result leaves, kept to two decimals and never below the floor.', ratingAfter, grid([...range(0, 1000, 25), 0.5, 99.99, 849.99, 1200], [true, false])),
    cases('scoring.ratingAfter (walked)', 'A rating walked through runs of results.', walk, [
      [0, Array(60).fill(true)],
      [0, Array(10).fill(false)],
      [400, [true, false, true, true, false, false, true, true, true, false]],
      [850, Array(30).fill(true)],
      [850, Array(5).fill(false)],
    ]),
    cases('scoring.rankOf', 'Where a rating stands on the ladder; `rated` decides New or Shaky below the first rung.', rankOf, grid([...range(0, 1000, 10), 99.99, 249.99, 849.99], [0, 1, 5])),
  ],
};

export default file;
