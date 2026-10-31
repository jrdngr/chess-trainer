/**
 * A Survival run (Autopilot's too) as a pure controller: `state + event →
 * state + effects`. The screen owns timing, the engine and the store; it
 * feeds each thing that happens in as an event and carries out the effects
 * in order. Everything the run decides lives here, so a scripted run can be
 * replayed without a screen, and the native app can copy the same shape.
 */
import { applySan, fenTurn, positionKey, positionStatus, type Color, type LegalMove } from '../chess/core';
import type { MoveKind } from './extensions';
import type { ReferenceIndex } from './reference';
import { deepestNodeWithin, nodeById, type OpeningTree } from './openingTree';
import type { MoveResult, RoundRecord } from './scoring';
import { gradeForTime } from './srs';
import type { Grade } from './types';
import {
  bookReply,
  evalSwing,
  firstMission,
  inTheBook,
  isBookMove,
  judgedExtras,
  missionTitle,
  moveScore,
  playTheirs,
  playYours,
  prepHere,
  secondsText,
  speedTone,
  type Earned,
  type ScoreTone,
  type SurvivalPrefs,
  type SurvivalRun,
  type SurvivalStart,
} from './survival';

/** How a run ended. */
export type Ending =
  | {
      kind: 'blunder';
      /** The move that lost, not on the board: the board stops before it. */
      played: string;
      /** The engine's move in the same position. */
      best: string | null;
      lost: number;
      /** The opponent's best answer to it, as a UCI move: the threat that made it a blunder. */
      reply: string | null;
    }
  | { kind: 'won' | 'lost' | 'draw' }
  /** You ended it yourself, off your prep: counted apart from moves survived. */
  | { kind: 'ended' };

/**
 * Where you stand against your prep: on it, through to the end of the line,
 * or off it. Latched: once complete or off, it stays that way for the run.
 */
export type PrepStatus = 'on' | 'complete' | 'off';

/**
 * What one of your moves cost, floating up from the square it landed on — or,
 * in Autopilot, a prepared move found, ticked, with how long it took.
 */
export interface Pop {
  square: LegalMove['to'];
  text: string;
  tone: ScoreTone;
  /** A prepared move found: the tick goes in front of its time. */
  found?: boolean;
  /** A book move past your prep: the tick and "Book" in the book's color. */
  book?: boolean;
  /** A prepared move that is an extension: the tick and "Ext", outlined in the extension color. */
  ext?: boolean;
}

/** A miss being shown: the prepared move, drawn as a green arrow on the board. */
export interface MissFlash {
  expected: string;
  from: LegalMove['from'];
  to: LegalMove['to'];
}

export interface Note {
  text: string;
  tone: 'good' | 'bad' | 'accent';
}

/** The engine's verdict on a move your prep did not have (see `useJudge`). */
export interface Judgement {
  san: string;
  ok: boolean;
  lost: number;
  best: string | null;
  before: number;
  after: number;
  moment: boolean;
  found: boolean;
  reply: string | null;
}

/** What the run is played under, fixed for its length. */
export interface RunContext {
  index: ReferenceIndex;
  prefs: SurvivalPrefs;
  /** Opened by Autopilot: prepared moves and book moves pop with their time. */
  autopilot: boolean;
  /** What your move `san` is where `line` stands: book, or one of the extension kinds. */
  kindOf: (line: string[], san: string) => MoveKind;
  /** What the engine said a saved move gives away, by `positionKey(fen) san`. */
  lossOf: (key: string) => number | undefined;
}

