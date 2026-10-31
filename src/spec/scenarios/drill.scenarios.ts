/**
 * Drill sittings, driven through `drillController` (positions) and
 * `lineDrillController` (lines) the way their screens drive them. The script
 * gives your answers; the cards they grade are kept here as the store keeps
 * them, so a sitting's later batches see its earlier grades. See
 * `scenarioKit`.
 *
 * Repertoire node ids are made up per session, so the file never shows
 * them: each is written as `@` and the line to that node.
 */
import { applySan, positionKey, type LegalMove } from '../../chess/core';
import {
  advance,
  answer,
  beginDrill,
  continueAfterWrong,
  current,
  drillRound,
  expectedSan,
  followUpFor,
  refill,
  regradeLast,
  type DrillEffect,
  type DrillOptions,
  type DrillState,
  type DrillStep,
} from '../../model/drillController';
import * as lines from '../../model/lineDrillController';
import { drawLines, type DrillLine, type LineLean } from '../../model/lineDrill';
import { openingTree } from '../../model/openingTree';
import { referenceIndex } from '../../model/referenceIndex';
import { addLine, createRepertoire, pathTo } from '../../model/repertoire';
import { allItems, mulberry32, type TrainingItem } from '../../model/session';
import { createCard, createLineCard, lineCardId, review } from '../../model/srs';
import type { Card, Grade, LineCard, Repertoire } from '../../model/types';
import { json, pinnedClock, type Scenario, type ScenarioFile, type ScenarioStep } from '../scenarioKit';

const index = referenceIndex();
const tree = openingTree(index);
const NOW = Date.parse('2026-10-01T09:00:00Z');
const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

function build(color: 'w' | 'b', sans: string[]): Repertoire {
  let out = createRepertoire(color === 'w' ? 'White' : 'Black', color, `rep_${color}`);
  for (const line of sans) out = addLine(out, line.split(' '), 'seed').rep;
  return out;
}

/** Node ids, written as the line to the node. */
function noIds(rep: Repertoire, value: unknown): unknown {
  let text = JSON.stringify(value === undefined ? null : value);
  for (const id of Object.keys(rep.nodes).sort((a, b) => b.length - a.length)) {
    text = text.split(id).join(`@${pathTo(rep, id).map((move) => move.san).join(' ')}`);
  }
  return json(JSON.parse(text));
}

/** A move the position does not want: the first of a few quiet ones that is legal and not prepared. */
function wrongMove(item: TrainingItem): LegalMove {
  const right = item.expected.map((e) => e.san);
  const san = ['a3', 'h3', 'a6', 'h6', 'a4', 'h4', 'a5', 'h5'].find((m) => !right.includes(m) && applySan(item.fen, m))!;
  return applySan(item.fen, san)!;
}

// --- Drill positions ---------------------------------------------------------

type PositionTap = { right: number } | { wrong: number } | 'continue' | { regrade: Grade };

interface PositionScript {
  name: string;
  about: string;
  color: 'w' | 'b';
  lines: string[];
  opts: DrillOptions;
  followLine: boolean;
  picker: number;
  taps: PositionTap[];
}

