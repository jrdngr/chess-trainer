/**
 * Growth sittings, driven through `growthController` the way the screen
 * drives it: the opponent walks on its own, a hole the book cannot answer
 * ends the batch, the batch is measured at its first hole, and their reply
 * to each answer comes from the book. The script gives your taps. The
 * repertoire a sitting adds to is kept here as the store would keep it, so
 * Undo takes back what was really added. See `scenarioKit`.
 *
 * Repertoire node ids are made up per session, so the file never shows
 * them: a removed node is given by its line, and `nodeId` fields are left
 * out of the session.
 */
import { referenceIndex } from '../../model/referenceIndex';
import { choicesAt, growthRows, nextHole, pastTheBook, preparedHere, resumeAdding, type GrowthRow } from '../../model/growth';
import {
  anotherBatch,
  beginGrowth,
  choose,
  measureBatch,
  nothingPrepared,
  opponentToMove,
  opponentWalks,
  reachedEdge,
  stop,
  theyReply,
  undo,
  walk,
  type GrowthEffect,
  type GrowthSession,
  type GrowthStep,
} from '../../model/growthController';
import { DEFAULT_GROWTH } from '../../model/modes';
import { growthSource } from '../../model/moveSource';
import { addLine, createRepertoire, pathTo, pruneLine } from '../../model/repertoire';
import type { Repertoire } from '../../model/types';
import { json, type Scenario, type ScenarioFile, type ScenarioStep } from '../scenarioKit';

const index = referenceIndex();

/** A tap: a move on the board while walking, an answer at a hole (by its place in the list, or by name), Undo, More, or Done. */
type Tap = { walk: string } | { choose: number | string } | { undo: 'last' | 'all' } | 'more' | 'stop';

interface Script {
  name: string;
  about: string;
  color: 'w' | 'b';
  lines: string[];
  /** Which row to grow, by its place in the list Growth shows. */
  row?: number;
  /** Start from move one rather than at the row's first hole. */
  fromStart?: boolean;
  find?: { minShare: number; maxPly: number };
  taps: Tap[];
}

/** Drop the session's node ids, and write sets as sorted lists. */
function data(value: unknown): unknown {
  return JSON.parse(
    JSON.stringify(value, (key, v) => {
      if (key === 'nodeId') return undefined;
      if (v instanceof Set) return [...v].sort();
      return v;
    }),
  );
}

function rowData(row: GrowthRow): unknown {
  return data({ id: row.id, name: row.name, color: row.color, depth: row.depth, holes: row.holes.map((h) => ({ path: h.path, san: h.san })) });
}

