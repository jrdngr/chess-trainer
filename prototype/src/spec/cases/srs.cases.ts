import { createCard, createLineCard, DAY, describeDelay, gradeForLine, gradeForTime, isDue, review, runGap, MINUTE } from '../../model/srs';
import type { Card, Grade } from '../../model/types';
import { cases, grid, range, type CaseFile } from '../caseKit';

const START = Date.parse('2026-10-01T09:00:00Z');

/**
 * A card from new, reviewed with each grade in turn, each review made the
 * moment the last one fell due. Every state along the way is recorded.
 */
function schedule(grades: Grade[]): Card[] {
  let card = createCard('rep_w#key', 'rep_w', 'key', 'fen', START);
  let now = START;
  const out: Card[] = [];
  for (const grade of grades) {
    card = review(card, grade, now).card;
    out.push(card);
    now = Math.max(now, card.due);
  }
  return out;
}

const GRADES: Grade[] = ['again', 'hard', 'good', 'easy'];

const file: CaseFile = {
  area: 'srs',
  functions: [
    cases('srs.gradeForTime', 'The grade a correct answer earns, by how long it took.', gradeForTime, range(0, 15, 0.1).map((n) => [n] as [number])),
    cases('srs.gradeForLine', "A whole line's grade: Guessed after any miss, otherwise the average time.", gradeForLine, [
      [[], 0],
      [[1, 2], 0],
      [[2.9, 3.1], 0],
      [[3, 3], 0],
      [[7.9, 8.1], 0],
      [[8, 8], 0],
      [[12, 20], 0],
      [[1], 1],
      [[], 2],
    ]),
    cases('srs.createCard', 'A new position card.', createCard, [['rep_w#key', 'rep_w', 'key', 'fen', START]]),
    cases('srs.createLineCard', 'A new line card.', createLineCard, [['rep_w', 'tip', START]]),
    cases('srs.review (one grade)', 'One review of a new card.', (grade: Grade) => review(createCard('id', 'rep', 'key', 'fen', START), grade, START), GRADES.map((g) => [g] as [Grade])),
    cases('srs.review (schedule)', 'A card reviewed through a sequence of grades, each on the day it fell due.', schedule, [
      ...grid(GRADES, GRADES, GRADES).map((gs) => [gs] as [Grade[]]),
      [['good', 'good', 'good', 'good', 'good', 'good', 'good', 'good', 'good', 'good']],
      [['easy', 'easy', 'easy', 'easy', 'easy', 'easy', 'easy', 'easy']],
      [['good', 'good', 'good', 'good', 'again', 'good', 'good', 'good']],
      [['again', 'again', 'again', 'again', 'again', 'again', 'again', 'again']],
      [['hard', 'hard', 'hard', 'hard', 'hard', 'hard', 'hard', 'hard']],
    ]),
    cases('srs.isDue', 'Whether a card is due at a moment.', (offset: number) => isDue({ ...createCard('id', 'rep', 'key', 'fen', START), due: START }, START + offset), [-1, 0, 1, DAY].map((n) => [n] as [number])),
    cases('srs.runGap', 'How many runs a card waits between asks, by its interval.', (interval: number, stage: Card['stage']) => runGap({ ...createCard('id', 'rep', 'key', 'fen', START), interval, stage }), grid([0, 1, 2, 3, 4, 6, 10, 21, 60, 365], ['new', 'learning', 'review'] as Card['stage'][])),
    cases('srs.describeDelay', 'How a wait is written.', describeDelay, [0, 30_000, MINUTE, 10 * MINUTE, 59 * MINUTE, 60 * MINUTE, 23 * 60 * MINUTE, DAY, 2 * DAY, 30 * DAY, 365 * DAY].map((n) => [n] as [number])),
  ],
};

export default file;