export interface RunSession extends SurvivalStart {
  prepStatus: PrepStatus;
  /** Whether your prep has answered anything yet: with nothing prepared, there is no status to show. */
  prepSeen: boolean;
  /**
   * The book phase, once a clean prep runs out: the ply count it has reached
   * (null before it begins), and whether it is over — at your first move that
   * is not a book move, or where the book has nothing.
   */
  bookTo: number | null;
  bookOver: boolean;
  /** Book moves played this run, for the end screen. */
  bookMoves: number;
  /**
   * The line as it stood when your prep ran out without a miss: a clean
   * finish, and where growing it would start. Null until then, and for good
   * once you miss.
   */
  prepEnd: string[] | null;
  /** This run's rated answers, which an opening the line reaches later takes too. */
  answers: MoveResult[];
  /** How long each prepared move you found took, in seconds: Autopilot's speed. */
  prepTimes: number[];
  /** The engine's score after your last scored move, White's side: where the next popup counts from. */
  lastScored: number | null;
  /** The engine's last word on the game, White's side, for the glow. */
  evalCp: number | null;
  /** Set once the run is over; a late verdict or move then lands nowhere. */
  ending: Ending | null;
}

/** What the run asks the store to keep when it ends. */
export interface Finish {
  how: Ending;
  /** The run, as it stood when it ended. */
  ended: SurvivalRun;
  /** Your prep played to its end without a miss: where growing it would start. */
  clean: string[] | null;
  /** Prep that asked nothing: an opening saved as its own moves, offered to grow but not a clean finish. */
  stub: boolean;
  answers: MoveResult[];
}

/** Something for the screen to do, in order. */
export type Effect =
  /** Rate one answered prepared position; `earlier` is the run's answers before it. */
  | { kind: 'rate'; result: MoveResult; earlier: MoveResult[] }
  /** A prepared position answered: review its card. */
  | { kind: 'answered'; repertoireId: string; fen: string; san: string; grade: Grade }
  /** A prepared position missed: log it for review. */
  | { kind: 'missed'; repertoireId: string; fen: string; played: string; expected: string }
  | { kind: 'buzz'; pattern: number | number[] }
  | { kind: 'pop'; pop: Pop }
  | { kind: 'note'; note: Note | null }
  | { kind: 'miss'; miss: MissFlash }
  /** The moment's move you missed, drawn green while its note shows. */
  | { kind: 'missedBest'; move: { from: LegalMove['from']; to: LegalMove['to'] } | null }
  | { kind: 'finish'; finish: Finish };

export type Step = { session: RunSession; effects: Effect[] };

/** A run, just begun. */
export function beginSession(begun: SurvivalStart): RunSession {
  return {
    ...begun,
    prepStatus: 'on',
    prepSeen: false,
    bookTo: null,
    bookOver: false,
    bookMoves: 0,
    prepEnd: null,
    answers: [],
    prepTimes: [],
    lastScored: null,
    evalCp: null,
    ending: null,
  };
}

const unchanged = (session: RunSession): Step => ({ session, effects: [] });

/**
 * One prepared position answered: a rated result for every opening the run
 * has reached, credited to the position asked rather than wherever the move
 * went. Past where the line left the book it rates the Extensions rating;
 * a saved mistake is not rated at all, though its card still is reviewed.
 */
function tally(session: RunSession, line: string[], correct: boolean, kind: MoveKind, at: number): Step {
  const result: MoveResult = {
    mode: 'survival',
    line,
    color: session.state.run.color,
    correct,
    rated: kind !== 'mistake',
    ...(kind !== 'book' ? { ext: true } : {}),
    at,
  };
  return {
    session: { ...session, answers: [...session.answers, result] },
    effects: [{ kind: 'rate', result, earlier: session.answers }],
  };
}

/** The run is over: say how, once. The screen records it and shows the end. */
function finish(session: RunSession, ended: SurvivalRun, how: Ending): Step {
  if (session.ending) return unchanged(session);
  const clean = ended.misses.length === 0 ? session.prepEnd : null;
  return {
    session: { ...session, ending: how },
    effects: [
      {
        kind: 'finish',
        finish: { how, ended, clean, stub: !!clean && session.answers.length === 0, answers: session.answers },
      },
    ],
  };
}

