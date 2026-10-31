import { positionKey } from '../../chess/core';
import { chooseStart, coldNeed, insideStart, prepDepth, splitItems, startKind, type StartKind } from '../../model/autopilot';
import { prepIndex } from '../../model/openingRun';
import { missingPrep } from '../../model/recommend';
import { addLine, createRepertoire } from '../../model/repertoire';
import { allItems } from '../../model/session';
import { createCard, runNeed } from '../../model/srs';
import type { Card } from '../../model/types';
import { cases, grid, range, type CaseFile } from '../caseKit';

const NOW = Date.parse('2026-10-01T09:00:00Z');
const DAY = 86_400_000;

let rep = createRepertoire('White', 'w', 'rep_w');
for (const line of ['e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d3', 'e4 e5 Nf3 Nc6 Bc4 Nf6 d3 Bc5 c3', 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3']) {
  rep = addLine(rep, line.split(' '), 'seed').rep;
}
const items = allItems([rep]);
const ids = (list: { cardId: string }[]) => list.map((item) => item.cardId);
const index = prepIndex(rep);
const prepAt = (fen: string) => index.get(positionKey(fen)) ?? [];

/** A card in a given state, at the scenario's time. */
function card(id: string, over: Partial<Card>): Card {
  return { ...createCard(id, 'rep_w', id.split('#')[1] ?? id, '', NOW), ...over };
}

const CARDS: Card[] = [
  card('rep_w#a', {}),
  card('rep_w#a', { due: NOW - DAY }),
  card('rep_w#a', { due: NOW + DAY }),
  card('rep_w#a', { stage: 'learning', testedRound: 10 }),
  card('rep_w#a', { stage: 'review', interval: 1, testedRound: 10 }),
  card('rep_w#a', { stage: 'review', interval: 4, testedRound: 10 }),
  card('rep_w#a', { stage: 'review', interval: 0.2, testedRound: 10 }),
];

/** Every card of the prep, last asked `ago` runs before round 20, with a stage. */
function deck(ago: (i: number) => number | undefined, stage: Card['stage'] = 'review', interval = 1): Record<string, Card> {
  return Object.fromEntries(
    items.map((item, i) => {
      const tested = ago(i);
      return [item.cardId, { ...createCard(item.cardId, item.repertoireId, item.key, item.fen, NOW), stage, interval, ...(tested === undefined ? {} : { testedRound: 20 - tested }), correct: i % 3, lapses: i % 2 }];
    }),
  );
}
const DECKS = [deck(() => undefined), deck(() => 1), deck((i) => (i % 4 === 0 ? 8 : 2)), deck((i) => i, 'learning')];

const RECENT: StartKind[][] = [
  [],
  ['position'],
  ['cold'],
  ['inside'],
  ['position', 'position'],
  ['cold', 'position'],
  ['position', 'inside'],
  ['inside', 'position'],
  ['position', 'position', 'cold'],
  ['cold', 'inside', 'position'],
];

const file: CaseFile = {
  area: 'autopilot',
  functions: [
    cases('autopilot.chooseStart', 'Where the next run starts, from the last starts and the need of a cold and an inside start.', (recent: StartKind[], cold: number, inside: number | null, firstTime: boolean) => chooseStart({ recent, cold, inside, firstTime }), [
      ...grid(RECENT, [0, 0.5, 1, 1.5], [null, 0.5, 1, 1.5, 2], [false]),
      ...grid(RECENT.slice(0, 3), [2], [2], [true]),
    ]),
    cases('autopilot.startKind', 'The kind of start a round was given.', startKind, [
      [{ pick: { start: 'inside' }, at: null }],
      [{ pick: { start: 'first' }, at: null }],
      [{ pick: { start: 'inside' }, at: ['e4', 'e5'] }],
      [{ pick: { start: 'first' }, at: ['e4', 'e5'] }],
    ]),
    cases('srs.runNeed', 'How much a position wants asking, in runs: 1 and over is due.', (c: Card, round: number) => runNeed(c, round, NOW), grid(CARDS, [10, 11, 12, 13, 16, 22])),
    cases('autopilot.splitItems', 'Your positions on the way into an opening and inside it, by the plies to its own position.', (plies: number) => {
      const split = splitItems(items, plies);
      return { wayIn: ids(split.wayIn), inside: ids(split.inside) };
    }, range(0, 6).map((n) => [n] as [number])),
    cases('autopilot.coldNeed', 'How much the way in wants playing: runs since its stalest move, over the cold gap.', (plies: number, deckAt: number, round: number) => coldNeed(splitItems(items, plies).wayIn, DECKS[deckAt], round), grid([0, 2, 4], range(0, DECKS.length - 1), [20, 26])),
    cases('autopilot.insideStart', 'The position an inside start would begin at, and its need: the most overdue, else the weakest while prep keeps missing.', (plies: number, deckAt: number, accuracy: number | null, round: number) => {
      const start = insideStart(splitItems(items, plies).inside, DECKS[deckAt], { accuracy, round, now: NOW });
      return start && { item: start.item.cardId, need: start.need };
    }, grid([2, 4], range(0, DECKS.length - 1), [null, 0.8, 0.97], [20, 30])),
    cases('recommend.missingPrep', 'How much your prep keeps missing in runs, from accuracy: 0 at 95% and over, 1 at 85% and under.', missingPrep, [[null], ...range(0.8, 1, 0.01).map((n) => [n] as [number])]),
    cases('autopilot.prepDepth', 'How many plies into a line your prep reaches, the first `from` plies counting whatever they were.', (line: string, color: 'w' | 'b', from: number) => prepDepth(line.split(' '), color, prepAt, from), grid(
      ['e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d3 O-O', 'e4 e5 Nf3 Nc6 Bb5 a6', 'e4 c5 Nf3 Nc6 d4', 'd4 d5', 'e4 e6 d4 d5'],
      ['w', 'b'] as const,
      [0, 2, 4],
    )),
  ],
};

export default file;