function positions(script: PositionScript): Scenario {
  const rep = build(script.color, script.lines);
  const items = allItems([rep]);
  const rand = mulberry32(script.picker);
  let clock = NOW;
  let cards: Record<string, Card> = {};
  const steps: ScenarioStep[] = [];
  const itemId = (item: TrainingItem | null | undefined) => item?.cardId ?? null;
  const summary = (s: DrillState) => ({
    index: s.index,
    asking: itemId(current(s)),
    queue: s.queue.map((i) => i.cardId),
    phase: s.phase,
    played: s.played?.san ?? null,
    stats: s.stats,
    last: s.last && { item: s.last.item.cardId, grade: s.last.grade, played: s.last.played, before: s.last.before },
    cards: Object.keys(cards).length,
    /** The sitting as one round, were it ended here. */
    round: drillRound(s, ''),
  });
  const effectData = (effect: DrillEffect) => {
    if (effect.kind === 'grade' || effect.kind === 'regrade') return { ...effect, item: effect.item.cardId };
    if (effect.kind === 'flash') return { kind: 'flash', next: itemId(effect.next) };
    return effect;
  };
  /** What the store does with a grade, at the scenario's time. */
  const store = (effect: DrillEffect) => {
    if (effect.kind === 'grade') {
      const { item } = effect;
      const card = cards[item.cardId] ?? createCard(item.cardId, item.repertoireId, item.key, item.fen, clock);
      cards = { ...cards, [item.cardId]: review(card, effect.grade, clock).card };
    }
    if (effect.kind === 'regrade') cards = { ...cards, [effect.item.cardId]: review(effect.before, effect.grade, clock).card };
  };

  let state = pinnedClock(
    () => clock,
    () => beginDrill(items, cards, script.opts, clock),
  );
  const record = (call: ScenarioStep['call'], step: DrillStep) => {
    const effects = step.effects.map(effectData);
    step.effects.forEach(store);
    state = step.state;
    steps.push(json({ call, effects, after: summary(state) }) as ScenarioStep);
    return step;
  };
  const update = (call: ScenarioStep['call'], next: DrillState) => {
    if (next !== state) record(call, { state: next, effects: [] });
  };
  steps.push(json({ call: { fn: 'beginDrill', now: clock, opts: script.opts }, effects: [], after: summary(state) }) as ScenarioStep);

  pinnedClock(
    () => clock,
    () => {
      for (const tap of script.taps) {
        update({ fn: 'refill', now: clock, opts: script.opts }, refill(state, items, cards, script.opts, rand, clock));
        const item = current(state);
        if (!item) throw new Error(`${script.name}: nothing to ask`);
        if (tap === 'continue') update({ fn: 'continueAfterWrong' }, continueAfterWrong(state));
        else if ('regrade' in tap) record({ fn: 'regradeLast', grade: tap.regrade }, regradeLast(state, tap.regrade));
        else {
          clock += 1000;
          const right = 'right' in tap;
          const move = right ? applySan(item.fen, expectedSan(item)!)! : wrongMove(item);
          const took = right ? tap.right : tap.wrong;
          const followUp = script.followLine ? followUpFor(item, items, rep) : null;
          const step = record(
            { fn: 'answer', san: move.san, took, card: cards[item.cardId] ?? null, followUp: itemId(followUp) },
            answer(state, move, took, cards[item.cardId], followUp),
          );
          const flash = step.effects.find((effect) => effect.kind === 'flash');
          if (flash) update({ fn: 'advance', extra: itemId(flash.next) }, advance(state, flash.next));
        }
      }
    },
  );
  return {
    name: script.name,
    about: script.about,
    setup: json({ rep: { id: rep.id, color: rep.color, lines: script.lines }, opts: script.opts, followLine: script.followLine, picker: script.picker }),
    steps,
  };
}

// --- Drill lines -------------------------------------------------------------

type LineTap = { right: number } | { wrong: number } | 'next' | { regrade: Grade };

interface LineScript {
  name: string;
  about: string;
  color: 'w' | 'b';
  lines: string[];
  lean: LineLean;
  count: number;
  picker: number;
  taps: LineTap[];
}