/** After any move: a finished game ends the run. */
function afterMove(session: RunSession, state: SurvivalRun): Step {
  const next = { ...session, state };
  const status = positionStatus(state.run.fen);
  if (!status.gameOver) return unchanged(next);
  if (status.checkmate) return finish(next, state, { kind: fenTurn(state.run.fen) === state.run.color ? 'lost' : 'won' });
  return finish(next, state, { kind: 'draw' });
}

function then(step: Step, more: (session: RunSession) => Step): Step {
  const after = more(step.session);
  return { session: after.session, effects: [...step.effects, ...after.effects] };
}

/** What your prep has here: the moves it answers this position with. */
export function prepMoves(session: RunSession): string[] {
  return prepHere(session.source, session.state);
}

/**
 * You played one of your prepared moves, `seconds` after your turn came. The
 * position is a card on the schedule, and finding the answer reviews it,
 * graded by how long it took. `now` stamps the rated result.
 */
export function playPrepared(session: RunSession, ctx: RunContext, move: LegalMove, seconds: number, now: number): Step {
  if (session.ending) return unchanged(session);
  const { run } = session.state;
  const effects: Effect[] = [{ kind: 'buzz', pattern: 10 }];
  if (run.repertoireId) {
    effects.push({ kind: 'answered', repertoireId: run.repertoireId, fen: run.fen, san: move.san, grade: gradeForTime(seconds) });
  }
  const kind = ctx.kindOf(run.played, move.san);
  const lost = ctx.lossOf(`${positionKey(run.fen)} ${move.san}`);
  const cost = kind === 'mistake' && lost !== undefined ? moveScore(-lost) : null;
  // A saved mistake is still yours to play, and the board says what it gives away.
  if (cost) effects.push({ kind: 'pop', pop: { square: move.to, text: `−${-cost.cp}`, tone: cost.tone } });
  // Autopilot says so on the board: the tick, and the time in the grade's color.
  else if (ctx.autopilot) {
    effects.push({
      kind: 'pop',
      pop: {
        square: move.to,
        text: secondsText(seconds),
        tone: speedTone(seconds),
        found: true,
        ...(kind !== 'book' ? { ext: true } : {}),
      },
    });
  }
  let step: Step = { session: { ...session, prepTimes: [...session.prepTimes, seconds] }, effects };
  step = then(step, (s) => tally(s, run.played, true, kind, now));
  step = then(step, (s) => afterMove({ ...s, prepSeen: true }, playYours(s.state, move.san)));
  return step;
}

/**
 * The engine judged a move your prep did not have, played `seconds` after
 * your turn came. Where your prep had an answer it is a miss, logged whatever
 * the engine says; a blunder ends the run; otherwise the move stands, with
 * what it cost and what it earned said over the board.
 */
