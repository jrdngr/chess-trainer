import { useEffect, useMemo, useRef, useState } from 'react';
import { Board } from '../../components/Board';
import { useLens } from '../../components/Lenses';
import { useCashOutCard, usePlanCard } from '../../components/PlanCards';
import { CASH_OUT_FROM } from '../../engine/cashOut';
import { newlyLoose } from '../../model/boardHints';
import { AppBar, haptic } from '../../components/ui';
import { ClockHud, useMoveClock } from '../../components/Clock';
import { selectionText, selectionTrail } from '../../components/Selection';
import { IntroPlate, PrepSegments } from '../../components/OpeningPlate';
import { prepDepth, type PrepSpan } from '../../model/autopilot';
import {
  applySan,
  fenTurn,
  lastMoveOf,
  positionKey,
  positionStatus,
  sansToMoveText,
  walkSan,
  type LegalMove,
} from '../../chess/core';
import { clockSeconds, fullLine, weaknessFromCards, type LineSource } from '../../model/openingRun';
import type { Color } from '../../chess/core';
import { deepestNodeWithin, nodeById, openingTree } from '../../model/openingTree';
import { referenceIndex } from '../../model/referenceIndex';
import { evidenceFor } from '../../model/growth';
import { bookLength, lossesIn, playedKinds, type MoveKind } from '../../model/extensions';
import { nodeStats, ratedNodes, seenIn, type MoveResult } from '../../model/scoring';
import { growOfferAt, offerOpening, type GrowOffer } from '../../model/growOffer';
import type { Selection } from '../../model/selection';
import { useRatingTracker } from '../../components/Ratings';
import { useHeaderRating } from '../../components/ScoreBar';
import { GrowthScreen } from '../growth/GrowthScreen';
import { gradeForTime } from '../../model/srs';
import { mulberry32 } from '../../model/session';
import {
  bookReply,
  comboMultiplier,
  firstMission,
  glowFor,
  inTheBook,
  isBookMove,
  judgedExtras,
  missionText,
  missionTitle,
  type Earned,
  evalSwing,
  moveScore,
  playTheirs,
  playYours,
  prepHere,
  prepSummary,
  secondsText,
  speedTone,
  startSurvival,
  type SurvivalPrefs,
  type SurvivalRecord,
  type SurvivalRun,
  type SurvivalStart,
  type ScoreTone,
} from '../../model/survival';
import { evidenceIn, takeRoundSelection } from '../../store/recommendation';
import { repertoireList, useStore } from '../../store/useStore';
import type { TidyFind } from '../../model/tidy';
import { useOpponent } from '../openingRun/useOpponent';
import { End, type Ending } from './End';
import { Setup } from './Setup';
import { useJudge } from './useJudge';
import { useModePrefs } from '../modePrefs';
import { introOpening, useRoundIntro } from '../../components/RoundIntro';

type Phase = 'setup' | 'playing' | 'over' | 'growing';

/** How long a run's last rating change stays on screen before the end screen: a tier drop's flash and shrink. */
const RATING_LINGER_MS = 1700;

/**
 * Where you stand against your prep: on it, through to the end of the line,
 * or off it. Latched: once complete or off, it stays that way for the run.
 */
type PrepStatus = 'on' | 'complete' | 'off';

const PREP_STATUS: Record<PrepStatus | 'book' | 'out', { text: string; color: string }> = {
  on: { text: 'On prep', color: 'var(--warn)' },
  complete: { text: 'Prep complete', color: 'var(--good)' },
  off: { text: 'Off prep', color: 'var(--bad)' },
  book: { text: 'In the book', color: 'var(--book)' },
  // Past a clean prep and the book after it: the engine judges from here.
  out: { text: 'Out of book', color: 'var(--text-2)' },
};

/** How long a miss stays over the board before the game goes on. */
const MISS_MS = 2000;

/** How long a move's score floats over its square. */
const SCORE_MS = 1400;

/** How long a moment's banner, or what a move earned, stays over the board. */
const NOTE_MS = 1600;

/** How long the Undefended flash holds your move before it lands. */
const FLASH_MS = 1300;

