/**
 * Survival and Autopilot runs, driven through `survivalController` the way
 * the screen drives it. The script gives your moves and the engine's
 * replies; the book plays the opponent while it has a move, from a seeded
 * picker. See `scenarioKit` for what the file records.
 */
import { applySan, positionKey } from '../../chess/core';
import type { MoveKind } from '../../model/extensions';
import { nodeById, openingTree } from '../../model/openingTree';
import { referenceIndex } from '../../model/referenceIndex';
import { addLine, createRepertoire } from '../../model/repertoire';
import { mulberry32 } from '../../model/session';
import { DEFAULT_SURVIVAL, startSurvival, type SurvivalPrefs, type SurvivalSteer } from '../../model/survival';
import {
  beginSession,
  bookTurn,
  closeBook,
  endRun,
  engineMove,
  judgedMove,
  missionFrom,
  playersTurn,
  playPrepared,
  prepLabel,
  prepMoves,
  prepRanOut,
  runRound,
  sawEval,
  type Effect,
  type Judgement,
  type RunContext,
  type RunSession,
  type Step,
} from '../../model/survivalController';
import type { Repertoire } from '../../model/types';
import { json, type Scenario, type ScenarioFile, type ScenarioStep } from '../scenarioKit';

const index = referenceIndex();
const tree = openingTree(index);
const NOW = Date.parse('2026-10-01T09:00:00Z');

/** Your turn: a move, how long it took, and what the engine says of the position in front of you. */
interface Turn {
  san: string;
  seconds?: number;
  /** The engine's score for the position before your move, White's side. */
  eval?: number;
  /** The engine's verdict, for a move your prep does not have. Defaults: sound, 10cp lost. */
  judge?: Partial<Omit<Judgement, 'san'>>;
}

interface Script {
  name: string;
  about: string;
  reps: { color: 'w' | 'b'; lines: string[] }[];
  color: 'w' | 'b';
  steer?: SurvivalSteer;
  node?: string;
  seed: number;
  /** Seeds the opponent's book picker. */
  picker: number;
  prefs?: Partial<SurvivalPrefs>;
  autopilot?: boolean;
  /** What a move of yours is, by `line | san`; book when not listed. */
  kinds?: Record<string, MoveKind>;
  /** What the engine said a saved move gives away, by `positionKey san`. */
  losses?: Record<string, number>;
  /** Your turns, then `end` to end the run yourself. */
  turns: (Turn | 'end')[];
  /** The engine's replies, in order, for where the book has nothing. */
  engine?: string[];
}

function rep(color: 'w' | 'b', lines: string[]): Repertoire {
  let out = createRepertoire(color === 'w' ? 'White' : 'Black', color, `rep_${color}`);
  for (const line of lines) out = addLine(out, line.split(' '), 'seed').rep;
  return out;
}

/** An effect as data: the run's answers so far go by count, the ended run by its line and misses. */
function effectData(effect: Effect): unknown {
  if (effect.kind === 'rate') return { ...effect, earlier: effect.earlier.length };
  if (effect.kind === 'finish') {
    const { ended, answers, ...rest } = effect.finish;
    return {
      kind: 'finish',
      finish: { ...rest, ended: { played: ended.run.played, moves: ended.moves, misses: ended.misses.length }, answers: answers.length },
      /** What the screen logs for it: the run as one round. */
      round: runRound(effect.finish, tree),
    };
  }
  return effect;
}

/** The session as the run decides it; the run's id and the line source are the screen's, not the spec's. */
function sessionData(session: RunSession): unknown {
  const { run, moves, misses, extras } = session.state;
  return {
    played: run.played,
    target: run.target,
    moves,
    misses,
    extras,
    prepStatus: session.prepStatus,
    prepSeen: session.prepSeen,
    bookTo: session.bookTo,
    bookOver: session.bookOver,
    bookMoves: session.bookMoves,
    prepEnd: session.prepEnd,
    answers: session.answers.length,
    prepTimes: session.prepTimes,
    lastScored: session.lastScored,
    evalCp: session.evalCp,
    ending: session.ending,
    label: prepLabel(session),
    prep: prepMoves(session),
  };
}