export function judgedMove(session: RunSession, ctx: RunContext, judged: Judgement, seconds: number, now: number): Step {
  if (session.ending) return unchanged(session);
  const { run } = session.state;
  const { prefs, index } = ctx;
  const expected = prepMoves(session);
  let step: Step = unchanged(session);
  if (expected.length) {
    step = tally(session, run.played, false, ctx.kindOf(run.played, expected[0]), now);
    step = {
      session: { ...step.session, prepStatus: 'off', prepEnd: null },
      effects: run.repertoireId
        ? [
            ...step.effects,
            { kind: 'missed', repertoireId: run.repertoireId, fen: run.fen, played: judged.san, expected: expected[0] },
          ]
        : step.effects,
    };
  }
  if (!judged.ok) {
    return then(step, (s) =>
      finish(s, s.state, { kind: 'blunder', played: judged.san, best: judged.best, lost: judged.lost, reply: judged.reply }),
    );
  }
  return then(step, (current) => {
    const effects: Effect[] = [];
    let s = current;
    // Past a clean prep, still in the book: a move strong players play is a
    // good opening move, prepared or not. Anything else ends the phase.
    const bookPhase = !expected.length && s.prepStatus === 'complete' && !s.bookOver;
    const book = bookPhase && isBookMove(index, run.fen, judged.san, judged.lost);
    if (bookPhase && !book) s = { ...s, bookOver: true };
    if (book) s = { ...s, bookTo: run.played.length + 1, bookMoves: s.bookMoves + 1 };
    effects.push({ kind: 'buzz', pattern: expected.length ? 14 : 10 });
    const swing = evalSwing(run.color, s.lastScored ?? judged.before, judged.after);
    s = { ...s, evalCp: judged.after, lastScored: judged.after };
    const score = prefs.moveScores && swing !== null ? moveScore(swing) : null;
    const landed = applySan(run.fen, judged.san);
    if (book && ctx.autopilot && landed) {
      effects.push({
        kind: 'pop',
        pop: { square: landed.to, text: secondsText(seconds), tone: speedTone(seconds), found: true, book: true },
      });
    } else if (score && landed) {
      effects.push({
        kind: 'pop',
        pop: { square: landed.to, text: score.cp > 0 ? `+${score.cp}` : `−${-score.cp}`, tone: score.tone },
      });
    }
    if (expected.length) {
      const right = applySan(run.fen, expected[0]);
      if (right) effects.push({ kind: 'miss', miss: { expected: expected[0], from: right.from, to: right.to } });
    }
    // Moments are a thing past your prep; a prepared position is the prep's to judge.
    // A book move keeps the combo going whatever the engine's own preference.
    const scored = judgedExtras(s.state.extras, prefs, run.color, {
      lost: book ? 0 : judged.lost,
      after: judged.after,
      moment: judged.moment && !expected.length,
      found: judged.found,
      fen: landed?.after,
    });
    effects.push({ kind: 'note', note: noteFor(scored.earned, judged.best) });
    const shown = scored.earned.moment && !scored.earned.moment.found && judged.best ? applySan(run.fen, judged.best) : null;
    effects.push({ kind: 'missedBest', move: shown ? { from: shown.from, to: shown.to } : null });
    const moved = afterMove(s, playYours(s.state, judged.san, expected[0], scored.extras));
    return { session: moved.session, effects: [...effects, ...moved.effects] };
  });
}

/**
 * The opponent's turn, from the book while it has a move: steered along the
 * drawn line, redrawn by the same steer when you have stepped off it. Null
 * when the book has nothing here, and the engine plays instead.
 */
export function bookTurn(session: RunSession, index: ReferenceIndex, rng: () => number): Step | null {
  if (session.ending) return unchanged(session);
  const { run } = session.state;
  const offLine = run.target.length <= run.played.length;
  const steered = offLine ? { ...session.state, run: session.redraw(run) } : session.state;
  const san = bookReply(session.source, index, steered, rng);
  if (!san) return null;
  return afterMove(session, playTheirs(steered, san));
}

/** The engine's move for the opponent, where the book had none. */
export function engineMove(session: RunSession, san: string): Step {
  if (session.ending) return unchanged(session);
  return afterMove(session, playTheirs(session.state, san));
}

/**
 * Your turn with nothing prepared, having followed your prep so far: the
 * line is done. The book phase starts here if the book has the position.
 */
export function prepRanOut(session: RunSession, index: ReferenceIndex): RunSession {
  if (session.prepStatus !== 'on') return session;
  const { run } = session.state;
  return {
    ...session,
    prepStatus: 'complete',
    ...(inTheBook(index, run.fen) ? { bookTo: run.played.length } : { bookOver: true }),
    // Where growing would start, even when the prep asked you nothing.
    ...(session.state.misses.length ? {} : { prepEnd: run.played }),
  };
}

/** Whether the book phase has reached a position the book has nothing for, whoever left it. */
export function bookRanOut(session: RunSession, index: ReferenceIndex): boolean {
  return session.prepStatus === 'complete' && session.bookTo !== null && !session.bookOver && !inTheBook(index, session.state.run.fen);
}