/** What a judged move earned, said over the board: a moment settled, a mission ended, the combo. */
function noteFor(earned: Earned, best: string | null): { text: string; tone: 'good' | 'bad' } | null {
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

/**
 * What one of your moves cost, floating up from the square it landed on — or,
 * in Autopilot, a prepared move found, ticked, with how long it took.
 */
interface ScorePop {
  key: number;
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

/**
 * What Autopilot decided a run should be: the side, the opening to walk
 * toward and whether to start inside it, and what My lines leans toward.
 */
export interface SurvivalPlan {
  color: Color;
  toward: string;
  enter: boolean;
  lean: 'popular' | 'weak';
  /** The moves to a position to start at, played for you: one your cards say is due. */
  at?: string[] | null;
}

interface Game {
  source: LineSource;
  state: SurvivalRun;
  redraw: SurvivalStart['redraw'];
}

/** A miss being shown: the prepared move, drawn as a green arrow on the board. */
interface MissFlash {
  expected: string;
  from: LegalMove['from'];
  to: LegalMove['to'];
}

/**
 * Survival: from move one until your first blunder.
 *
 * Your prep referees the positions it has an answer to; everywhere else, and
 * wherever you play something your prep does not have, the engine judges. A
 * blunder ends the run. A sound move where your prep had another is a miss:
 * it flashes over the board with the prepared move in green, is logged for
 * review, and the game goes on. Mate or a draw ends a run too.
 *
 * It is the one mode that rates: every prepared position answered moves the
 * rating of every opening the run's line reaches, up for your prep move and
 * down for a miss, and nothing past your prep counts. An opening the line
 * reaches later in the run takes the answers that led there. A run that gets to
 * the end of your prep without a miss is a clean finish of that line, which
 * is what Growth's readiness reads, and its end screen offers to grow from
 * where the prep ran out. It adds nothing to the repertoire itself, and keeps
 * its own record of moves survived.
 *
 * Opened by Autopilot it skips setup: the plan says what to run, your saved
 * options say how, and the end screen's Next run is Autopilot's next round.
 */
export function SurvivalScreen({
  onExit,
  onAnalyze,
  onTidy,
  onPractice,
  plan,
  scope,
  onNext,
}: {
  onExit: () => void;
  /** Leave for the Analysis tab on this line, seen from this side. */
  onAnalyze: (sans: string[], side: 'w' | 'b') => void;
  /** Leave for Tidy, open on a miss that was closer to your other lines. */
  onTidy?: (find: TidyFind) => void;
  /** Growth's way back, when it was opened from here: Autopilot on what was grown. */
  onPractice?: (scope: Selection) => void;
  /** Autopilot's round: what to run, in place of the setup screen. */
  plan?: SurvivalPlan;
  /** The selection the round runs in, in place of the saved one. */
  scope?: Selection;
  /** Autopilot's next round, in place of another run. */
  onNext?: () => void;
}) {
  const state = useStore();
  const { settings, cards } = state;
  const recordMove = useStore((s) => s.recordMove);
  const settleRun = useStore((s) => s.settleRun);
  const endRound = useStore((s) => s.endRound);
  const endSurvival = useStore((s) => s.endSurvival);
  const endSurvivalEarly = useStore((s) => s.endSurvivalEarly);
  const answered = useStore((s) => s.answeredInOpeningRun);
  const missed = useStore((s) => s.missedInOpeningRun);
  const index = referenceIndex();
  const tree = openingTree(index);
  /** What the engine said of your saved moves, for telling an extension's mistakes apart. */
  const losses = useMemo(() => lossesIn(repertoireList(state)), [state.repertoires]);
  /** What the move `san` is where `line` stands: book, or one of the extension kinds. */
  const kindOf = (line: string[], san: string): MoveKind => playedKinds(index, [...line, san], losses).at(-1) ?? 'book';
  /** What your games say, read once a visit, for the steers. */
  const [evidence] = useState(() => evidenceIn(state));

  const [phase, setPhase] = useState<Phase>('setup');
  const modes = useModePrefs();
  const [prefs, setPrefs] = useState<SurvivalPrefs>(modes.survival);
  /** With moments, missions or the combo on, a run is scored in points as well as moves. */
  const scoredInPoints = prefs.moments || prefs.missions || prefs.combo;
  const [game, setGame] = useState<Game | null>(null);
  const [ending, setEnding] = useState<Ending | null>(null);
  const [before, setBefore] = useState<SurvivalRecord>(state.survival);
  const [thinking, setThinking] = useState(false);
  /** The book has nothing for the opponent here, so the engine plays. */
  const [engineTurn, setEngineTurn] = useState(false);
  const [miss, setMiss] = useState<MissFlash | null>(null);
  const [pop, setPop] = useState<ScorePop | null>(null);
  /** What your last judged move earned, or "There's something here", over the board. */
  const [note, setNote] = useState<{ key: number; text: string; tone: 'good' | 'bad' | 'accent' } | null>(null);
  /** The moment's move you missed, drawn green while its note shows. */
  const [missedBest, setMissedBest] = useState<{ from: LegalMove['from']; to: LegalMove['to'] } | null>(null);
  const [prepStatus, setPrepStatus] = useState<PrepStatus>('on');
  /** Whether your prep has answered anything yet this run: with nothing prepared, there is no status to show. */
  const [prepSeen, setPrepSeen] = useState(false);
  /**
   * The book phase, once a clean prep runs out: the ply count it has reached
   * (null before it begins), and whether it is over — at your first move that
   * is not a book move, or where the book has nothing. See `BOOK_SHARE`.
   */
  const [bookTo, setBookTo] = useState<number | null>(null);
  const [bookOver, setBookOver] = useState(false);
  /** Book moves played this run, for the end screen. */
  const bookMovesPlayed = useRef(0);
  /** How long your move took, kept from the moment you played it while the engine judges it. */
  const judgedSeconds = useRef(0);
  /** The engine's last word on the game, White's side, for the glow. */
  const [evalCp, setEvalCp] = useState<number | null>(null);
  /** The engine's score after your last scored move, White's side: where the next popup counts from. */
  const lastScored = useRef<number | null>(null);
  const picker = useRef(mulberry32(Math.floor(Math.random() * 2 ** 31)));
  /** True once the run has ended, so a late verdict or engine move lands nowhere. */
  const over = useRef(false);
  /**
   * The line as it stood when your prep ran out without a miss: a clean
   * finish, and where growing it would start. Null until then, and for good
   * once you miss.
   */
  const prepEnd = useRef<string[] | null>(null);
  const [growOffer, setGrowOffer] = useState<GrowOffer | null>(null);
  const ratings = useRatingTracker();
  /** This run's rated answers, which an opening the line reaches later takes too. */
  const answers = useRef<MoveResult[]>([]);
  /** How long each prepared move you found took, in seconds: Autopilot's speed. */
  const prepTimes = useRef<number[]>([]);

  const run = game?.state.run ?? null;
  /**
   * Autopilot's measure of the run: how far into your prep it stands, out of
   * how far your prep goes along the line it is on. Held where it was once
   * you step off your prep.
   */
  const spanHeld = useRef<PrepSpan | null>(null);
  const span = useMemo(() => {
    if (!plan || !game) return null;
    const now = game.state.run;
    if (prepStatus !== 'off') {
      const total = prepDepth(fullLine(game.source, now), now.color, (fen) => game.source.prepAt(fen), now.opened);
      const book = prepStatus === 'complete' && bookTo !== null ? Math.max(0, bookTo - total) : 0;
      // Where the prep leaves the book, its segments from there on are drawn as an extension.
      const ext = bookLength(playedKinds(index, fullLine(game.source, now).slice(0, total), losses));
      spanHeld.current = {
        played: Math.min(now.played.length, total),
        total,
        ...(book ? { book } : {}),
        ...(ext < total ? { ext } : {}),
      };
    }
    return spanHeld.current;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [plan, game, prepStatus, bookTo, losses]);
  /**
   * Each run is announced, and one started inside an opening has its way in
   * played out first. A run from move one is named by the opening it is
   * steered toward. Autopilot's is announced by its plate, with no mode.
   */
  const introId = run ? (run.enteredIn ?? (plan ? plan.toward : introOpening(run.openingId, run.played.slice(0, run.opened)))) : '';
  const intro = useRoundIntro(
    phase === 'playing' && run
      ? {
          key: run.id,
          mode: 'Survival',
          opening: introId,
          plate: plan ? (
            <IntroPlate name={openingName(introId)} sans={nodeById(tree, introId).sans} color={run.color} span={span} />
          ) : undefined,
          color: run.color,
          path: run.played.slice(0, run.opened),
        }
      : null,
    (game?.state.moves ?? 0) > 0,
  );
  /** The opening the header names, whose rating rides along its bottom edge. */
  const headerOpening = run ? (run.enteredIn ?? run.openingId) : '';
  const played = run?.played;
  const headerReached = useMemo(
    () => !!played && ratedNodes(tree, played).includes(headerOpening),
    [tree, played, headerOpening],
  );
  const headerRating = useHeaderRating(headerOpening, headerReached);
  /** The header's rating as last drawn, so a run that ends by moving it can show that first. */
  const drawnRating = useRef(0);
  drawnRating.current = useStore((s) => nodeStats(s.score, headerOpening).rating);
  /** Holds the end screen back while the header plays the run's last rating change. */
  const lingerTimer = useRef<number | null>(null);
  useEffect(() => () => {
    if (lingerTimer.current) window.clearTimeout(lingerTimer.current);
  }, []);
  /** Under way: past the intro, and not over. Nothing moves and no clock runs until then. */
  const live = phase === 'playing' && !!run && !intro.held;
  const myTurn = !!run && fenTurn(run.fen) === run.color;

  const buzz = (pattern: number | number[]) => {
    if (settings.hapticFeedback) haptic(pattern);
  };

  /** The run is over: log it once and show the end screen. */
  const finish = (ended: SurvivalRun, how: Ending) => {
    if (over.current) return;
    over.current = true;
    setBefore(useStore.getState().survival);
    const line = ended.run.played;
    // A run you end yourself is counted, but says nothing about how long you survive.
    if (how.kind === 'ended') endSurvivalEarly(line);
    else endSurvival(line, ended.moves, scoredInPoints ? ended.extras.points : ended.moves);
    ratings.track(settleRun(answers.current, line));
    const region = nodeById(tree, ended.run.openingId);
    const clean = ended.misses.length === 0 ? prepEnd.current : null;
    // Prep that asked you nothing is an opening saved as its own moves: an
    // offer to grow it, but not a clean finish of anything.
    const stub = !!clean && answers.current.length === 0;
    endRound({
      mode: 'survival',
      openingId: deepestNodeWithin(tree, region, line).id,
      color: ended.run.color,
      answered: ended.moves + (how.kind === 'blunder' ? 1 : 0),
      correct: ended.moves,
      // A clean finish is your prep played to its end without a miss,
      // whatever the game did after it.
      perfect: !!clean && !stub,
      line: clean ?? ended.run.target,
      prep: { asked: answers.current.length, found: answers.current.filter((answer) => answer.correct).length },
    });
    setGrowOffer(clean ? offerFor(ended.run.color, ended.run.enteredIn, ended.run.openingId, clean, stub) : null);
    buzz(how.kind === 'blunder' || how.kind === 'lost' ? [22, 60, 22] : 14);
    setEnding(how);
    setMiss(null);
    setPop(null);
    setNote(null);
    setMissedBest(null);
    setEngineTurn(false);
    setThinking(false);
    // A last answer (or the run's catch-up) that moved the header's rating
    // plays out on the bar before the end screen covers it.
    const moved = nodeStats(useStore.getState().score, headerOpening).rating !== drawnRating.current;
    if (moved && how.kind !== 'ended') {
      lingerTimer.current = window.setTimeout(() => setPhase('over'), RATING_LINGER_MS);
    } else {
      setPhase('over');
    }
  };

  /** After any move: a finished game ends the run. */
  const afterMove = (next: Game) => {
    setGame(next);
    const { run: now } = next.state;
    const status = positionStatus(now.fen);
    if (!status.gameOver) return;
    if (status.checkmate) finish(next.state, { kind: fenTurn(now.fen) === now.color ? 'lost' : 'won' });
    else finish(next.state, { kind: 'draw' });
  };

  /**
   * One prepared position answered: a rated result for every opening the run
   * has reached, credited to the position asked rather than wherever the move
   * went. Past where the line left the book it rates the Extensions rating;
   * a saved mistake is not rated at all, though its card still is reviewed.
   */
  const tally = (line: string[], correct: boolean, kind: MoveKind) => {
    if (!run) return;
    const result: MoveResult = {
      mode: 'survival',
      line,
      color: run.color,
      correct,
      rated: kind !== 'mistake',
      ...(kind !== 'book' ? { ext: true } : {}),
      at: Date.now(),
    };
    ratings.track(recordMove(result, answers.current));
    answers.current = [...answers.current, result];
  };

  /** The way into Growth a clean end of prep earns — see `growOfferAt`. */
  const offerFor = (
    color: Color,
    enteredIn: string | null | undefined,
    openingId: string,
    played: string[],
    stub = false,
  ) => {
    const now = useStore.getState();
    const rep = repertoireList(now).find((r) => r.color === color);
    if (!rep) return null;
    const entered = enteredIn ? nodeById(tree, enteredIn) : null;
    return growOfferAt({
      rep,
      index,
      tree,
      opening: offerOpening(tree, nodeById(tree, openingId), entered, played),
      played,
      rounds: now.score.rounds,
      growth: modes.growth,
      starred: now.settings.favoriteOpenings,
      stub,
    });
  };

  const judge = useJudge({
    fen: live && myTurn ? run.fen : null,
    color: run?.color ?? 'w',
    // Kept warm where the engine is sure to be asked: past your prep.
    active: live && myTurn && !!game && prepHere(game.source, game.state).length === 0,
    moments: prefs.moments,
    onJudged: (judged) => {
      if (!game || !run || over.current) return;
      const expected = prepHere(game.source, game.state);
      if (expected.length) {
        // A move your prep does not have, where it had one: a miss, logged
        // now whatever the engine says, because the drill lives in review.
        tally(run.played, false, kindOf(run.played, expected[0]));
        setPrepStatus('off');
        prepEnd.current = null;
        if (run.repertoireId) missed(run.repertoireId, run.fen, judged.san, expected[0]);
      }
      if (!judged.ok) {
        finish(game.state, { kind: 'blunder', played: judged.san, best: judged.best, lost: judged.lost });
        return;
      }
      // Past a clean prep, still in the book: a move strong players play is a
      // good opening move, prepared or not. Anything else ends the phase.
      const bookPhase = !expected.length && prepStatus === 'complete' && !bookOver;
      const book = bookPhase && isBookMove(index, run.fen, judged.san, judged.lost);
      if (bookPhase && !book) setBookOver(true);
      if (book) {
        setBookTo(run.played.length + 1);
        bookMovesPlayed.current += 1;
      }
      buzz(expected.length ? 14 : 10);
      setEvalCp(judged.after);
      const swing = evalSwing(run.color, lastScored.current ?? judged.before, judged.after);
      lastScored.current = judged.after;
      const score = prefs.moveScores && swing !== null ? moveScore(swing) : null;
      const landed = applySan(run.fen, judged.san);
      if (book && plan && landed) {
        const seconds = judgedSeconds.current;
        setPop({ key: Date.now(), square: landed.to, text: secondsText(seconds), tone: speedTone(seconds), found: true, book: true });
      } else if (score && landed) {
        setPop({ key: Date.now(), square: landed.to, text: score.cp > 0 ? `+${score.cp}` : `−${-score.cp}`, tone: score.tone });
      }
      if (expected.length) {
        const right = applySan(run.fen, expected[0]);
        if (right) setMiss({ expected: expected[0], from: right.from, to: right.to });
      }
      // Moments are a thing past your prep; a prepared position is the prep's to judge.
      // A book move keeps the combo going whatever the engine's own preference.
      const scored = judgedExtras(game.state.extras, prefs, run.color, {
        lost: book ? 0 : judged.lost,
        after: judged.after,
        moment: judged.moment && !expected.length,
        found: judged.found,
        fen: applySan(run.fen, judged.san)?.after,
      });
      const told = noteFor(scored.earned, judged.best);
      setNote(told ? { key: Date.now(), ...told } : null);
      const shown = scored.earned.moment && !scored.earned.moment.found && judged.best ? applySan(run.fen, judged.best) : null;
      setMissedBest(shown ? { from: shown.from, to: shown.to } : null);
      afterMove({ ...game, state: playYours(game.state, judged.san, expected[0], scored.extras) });
    },
  });

  useOpponent({
    fen: run?.fen ?? null,
    enabled: live && engineTurn && !myTurn && !miss,
    onMove: (san) => {
      if (!game || over.current) return;
      setEngineTurn(false);
      afterMove({ ...game, state: playTheirs(game.state, san) });
    },
  });

  /**
   * A moment: one move here is far better than the rest. Said over the board
   * when your turn comes, with the clock held while it shows.
   */
  const momentHere =
    prefs.moments &&
    live &&
    myTurn &&
    !judge.pending &&
    !!run &&
    !!game &&
    judge.momentAt === run.fen &&
    prepHere(game.source, game.state).length === 0;
  useEffect(() => {
    if (momentHere) setNote({ key: Date.now(), text: "There's something here", tone: 'accent' });
  }, [momentHere]);
  const momentShowing = momentHere && note?.tone === 'accent';

  const clock = useMoveClock({
    seconds: clockSeconds(prefs.clock),
    turnKey: `${run?.id ?? ''}:${run?.played.length ?? 0}`,
    active: live && myTurn && !judge.pending && !momentShowing,
  });

  /** A move held back by the Undefended flash: what it leaves loose, and a moment to take it back. */
  const [flash, setFlash] = useState<{ move: LegalMove; loose: LegalMove['to'][] } | null>(null);

  /** Your move stands on the board while the engine judges it, or while the flash holds it. */
  const shownFen = !run
    ? null
    : flash
      ? flash.move.after
      : judge.pending
        ? (applySan(run.fen, judge.pending.san)?.after ?? run.fen)
        : run.fen;
  const shownLine = !run ? [] : flash ? [...run.played, flash.move.san] : judge.pending ? [...run.played, judge.pending.san] : run.played;
  const prevFen = useMemo(() => {
    if (!shownLine.length) return null;
    const { fens } = walkSan(shownLine.slice(0, -1));
    return fens[fens.length - 1];
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [shownLine.join(' ')]);
  // The flash holds the move for a moment, then it lands unless taken back.
  useEffect(() => {
    if (!flash) return;
    const timer = window.setTimeout(() => {
      setFlash(null);
      commitRef.current?.(flash.move);
    }, FLASH_MS);
    return () => window.clearTimeout(timer);
  }, [flash]);
  /** The latest commit, for the flash's timer to call once it runs out. */
  const commitRef = useRef<((move: LegalMove) => void) | null>(null);

  const lens = useLens({
    fen: shownFen ?? '',
    me: run?.color ?? 'w',
    prevFen,
    enabled: phase === 'playing' && !!run && !intro.fen,
  });

  // The opponent answers after a beat, and not while a miss is on the board.
  // From the book while it has a move — steered along the drawn line, redrawn
  // by the same steer when you have stepped off it — then the engine.
  useEffect(() => {
    if (!game || !run || !live || myTurn || miss || engineTurn || over.current) return;
    setThinking(true);
    const timer = setTimeout(() => {
      setThinking(false);
      if (over.current) return;
      const offLine = run.target.length <= run.played.length;
      const steered = offLine ? { ...game.state, run: game.redraw(run) } : game.state;
      const san = bookReply(game.source, index, steered, picker.current);
      if (!san) {
        setEngineTurn(true);
        return;
      }
      afterMove({ ...game, state: playTheirs(steered, san) });
    }, 420);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [game, live, myTurn, miss, engineTurn]);

  // Your turn with nothing prepared, having followed your prep so far: the line is done.
  const prepRanOut = live && myTurn && !judge.pending && !!game && prepHere(game.source, game.state).length === 0;
  useEffect(() => {
    if (!prepRanOut || prepStatus !== 'on') return;
    setPrepStatus('complete');
    if (run && inTheBook(index, run.fen)) setBookTo(run.played.length);
    else setBookOver(true);
    // Where growing would start, even when the prep asked you nothing.
    if (run && !game?.state.misses.length) prepEnd.current = run.played;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [prepRanOut]);

  // The book phase ends where the book has nothing more to say, whoever left it.
  const bookRanOut = live && myTurn && prepStatus === 'complete' && bookTo !== null && !bookOver && !inTheBook(index, run.fen);
  useEffect(() => {
    if (bookRanOut) setBookOver(true);
  }, [bookRanOut]);
  const inBook = prepStatus === 'complete' && bookTo !== null && !bookOver;
  const outOfBook = prepStatus === 'complete' && bookOver;

  // The engine's score for the position in front of you steers the glow.
  const baselineCp = judge.baseline && run && judge.baseline.fen === run.fen ? judge.baseline.cp : null;
  useEffect(() => {
    if (baselineCp !== null) setEvalCp(baselineCp);
  }, [baselineCp]);

  // Past the end of prep: the plan for the structure on the board, and Cash out when well ahead.
  const pastPrep = prepStatus !== 'on';
  const planCard = usePlanCard({
    fen: shownFen ?? '',
    me: run?.color ?? 'w',
    enabled: phase === 'playing' && !!run && pastPrep && !intro.held,
    resetKey: run?.id ?? '',
  });
  const myCp = baselineCp === null || !run ? null : run.color === 'w' ? baselineCp : -baselineCp;
  const cashOut = useCashOutCard({
    fen: run?.fen ?? '',
    me: run?.color ?? 'w',
    enabled: live && myTurn && pastPrep && !judge.pending && !flash && !momentHere && myCp !== null && myCp >= CASH_OUT_FROM,
    resetKey: run?.id ?? '',
  });

  // Where the prep runs out, the first mission is set from the eval in front of you.
  useEffect(() => {
    if (!game || !run || !live || !myTurn || baselineCp === null) return;
    if (prepHere(game.source, game.state).length) return;
    const extras = firstMission(game.state.extras, prefs, run.color, baselineCp, run.fen);
    if (extras !== game.state.extras) setGame({ ...game, state: { ...game.state, extras } });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [baselineCp, live, myTurn]);

  useEffect(() => {
    if (!note) return;
    const timer = window.setTimeout(() => {
      setNote(null);
      setMissedBest(null);
    }, NOTE_MS);
    return () => window.clearTimeout(timer);
  }, [note]);

  useEffect(() => {
    if (!pop) return;
    const timer = window.setTimeout(() => setPop(null), SCORE_MS);
    return () => window.clearTimeout(timer);
  }, [pop]);

  /** A miss clears itself, and a tap clears it sooner. */
  useEffect(() => {
    if (!miss) return;
    const timer = window.setTimeout(() => setMiss(null), MISS_MS);
    return () => window.clearTimeout(timer);
  }, [miss]);

  const start = (chosen: SurvivalPrefs) => {
    // Each run starts on its own selection: "Any favorite" lands on one favorite per run.
    const selection = scope ?? takeRoundSelection(useStore.getState());
    const begun = startSurvival({
      steer: plan ? 'lines' : chosen.steer,
      tree,
      reps: repertoireList(useStore.getState()),
      node: nodeById(tree, selection.opening),
      color: plan?.color ?? selection.color,
      lean: plan?.lean,
      toward: plan ? nodeById(tree, plan.toward) : undefined,
      enter: plan?.enter,
      at: plan?.at,
      weakness: weaknessFromCards(cards, evidence),
      growth: modes.growth,
      holeWeight: evidenceFor(evidence),
      seen: seenIn(useStore.getState().score),
    });
    if (!begun) return;
    if (lingerTimer.current) window.clearTimeout(lingerTimer.current);
    over.current = false;
    prepEnd.current = null;
    ratings.reset();
    answers.current = [];
    prepTimes.current = [];
    bookMovesPlayed.current = 0;
    setBookTo(null);
    setBookOver(false);
    setGrowOffer(null);
    judge.reset();
    setPrefs(chosen);
    setEnding(null);
    setMiss(null);
    setPop(null);
    setNote(null);
    setMissedBest(null);
    setPrepStatus('on');
    setPrepSeen(false);
    setEvalCp(null);
    lastScored.current = null;
    setEngineTurn(false);
    setThinking(false);
    setGame({ source: begun.source, state: begun.state, redraw: begun.redraw });
    setPhase('playing');
  };

  // Autopilot's run starts the moment the screen opens, on your saved options.
  useEffect(() => {
    if (plan) start(modes.survival);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (phase === 'setup' || !game || !run) {
    // Autopilot's run starts itself; there is nothing to set up.
    if (plan) return <div className="screen no-nav" style={{ display: 'grid', placeItems: 'center' }}><div className="spinner" /></div>;
    return <Setup onStart={start} onExit={onExit} />;
  }

  const next = onNext ?? (() => start(prefs));

  if (phase === 'growing' && growOffer) {
    const { launch } = growOffer;
    const practice = onPractice
      ? () => onPractice({ color: run.color, opening: launch.opening.id })
      : next;
    return (
      <GrowthScreen
        onExit={onExit}
        onAnalyze={onAnalyze}
        launch={{
          row: launch.row,
          hole: launch.hole,
          region: launch.opening.id,
          backLabel: onNext ? 'Next round' : 'Practice these lines',
          onBack: onNext ?? practice,
          pointBack: growOffer.kind === 'line' ? 'batch' : 'cap',
          widened: launch.widened,
          next: onNext,
        }}
      />
    );
  }

  if (phase === 'over' && ending) {
    // Every opening the run reached was rated; the end screen names your
    // favorites and the one the run was played in, not every opening above it.
    const { run: ended } = game.state;
    const playedIn = deepestNodeWithin(tree, nodeById(tree, ended.openingId), ended.played).id;
    const shown = ratings.moved.filter(
      (change) => change.id === playedIn || settings.favoriteOpenings.includes(change.id),
    );
    return (
      <End
        name={plan ? openingName(headerOpening) : undefined}
        state={game.state}
        ending={ending}
        before={before}
        moved={shown}
        grow={growOffer ? () => setPhase('growing') : null}
        prepPly={prepEnd.current?.length ?? game.state.misses[0]?.ply ?? null}
        prep={
          plan
            ? prepSummary(
                answers.current.filter((answer) => answer.correct).length,
                answers.current.length,
                prepTimes.current,
                bookMovesPlayed.current,
              )
            : null
        }
        nextLabel={onNext ? 'Next round' : 'Next run'}
        prefs={prefs}
        onNext={next}
        onChangeOptions={plan ? undefined : () => setPhase('setup')}
        onAnalyze={() => onAnalyze(game.state.run.played, game.state.run.color)}
        onTidy={onTidy}
        onExit={onExit}
      />
    );
  }

  const onMove = (move: LegalMove) => {
    if (!live || !myTurn || judge.pending || over.current || flash) return;
    if (prefs.undefendedFlash) {
      const loose = newlyLoose(run.fen, move.after, run.color, move);
      if (loose.length) {
        buzz([12, 40, 12]);
        setFlash({ move, loose });
        return;
      }
    }
    commit(move);
  };

  const commit = (move: LegalMove) => {
    if (!live || !myTurn || judge.pending || over.current) return;
    setMiss(null);
    const prep = prepHere(game.source, game.state);
    if (prep.includes(move.san)) {
      buzz(10);
      // A position your prep answers is a card on the schedule, and finding
      // the answer reviews it, graded by how long it took.
      const seconds = clock.elapsedNow();
      if (run.repertoireId) answered(run.repertoireId, run.fen, move.san, gradeForTime(seconds));
      prepTimes.current = [...prepTimes.current, seconds];
      const kind = kindOf(run.played, move.san);
      const lost = losses.get(`${positionKey(run.fen)} ${move.san}`);
      const cost = kind === 'mistake' && lost !== undefined ? moveScore(-lost) : null;
      // A saved mistake is still yours to play, and the board says what it gives away.
      if (cost) setPop({ key: Date.now(), square: move.to, text: `−${-cost.cp}`, tone: cost.tone });
      // Autopilot says so on the board: the tick, and the time in the grade's color.
      else if (plan) {
        setPop({
          key: Date.now(),
          square: move.to,
          text: secondsText(seconds),
          tone: speedTone(seconds),
          found: true,
          ...(kind !== 'book' ? { ext: true } : {}),
        });
      }
      tally(run.played, true, kind);
      setPrepSeen(true);
      afterMove({ ...game, state: playYours(game.state, move.san) });
      return;
    }
    judgedSeconds.current = clock.elapsedNow();
    judge.submit(run.fen, move);
  };
  commitRef.current = commit;

  const glow = prefs.boardGlow && evalCp !== null ? glowFor(run.color, evalCp) : null;

  return (
    <>
      {intro.cover}
      <AppBar
        title={plan ? openingName(headerOpening) : 'Survival'}
        subtitle={
          plan ? (
            <PrepSegments span={span} className="bar" />
          ) : (
            <span className="sub-row">
              <span className="truncate">{selectionText(run.color, headerOpening)}</span>
              {headerRating?.label}
            </span>
          )
        }
        edge={headerRating?.edge}
        onClose={onExit}
        actions={
          <div className="row gap-6">
            {live && myTurn && <ClockHud clock={clock} />}
            {plan ? (
              <RatingGained delta={ratings.moved.find((change) => change.id === headerOpening && !change.ext)?.delta ?? 0} />
            ) : (
              <span className="chip num wide">{scoredInPoints ? game.state.extras.points : game.state.moves}</span>
            )}
          </div>
        }
      />

      <div className="screen no-nav">
        <Board
          fen={intro.fen ?? shownFen ?? run.fen}
          orientation={run.color}
          interactive={live && myTurn && !thinking && !judge.pending && !flash}
          movableFor={run.color}
          onMove={onMove}
          lastMove={intro.fen ? intro.lastMove : lastMoveOf(shownLine)}
          arrows={
            miss
              ? [{ from: miss.from, to: miss.to, color: 'var(--good)' }]
              : missedBest
                ? [{ from: missedBest.from, to: missedBest.to, color: 'var(--good)' }]
                : cashOut.arrows
          }
          showCoordinates={settings.showCoordinates}
          theme={settings.boardTheme}
          captured
          glow={glow}
          marks={lens.marks}
          overlay={
            <>
              {intro.overlay}
              {flash && (
                <>
                  {flash.loose.map((square) => (
                    <FlashRing key={square} square={square} orientation={run.color} />
                  ))}
                  <div className="board-flash top" style={{ animation: 'none' }}>
                    <button className="btn sm" onClick={() => setFlash(null)}>
                      Take back
                    </button>
                  </div>
                </>
              )}
              {/* Kept apart: the popup and the note are often set in the same millisecond, and a shared key leaks copies. */}
              {pop && <MoveScore key={`score-${pop.key}`} pop={pop} orientation={run.color} />}
              {note && !miss && (
                <div key={`note-${note.key}`} className="board-flash top pass">
                  <div className="flash-pill">
                    <div className={`verdict ${note.tone === 'good' ? 'ok' : note.tone === 'bad' ? 'no' : 'accent'}`} style={{ padding: 0 }}>
                      {note.text}
                    </div>
                  </div>
                </div>
              )}
              {miss && (
                <div className="board-flash top" onPointerDown={() => setMiss(null)}>
                  <div className="flash-pill">
                    <div className="verdict accent" style={{ padding: 0 }}>
                      Off your prep · {miss.expected} was yours
                    </div>
                  </div>
                </div>
              )}
            </>
          }
        />

        {!intro.held && lens.bar}
        {lens.legend}
        <div style={{ display: lens.legend ? 'none' : 'contents' }}>

        {intro.below ??
          (run.opened > 0 && (
            <div className="center small muted mt-8">From {sansToMoveText(run.played.slice(0, run.opened))}</div>
          ))}

        {cashOut.card}
        {planCard.card}

        <div className="spacer" />

        <div className="prompt" style={intro.held ? { visibility: 'hidden' } : undefined}>
          <div className="who">
            {thinking || judge.pending || engineTurn ? (
              <span className="spinner" />
            ) : (
              <span className={`side ${run.color}`} />
            )}
            {judge.pending ? 'Judging' : thinking || engineTurn || !myTurn ? 'Reply' : 'Your move'}
          </div>
          {inBook || outOfBook ? (
            <div className="ctx" style={{ color: PREP_STATUS[inBook ? 'book' : 'out'].color, fontWeight: 600 }}>
              {PREP_STATUS[inBook ? 'book' : 'out'].text}
            </div>
          ) : (
            (prepSeen || prepStatus === 'off' || (prepStatus === 'on' && prepHere(game.source, game.state).length > 0)) && (
              <div className="ctx" style={{ color: PREP_STATUS[prepStatus].color, fontWeight: 600 }}>
                {PREP_STATUS[prepStatus].text}
              </div>
            )
          )}
          {momentHere && (
            <div className="ctx" style={{ color: 'var(--accent)', fontWeight: 600 }}>
              There's something here
            </div>
          )}
          {prefs.missions && game.state.extras.mission && (
            <div className="ctx">{missionText(game.state.extras.mission)}</div>
          )}
          {prefs.combo && comboMultiplier(game.state.extras.combo) > 1 && (
            <div className="ctx num" style={{ color: 'var(--good)', fontWeight: 600 }}>
              Combo ×{comboMultiplier(game.state.extras.combo)}
            </div>
          )}
          {plan ? (
            // Autopilot's way out, there from the first move: ending a round at
            // the end of your prep, or after a slip, still gets the end screen.
            // Quiet, since playing on is the game.
            <button
              className="btn sm soft mt-12"
              style={{ color: 'var(--text-2)' }}
              onClick={() => finish(game.state, { kind: 'ended' })}
            >
              End round
            </button>
          ) : (
            prepStatus === 'off' && (
              <button className="btn sm mt-8" onClick={() => finish(game.state, { kind: 'ended' })}>
                End run
              </button>
            )
          )}
          {game.state.misses.length > 0 && (
            <div className="ctx">
              {game.state.misses.length} miss{game.state.misses.length === 1 ? '' : 'es'} so far
            </div>
          )}
        </div>
        </div>
      </div>
    </>
  );
}

/** An opening by the last of its trail: "Berlin Defence", not "Ruy Lopez › Berlin Defence". */
function openingName(id: string): string {
  return selectionTrail(id).at(-1) ?? '';
}

/** What this run has done to the opening's rating so far, in the app bar. */
function RatingGained({ delta }: { delta: number }) {
  const n = Math.round(delta);
  return (
    <span className={`chip num wide${n > 0 ? ' good' : n < 0 ? ' bad' : ''}`} aria-label={`Rating ${n >= 0 ? 'gained' : 'lost'} this run`}>
      {n < 0 ? `−${-n}` : `+${n}`}
    </span>
  );
}

/** A piece your held move leaves undefended, ringed while the Undefended flash shows. */
function FlashRing({ square, orientation }: { square: LegalMove['to']; orientation: 'w' | 'b' }) {
  const file = square.charCodeAt(0) - 97;
  const rank = Number(square[1]) - 1;
  const col = orientation === 'w' ? file : 7 - file;
  const row = orientation === 'w' ? 7 - rank : rank;
  return (
    <div
      className="undefended-flash"
      style={{ left: `${col * 12.5}%`, top: `${row * 12.5}%`, width: '12.5%', height: '12.5%' }}
    />
  );
}

/** A move's cost, over the square it landed on. */
function MoveScore({ pop, orientation }: { pop: ScorePop; orientation: 'w' | 'b' }) {
  const file = pop.square.charCodeAt(0) - 97;
  const rank = Number(pop.square[1]) - 1;
  const col = orientation === 'w' ? file : 7 - file;
  const row = orientation === 'w' ? 7 - rank : rank;
  return (
    <div className={`move-score ${pop.tone}${pop.ext ? ' ext' : ''}`} style={{ left: `${col * 12.5}%`, top: `${row * 12.5}%` }}>
      <span>
        {pop.found && <b className={`tick${pop.book ? ' book' : pop.ext ? ' ext' : ''}`}>✓</b>}
        {pop.book && <b className="book-word">Book</b>}
        {pop.ext && <b className="ext-word">Ext</b>}
        {pop.text}
      </span>
    </div>
  );
}