function play(script: Script): Scenario {
  const prefs = { ...DEFAULT_SURVIVAL, ...script.prefs };
  const reps = script.reps.map((r) => rep(r.color, r.lines));
  const node = script.node ? nodeById(tree, script.node) : tree.root;
  const begun = startSurvival({ steer: script.steer ?? 'lines', tree, reps, node, color: script.color, seed: script.seed });
  if (!begun) throw new Error(`${script.name}: no run`);
  const kinds = script.kinds ?? {};
  const losses = script.losses ?? {};
  const ctx: RunContext = {
    index,
    prefs,
    autopilot: !!script.autopilot,
    kindOf: (line, san) => kinds[`${line.join(' ')} | ${san}`] ?? 'book',
    lossOf: (key) => losses[key],
  };
  const picker = mulberry32(script.picker);
  const engine = [...(script.engine ?? [])];
  const steps: ScenarioStep[] = [];
  let session = beginSession(begun);
  let clock = NOW;

  const record = (call: ScenarioStep['call'], step: Step) => {
    session = step.session;
    steps.push(json({ call, effects: step.effects.map(effectData), after: sessionData(session) }) as ScenarioStep);
  };
  /** A call that only changes the session, recorded when it does. */
  const update = (call: ScenarioStep['call'], next: RunSession) => {
    if (next !== session) record(call, { session: next, effects: [] });
  };

  const opponent = () => {
    while (!session.ending && !playersTurn(session)) {
      const step = bookTurn(session, index, picker);
      if (step) {
        record({ fn: 'bookTurn' }, step);
        continue;
      }
      const san = engine.shift();
      if (!san || !applySan(session.state.run.fen, san)) {
        throw new Error(`${script.name}: the engine has no legal reply after ${session.state.run.played.join(' ')}`);
      }
      record({ fn: 'engineMove', san }, engineMove(session, san));
    }
  };

  opponent();
  for (const turn of script.turns) {
    if (session.ending) throw new Error(`${script.name}: a turn after the run ended`);
    if (turn === 'end') {
      record({ fn: 'endRun' }, endRun(session));
      break;
    }
    // Your turn begins: what the screen settles before you move.
    if (!prepMoves(session).length) update({ fn: 'prepRanOut' }, prepRanOut(session, index));
    update({ fn: 'closeBook' }, closeBook(session, index));
    if (turn.eval !== undefined) {
      update({ fn: 'sawEval', cp: turn.eval }, sawEval(session, turn.eval));
      update({ fn: 'missionFrom', cp: turn.eval }, missionFrom(session, prefs, turn.eval));
    }
    const seconds = turn.seconds ?? 2;
    clock += 1000;
    if (!turn.judge && prepMoves(session).includes(turn.san)) {
      const move = applySan(session.state.run.fen, turn.san);
      if (!move) throw new Error(`${script.name}: ${turn.san} is not legal`);
      record({ fn: 'playPrepared', san: turn.san, seconds, now: clock }, playPrepared(session, ctx, move, seconds, clock));
    } else {
      if (!applySan(session.state.run.fen, turn.san)) throw new Error(`${script.name}: ${turn.san} is not legal after ${session.state.run.played.join(' ')}`);
      const judged: Judgement = {
        san: turn.san,
        ok: true,
        lost: 10,
        best: null,
        before: turn.eval ?? 20,
        after: (turn.eval ?? 20) - (script.color === 'w' ? 10 : -10),
        moment: false,
        found: false,
        reply: null,
        ...turn.judge,
      };
      record({ fn: 'judgedMove', judgement: judged, seconds, now: clock }, judgedMove(session, ctx, judged, seconds, clock));
    }
    opponent();
  }
  if (engine.length) throw new Error(`${script.name}: the engine's replies ${engine.join(' ')} were never needed`);
  return {
    name: script.name,
    about: script.about,
    setup: json({
      reps: reps.map((r, i) => ({ id: r.id, color: r.color, lines: script.reps[i].lines })),
      start: { steer: script.steer ?? 'lines', node: node.id, color: script.color, seed: script.seed },
      picker: script.picker,
      prefs,
      autopilot: !!script.autopilot,
      kinds,
      losses,
    }),
    steps,
  };
}

/** The position after `line`, as the key a saved move's loss is kept under. */
function keyAfter(line: string): string {
  const fen = line.split(' ').reduce((at, san) => applySan(at, san)!.after, START);
  return positionKey(fen);
}

const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const QGD = 'd4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5';