function lineSitting(script: LineScript): Scenario {
  const rep = build(script.color, script.lines);
  const items = allItems([rep]);
  const rand = mulberry32(script.picker);
  const color = script.color;
  let clock = NOW;
  let lineCards: Record<string, LineCard> = {};
  const mistakes = new Set<string>();
  const steps: ScenarioStep[] = [];
  const draw = (avoid?: Set<string>): DrillLine[] =>
    drawLines({ rep, tree, region: tree.root, index, lean: script.lean, cards: lineCards, avoid, count: script.count, rand, now: clock });
  const fenAt = (s: lines.LineDrillState) => s.line!.sans.slice(0, s.ply).reduce((fen, san) => applySan(fen, san)!.after, START);
  const summary = (s: lines.LineDrillState) => ({
    group: s.group,
    at: s.at,
    batch: s.batch.map((l) => l.sans.join(' ')),
    line: s.line?.sans ?? null,
    ply: s.ply,
    phase: s.phase,
    played: s.played?.san ?? null,
    misses: s.misses,
    times: s.times,
    graded: s.graded,
    finished: s.finished,
  });

  let state = lines.beginLines([]);
  const record = (call: ScenarioStep['call'], step: lines.LineStep) => {
    state = step.state;
    const effects = step.effects;
    for (const effect of effects) {
      if (effect.kind === 'mistake') mistakes.add(`${effect.mistake.repertoireId}#${effect.mistake.key}`);
      if (effect.kind === 'clearMistake') mistakes.delete(effect.id);
    }
    steps.push(noIds(rep, { call, effects, after: summary(state) }) as ScenarioStep);
    // The store grades the line and hands back the card as it was.
    for (const effect of effects) {
      if (effect.kind !== 'gradeLine') continue;
      const id = lineCardId(effect.repertoireId, effect.tipId);
      const before = effect.before ?? lineCards[id] ?? createLineCard(effect.repertoireId, effect.tipId, clock);
      lineCards = { ...lineCards, [id]: review(before, effect.grade, clock).card };
      if (!effect.before) record({ fn: 'graded', before, grade: effect.grade }, { state: lines.graded(state, before, effect.grade), effects: [] });
    }
  };
  const update = (call: ScenarioStep['call'], next: lines.LineDrillState) => {
    if (next !== state) record(call, { state: next, effects: [] });
  };
  /** The opponent's moves, and the end of the line, as they happen on their own. */
  const settle = () => {
    for (let guard = 0; guard < 80; guard += 1) {
      const before = state;
      update({ fn: 'theirMove' }, lines.theirMove(state, color));
      const done = lines.lineDone(state, color, tree, tree.root);
      if (done.state !== state) record({ fn: 'lineDone' }, done);
      if (state === before) return;
    }
  };

  pinnedClock(
    () => clock,
    () => {
      const drawn = draw();
      record({ fn: 'beginLines', lines: drawn }, { state: lines.beginLines(drawn), effects: [] });
      settle();
      for (const tap of script.taps) {
        if (tap === 'next') {
          const fresh = lines.needsDraw(state) ? draw(new Set(state.batch.map((done) => done.tipId))) : undefined;
          update({ fn: 'nextLine', fresh: fresh ?? null }, lines.nextLine(state, fresh));
        } else if ('regrade' in tap) record({ fn: 'regrade', grade: tap.regrade }, lines.regrade(state, tap.regrade));
        else {
          if (!lines.yourMove(state, color) || state.phase !== 'play') throw new Error(`${script.name}: not your move`);
          clock += 1000;
          const fen = fenAt(state);
          const item = items.find((candidate) => candidate.key === positionKey(fen)) ?? null;
          const right = 'right' in tap;
          const move = right ? applySan(fen, lines.expectedHere(state, color)!)! : wrongMove(item ?? ({ fen, expected: [] } as never));
          const took = right ? tap.right : tap.wrong;
          record(
            { fn: 'answer', san: move.san, took, item: item?.cardId ?? null, mistakeIds: [...mistakes].sort() },
            lines.answer(state, color, move, took, rep, item, [...mistakes]),
          );
          // The flash after a right move, or Continue after a miss: the line goes on.
          update({ fn: 'carryOn' }, lines.carryOn(state));
        }
        settle();
      }
    },
  );
  return {
    name: script.name,
    about: script.about,
    setup: json({ rep: { id: rep.id, color, lines: script.lines }, lean: script.lean, count: script.count, picker: script.picker }),
    steps,
  };
}

const ITALIAN = 'e4 e5 Nf3 Nc6 Bc4 Bc5 O-O';
const SICILIAN = 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3';
const OPEN = 'e4 e5 Nf3 Nc6 Bc4 Nf6 d3';

const positionScripts: PositionScript[] = [
  {
    name: 'positions-a-sitting',
    about: 'Drill positions: answers at four speeds, a miss sent back round, Guessed on a right answer, and the queue refilled from extra practice once the schedule is clear.',
    color: 'w',
    lines: [ITALIAN, SICILIAN, OPEN],
    opts: { mode: 'repertoire', maxNew: 8, weakFirst: false },
    followLine: true,
    picker: 13,
    taps: [
      { right: 1 },
      { right: 4 },
      { wrong: 6 },
      'continue',
      { right: 9 },
      { regrade: 'again' },
      { right: 2 },
      { right: 15 },
      { wrong: 3 },
      'continue',
      { right: 2 },
      { right: 2 },
      { right: 2 },
      { right: 2 },
    ],
  },
];

const lineScripts: LineScript[] = [
  {
    name: 'lines-a-group',
    about: 'Drill lines: a clean line graded by its time, a line with a miss (Continue plays the prep), a grade changed, and a fresh group drawn when this one is done.',
    color: 'w',
    lines: [ITALIAN, SICILIAN, OPEN],
    lean: 'popular',
    count: 2,
    picker: 21,
    taps: [
      { right: 1 },
      { right: 2 },
      { right: 1 },
      { right: 2 },
      { right: 1 },
      'next',
      { right: 3 },
      { wrong: 5 },
      { right: 3 },
      { right: 3 },
      { regrade: 'good' },
      'next',
      { right: 2 },
    ],
  },
];

const file: ScenarioFile = {
  area: 'drill',
  scenarios: [...positionScripts.map(positions), ...lineScripts.map(lineSitting)],
};
export default file;