function play(script: Script): Scenario {
  const find = script.find ?? { minShare: DEFAULT_GROWTH.minShare, maxPly: DEFAULT_GROWTH.maxPly };
  let live: Repertoire = createRepertoire(script.color === 'w' ? 'White' : 'Black', script.color, `rep_${script.color}`);
  for (const line of script.lines) live = addLine(live, line.split(' '), 'seed').rep;
  /** The tree as it was when the run began, so adding a move cannot re-steer it. */
  const tree = live;
  const rows = growthRows([tree], index, { minShare: find.minShare, maxPly: find.maxPly });
  const row = rows[script.row ?? 0];
  if (!row) throw new Error(`${script.name}: no row`);
  const steps: ScenarioStep[] = [];
  let session = beginGrowth(tree, index, row, script.fromStart ? null : undefined);

  const effectData = (effect: GrowthEffect): unknown => {
    if (effect.kind === 'removeLine') return { kind: 'removeLine', line: pathTo(live, effect.nodeId).map((move) => move.san) };
    return effect;
  };
  /** Carry out the store's effects, as the screen does. */
  const store = (effect: GrowthEffect) => {
    if (effect.kind === 'addLine') live = addLine(live, effect.line, growthSource(index)).rep;
    if (effect.kind === 'removeLine') live = pruneLine(live, effect.nodeId);
  };
  const sessionData = (s: GrowthSession) =>
    data({
      phase: s.phase,
      run: { path: s.run.path, fen: s.run.fen, hole: s.run.hole, targets: s.run.targets },
      wrong: s.wrong,
      added: s.added,
      batch: s.batch,
      answer: s.answer?.san ?? null,
      history: s.history.map((h) => ({ path: h.run.path, batch: h.batch, san: h.san })),
      edge: s.edge,
      saved: [...live.nodes ? Object.keys(live.nodes) : []].length,
    });
  const record = (call: ScenarioStep['call'], step: GrowthStep) => {
    const effects = step.effects.map(effectData);
    step.effects.forEach(store);
    session = step.session;
    steps.push(json({ call, effects, after: sessionData(session) }) as ScenarioStep);
  };
  const update = (call: ScenarioStep['call'], next: GrowthSession) => {
    if (next !== session) record(call, { session: next, effects: [] });
  };

  /** What happens on its own between taps. */
  const settle = () => {
    for (let guard = 0; guard < 200; guard += 1) {
      const before = session;
      if (session.phase === 'walking') {
        if (opponentToMove(session, tree)) update({ fn: 'opponentWalks', find }, opponentWalks(session, tree, index, find));
        else update({ fn: 'nothingPrepared', prepared: preparedHere(tree, session.run).length }, nothingPrepared(session, preparedHere(tree, session.run).length));
      }
      if ((session.phase === 'hole' || session.phase === 'answered') && pastTheBook(index, session.run.fen)) {
        record({ fn: 'reachedEdge' }, reachedEdge(session));
      }
      if (session.phase === 'hole') {
        const choices = choicesAt(index, session.run.fen, 4);
        if (choices === undefined) throw new Error(`${script.name}: past the book at a hole`);
        if (!choices.length) update({ fn: 'stop' }, stop(session));
        else update({ fn: 'measureBatch', maxPly: find.maxPly }, measureBatch(session, find.maxPly));
      }
      if (session.phase === 'answered') {
        const hole = nextHole(index, session.run);
        if (hole === undefined) throw new Error(`${script.name}: the engine would reply`);
        update({ fn: 'theyReply', hole: data(hole) }, theyReply(session, hole));
      }
      if (session === before) return;
    }
    throw new Error(`${script.name}: never settled`);
  };

  settle();
  for (const tap of script.taps) {
    if (tap === 'stop') update({ fn: 'stop' }, stop(session));
    else if (tap === 'more') {
      const more = resumeAdding(tree, index, session.run);
      if (!more) throw new Error(`${script.name}: nothing more to add`);
      record({ fn: 'anotherBatch', more: data({ path: more.path, fen: more.fen, hole: more.hole, targets: more.targets }) }, anotherBatch(session, tree, more));
    } else if ('walk' in tap) record({ fn: 'walk', san: tap.walk }, walk(session, tree, tap.walk));
    else if ('undo' in tap) record({ fn: 'undo', all: tap.undo === 'all' }, undo(session, live, tap.undo === 'all'));
    else {
      if (session.phase !== 'hole') throw new Error(`${script.name}: no hole to answer`);
      const offered = (choicesAt(index, session.run.fen, 4) ?? []).map((option) => option.san);
      const san = typeof tap.choose === 'number' ? offered[tap.choose] : tap.choose;
      if (!san) throw new Error(`${script.name}: no answer ${tap.choose}`);
      const allowance = session.batch?.allowance ?? 0;
      record({ fn: 'choose', san, allowance, offered }, choose(session, san, allowance, offered));
    }
    settle();
  }
  return {
    name: script.name,
    about: script.about,
    setup: json({ rep: { id: tree.id, color: tree.color, lines: script.lines }, find, row: rowData(row), fromStart: !!script.fromStart }),
    steps,
  };
}

const KID = 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6';

const scripts: Script[] = [
  {
    name: 'answer-a-batch',
    about: 'A thin King’s Indian: answer the first holes with the top choice, each reply walking on to the next, until the batch is full.',
    color: 'b',
    lines: [KID],
    taps: [...Array(8).fill({ choose: 0 }), 'more', { choose: 1 }, 'stop'],
  },
  {
    name: 'undo-one-and-all',
    about: 'Answers taken back: Undo the last, which stands the run on the reply again with the slot free, then answer again and Undo all.',
    color: 'b',
    lines: [KID],
    taps: [{ choose: 0 }, { choose: 1 }, { undo: 'last' }, { choose: 2 }, { choose: 0 }, { undo: 'all' }, 'stop'],
  },
  {
    name: 'to-the-edge-of-the-book',
    about: 'Batches answering the top choice each time, then another batch, until the book has no reply: the run stops at the edge and says so.',
    color: 'w',
    lines: ['e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6'],
    find: { minShare: 1, maxPly: 60 },
    taps: [...Array(8).fill({ choose: 0 }), 'more', { choose: 0 }],
  },
];

const file: ScenarioFile = { area: 'growth', scenarios: scripts.map(play) };
export default file;