const scripts: Script[] = [
  {
    name: 'clean-prep-into-the-book',
    about: 'Autopilot: every prepared move found, at four speeds; the prep runs out cleanly, two book moves, then a move off the book ends the book phase; ended by hand.',
    reps: [{ color: 'w', lines: [QGD] }],
    color: 'w',
    seed: 3,
    picker: 5,
    autopilot: true,
    engine: ['c6'],
    turns: [
      { san: 'd4', seconds: 1 },
      { san: 'c4', seconds: 3 },
      { san: 'Nc3', seconds: 6 },
      { san: 'cxd5', seconds: 12 },
      { san: 'Bg5', seconds: 2 },
      { san: 'e3', seconds: 4, eval: 30, judge: { lost: 5, after: 25 } },
      { san: 'Bh4', seconds: 9, eval: 25, judge: { lost: 15, after: 15 } },
      { san: 'g4', seconds: 3, eval: 15, judge: { lost: 70, after: -40, best: 'Bd3' } },
      'end',
    ],
  },
  {
    name: 'book-runs-out',
    about: 'Autopilot past a clean prep: book moves until the book has nothing for the position, which ends the book phase on your turn.',
    reps: [{ color: 'w', lines: [QGD] }],
    color: 'w',
    seed: 3,
    picker: 5,
    autopilot: true,
    turns: [
      { san: 'd4' },
      { san: 'c4' },
      { san: 'Nc3' },
      { san: 'cxd5' },
      { san: 'Bg5' },
      { san: 'e3', eval: 30, judge: { lost: 5, after: 25 } },
      { san: 'Bh4', eval: 25, judge: { lost: 5, after: 20 } },
      { san: 'Bd3', eval: 20, judge: { lost: 5, after: 15 } },
      { san: 'Nge2', eval: 15, judge: { lost: 5, after: 10 } },
      { san: 'Qc2', eval: 10, judge: { lost: 5, after: 5 } },
      { san: 'O-O', eval: 5, judge: { lost: 5, after: 0 } },
      'end',
    ],
    engine: ['Nbd7', 'Nf8'],
  },
  {
    name: 'miss-then-moments-and-a-blunder',
    about: 'Survival with every extra on: a miss on move two, play on past the prep with a mission set from the eval, a moment found, a moment missed, then a blunder ends it.',
    reps: [{ color: 'w', lines: [QGD] }],
    color: 'w',
    seed: 3,
    picker: 7,
    turns: [
      { san: 'd4', seconds: 1 },
      { san: 'Nf3', seconds: 5, eval: 25, judge: { lost: 15, after: 15 } },
      { san: 'c4', seconds: 3, eval: 120, judge: { lost: 5, after: 115 } },
      { san: 'Nc3', seconds: 3, eval: 115, judge: { lost: 0, after: 130, moment: true, found: true, best: 'Nc3' } },
      { san: 'e3', seconds: 3, eval: 130, judge: { lost: 90, after: 40, moment: true, found: false, best: 'Bg5' } },
      { san: 'h4', seconds: 3, eval: 40, judge: { ok: false, lost: 320, after: -280, best: 'Bd3', reply: 'd8a5' } },
    ],

  },
  {
    name: 'saved-mistake-in-prep',
    about: 'A move saved in the prep as a mistake: still yours to play, its cost popped and not rated; then the prep runs out where the book has nothing and the engine plays on.',
    reps: [{ color: 'w', lines: ['e4 e5 Qh5 Nc6 Bc4'] }],
    color: 'w',
    seed: 1,
    picker: 1,
    kinds: { 'e4 e5 | Qh5': 'mistake' },
    losses: { [`${keyAfter('e4 e5')} Qh5`]: 60 },
    turns: [
      { san: 'e4', seconds: 2 },
      { san: 'Qh5', seconds: 2 },
      { san: 'Bc4', seconds: 2 },
      { san: 'Qf3', seconds: 4, eval: -20, judge: { lost: 20, after: -40 } },
      'end',
    ],
    engine: ['Nf6'],
  },
  {
    name: 'mated-as-black',
    about: 'Black prep that mates: the game ends won on the board, with the prep complete and clean.',
    reps: [{ color: 'b', lines: ['f3 e5 g4 Qh4#'] }],
    color: 'b',
    seed: 2,
    picker: 2,
    turns: [
      { san: 'e5', seconds: 1 },
      { san: 'Qh4#', seconds: 1 },
    ],
  },
  {
    name: 'ended-on-prep-quietly',
    about: 'Survival with move scores, moments, missions and combo off: one prepared move, then the run ended by hand while still on the prep.',
    reps: [{ color: 'w', lines: [QGD] }],
    color: 'w',
    seed: 3,
    picker: 9,
    prefs: { moveScores: false, moments: false, missions: false, combo: false },
    turns: [{ san: 'd4', seconds: 8 }, 'end'],
  },
];

const file: ScenarioFile = { area: 'survival', scenarios: scripts.map(play) };
export default file;