/** Your turn where the book has run out: the book phase is over. */
export function closeBook(session: RunSession, index: ReferenceIndex): RunSession {
  return bookRanOut(session, index) ? { ...session, bookOver: true } : session;
}

/** Where the prep runs out, the first mission is set from the eval in front of you. */
export function missionFrom(session: RunSession, prefs: SurvivalPrefs, cp: number): RunSession {
  if (prepMoves(session).length) return session;
  const { run } = session.state;
  const extras = firstMission(session.state.extras, prefs, run.color, cp, run.fen);
  return extras === session.state.extras ? session : { ...session, state: { ...session.state, extras } };
}

/**
 * The run as one round for the score, against the deepest opening its line
 * reached in the region it was drawn from. A blunder counts as an answer
 * that was not right. A clean finish is your prep played to its end without
 * a miss, whatever the game did after it, and not a stub; its line is the
 * one finished, otherwise the line the opponent was steering toward.
 */
export function runRound(finish: Finish, tree: OpeningTree): Omit<RoundRecord, 'at'> {
  const { how, ended, clean, stub, answers } = finish;
  const line = ended.run.played;
  return {
    mode: 'survival',
    openingId: deepestNodeWithin(tree, nodeById(tree, ended.run.openingId), line).id,
    color: ended.run.color,
    answered: ended.moves + (how.kind === 'blunder' ? 1 : 0),
    correct: ended.moves,
    perfect: !!clean && !stub,
    line: clean ?? ended.run.target,
    prep: { asked: answers.length, found: answers.filter((answer) => answer.correct).length },
  };
}

/** You ended the run yourself. */
export function endRun(session: RunSession): Step {
  return finish(session, session.state, { kind: 'ended' });
}

/** What the prompt says of your prep: the book phase and after, or the prep status. */
export function prepLabel(session: RunSession): 'on' | 'complete' | 'off' | 'book' | 'out' | null {
  const { prepStatus, bookTo, bookOver } = session;
  if (prepStatus === 'complete' && bookTo !== null && !bookOver) return 'book';
  if (prepStatus === 'complete' && bookOver) return 'out';
  if (session.prepSeen || prepStatus === 'off' || (prepStatus === 'on' && prepMoves(session).length > 0)) return prepStatus;
  return null;
}

/** What a judged move earned, said over the board: a moment settled, a mission ended, the combo. */
export function noteFor(earned: Earned, best: string | null): { text: string; tone: 'good' | 'bad' } | null {
  const parts: { text: string; good: boolean }[] = [];
  if (earned.moment) {
    parts.push(
      earned.moment.found
        ? { text: `Found it · +${earned.moment.bonus}`, good: true }
        : { text: best ? `Missed it · ${best} was there` : 'Missed it', good: false },
    );
  }
  if (earned.mission) {
    parts.push(
      earned.mission.result === 'done'
        ? { text: `${missionTitle(earned.mission.kind)} complete · +${earned.mission.bonus}`, good: true }
        : { text: `${missionTitle(earned.mission.kind)} failed`, good: false },
    );
  }
  if (!earned.moment && earned.combo === 'broke') parts.push({ text: 'Combo broken', good: false });
  if (!parts.length) return null;
  return { text: parts.map((part) => part.text).join(' · '), tone: parts.every((part) => part.good) ? 'good' : 'bad' };
}

/** Whose turn it is in the run: the player's, or the opponent's. */
export function playersTurn(session: RunSession): boolean {
  return fenTurn(session.state.run.fen) === (session.state.run.color as Color);
}

/** The engine's score for the position in front of you, White's side: it steers the glow. */
export function sawEval(session: RunSession, cp: number): RunSession {
  return session.evalCp === cp ? session : { ...session, evalCp: cp };
}
