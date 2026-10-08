import { useEffect, useMemo, useRef, useState } from 'react';
import { Board } from '../../components/Board';
import { AppBar, haptic } from '../../components/ui';
import { ClockHud, useMoveClock } from '../../components/Clock';
import { selectionText } from '../../components/Selection';
import {
  applySan,
  fenTurn,
  lastMoveOf,
  positionStatus,
  sansToMoveText,
  type LegalMove,
} from '../../chess/core';
import { clockSeconds, weaknessFromCards, type LineSource } from '../../model/openingRun';
import type { Color } from '../../chess/core';
import { deepestNodeWithin, nodeById, openingTree } from '../../model/openingTree';
import { referenceIndex } from '../../model/referenceIndex';
import { evidenceFor } from '../../model/growth';
import { ratedNodes, seenIn, type MoveResult } from '../../model/scoring';
import { growOfferAt, offerOpening, type GrowOffer } from '../../model/growOffer';
import type { Selection } from '../../model/selection';
import { useRatingTracker } from '../../components/Ratings';
import { useHeaderRating } from '../../components/ScoreBar';
import { GrowthScreen } from '../growth/GrowthScreen';
import { gradeForTime } from '../../model/srs';
import { mulberry32 } from '../../model/session';
import {
  bookReply,
  glowFor,
  evalSwing,
  moveScore,
  playTheirs,
  playYours,
  prepHere,
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

/**
 * Where you stand against your prep: on it, through to the end of the line,
 * or off it. Latched: once complete or off, it stays that way for the run.
 */
type PrepStatus = 'on' | 'complete' | 'off';

const PREP_STATUS: Record<PrepStatus, { text: string; color: string }> = {
  on: { text: 'On prep', color: 'var(--warn)' },
  complete: { text: 'Prep complete', color: 'var(--good)' },
  off: { text: 'Off prep', color: 'var(--bad)' },
};

/** How long a miss stays over the board before the game goes on. */
const MISS_MS = 2000;

/** How long a move's score floats over its square. */
const SCORE_MS = 1400;

/** What one of your moves cost, floating up from the square it landed on. */
interface ScorePop {
  key: number;
  square: LegalMove['to'];
  cp: number;
  tone: ScoreTone;
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
  roundName,
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
  /** What the run is announced as, when not plain Survival: Autopilot's Cold Start. */
  roundName?: string;
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
  /** What your games say, read once a visit, for the steers. */
  const [evidence] = useState(() => evidenceIn(state));

  const [phase, setPhase] = useState<Phase>('setup');
  const modes = useModePrefs();
  const [prefs, setPrefs] = useState<SurvivalPrefs>(modes.survival);
  const [game, setGame] = useState<Game | null>(null);
  const [ending, setEnding] = useState<Ending | null>(null);
  const [before, setBefore] = useState<SurvivalRecord>(state.survival);
  const [thinking, setThinking] = useState(false);
  /** The book has nothing for the opponent here, so the engine plays. */
  const [engineTurn, setEngineTurn] = useState(false);
  const [miss, setMiss] = useState<MissFlash | null>(null);
  const [pop, setPop] = useState<ScorePop | null>(null);
  const [prepStatus, setPrepStatus] = useState<PrepStatus>('on');
  /** Whether your prep has answered anything yet this run: with nothing prepared, there is no status to show. */
  const [prepSeen, setPrepSeen] = useState(false);
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

  const run = game?.state.run ?? null;
  /**
   * Each run is announced, and one started inside an opening has its way in
   * played out first. A run from move one is named by the opening it is
   * steered toward.
   */
  const intro = useRoundIntro(
    phase === 'playing' && run
      ? {
          key: run.id,
          mode: roundName ?? 'Survival',
          opening: run.enteredIn ?? (plan ? plan.toward : introOpening(run.openingId, run.played.slice(0, run.opened))),
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
    else endSurvival(line, ended.moves);
    ratings.track(settleRun(answers.current, line));
    const region = nodeById(tree, ended.run.openingId);
    const clean = ended.misses.length === 0 ? prepEnd.current : null;
    endRound({
      mode: 'survival',
      openingId: deepestNodeWithin(tree, region, line).id,
      color: ended.run.color,
      answered: ended.moves + (how.kind === 'blunder' ? 1 : 0),
      correct: ended.moves,
      // A clean finish is your prep played to its end without a miss,
      // whatever the game did after it.
      perfect: !!clean,
      line: clean ?? ended.run.target,
      prep: { asked: answers.current.length, found: answers.current.filter((answer) => answer.correct).length },
    });
    setGrowOffer(clean ? offerFor(ended.run.color, ended.run.enteredIn, ended.run.openingId, clean) : null);
    buzz(how.kind === 'blunder' || how.kind === 'lost' ? [22, 60, 22] : 14);
    setEnding(how);
    setMiss(null);
    setPop(null);
    setEngineTurn(false);
    setThinking(false);
    setPhase('over');
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
   * went.
   */
  const tally = (line: string[], correct: boolean) => {
    if (!run) return;
    const result: MoveResult = { mode: 'survival', line, color: run.color, correct, rated: true, at: Date.now() };
    ratings.track(recordMove(result, answers.current));
    answers.current = [...answers.current, result];
  };

  /** The way into Growth a clean end of prep earns — see `growOfferAt`. */
  const offerFor = (color: Color, enteredIn: string | null | undefined, openingId: string, played: string[]) => {
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
    });
  };

  const judge = useJudge({
    fen: live && myTurn ? run.fen : null,
    color: run?.color ?? 'w',
    // Kept warm where the engine is sure to be asked: past your prep.
    active: live && myTurn && !!game && prepHere(game.source, game.state).length === 0,
    onJudged: (judged) => {
      if (!game || !run || over.current) return;
      const expected = prepHere(game.source, game.state);
      if (expected.length) {
        // A move your prep does not have, where it had one: a miss, logged
        // now whatever the engine says, because the drill lives in review.
        tally(run.played, false);
        setPrepStatus('off');
        prepEnd.current = null;
        if (run.repertoireId) missed(run.repertoireId, run.fen, judged.san, expected[0]);
      }
      if (!judged.ok) {
        finish(game.state, { kind: 'blunder', played: judged.san, best: judged.best, lost: judged.lost });
        return;
      }
      buzz(expected.length ? 14 : 10);
      setEvalCp(judged.after);
      const swing = evalSwing(run.color, lastScored.current ?? judged.before, judged.after);
      lastScored.current = judged.after;
      const score = prefs.moveScores && swing !== null ? moveScore(swing) : null;
      const landed = score ? applySan(run.fen, judged.san) : null;
      if (score && landed) setPop({ key: Date.now(), square: landed.to, ...score });
      if (expected.length) {
        const right = applySan(run.fen, expected[0]);
        if (right) setMiss({ expected: expected[0], from: right.from, to: right.to });
      }
      afterMove({ ...game, state: playYours(game.state, judged.san, expected[0]) });
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

  const clock = useMoveClock({
    seconds: clockSeconds(prefs.clock),
    turnKey: `${run?.id ?? ''}:${run?.played.length ?? 0}`,
    active: live && myTurn && !judge.pending,
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
    // Only a line your prep actually asked you something on is finished.
    if (prepSeen && run && !game?.state.misses.length) prepEnd.current = run.played;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [prepRanOut]);

  // The engine's score for the position in front of you steers the glow.
  const baselineCp = judge.baseline && run && judge.baseline.fen === run.fen ? judge.baseline.cp : null;
  useEffect(() => {
    if (baselineCp !== null) setEvalCp(baselineCp);
  }, [baselineCp]);

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
      weakness: weaknessFromCards(cards, evidence),
      growth: modes.growth,
      holeWeight: evidenceFor(evidence),
      seen: seenIn(useStore.getState().score),
    });
    if (!begun) return;
    over.current = false;
    prepEnd.current = null;
    ratings.reset();
    answers.current = [];
    setGrowOffer(null);
    judge.reset();
    setPrefs(chosen);
    setEnding(null);
    setMiss(null);
    setPop(null);
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
        state={game.state}
        ending={ending}
        before={before}
        moved={shown}
        grow={growOffer?.kind === 'opening' ? { text: growOffer.text, onGrow: () => setPhase('growing') } : null}
        growLine={growOffer?.kind === 'line' ? () => setPhase('growing') : null}
        nextLabel={onNext ? 'Next round' : 'Next run'}
        onNext={next}
        onChangeOptions={plan ? undefined : () => setPhase('setup')}
        onAnalyze={() => onAnalyze(game.state.run.played, game.state.run.color)}
        onTidy={onTidy}
        onExit={onExit}
      />
    );
  }

  const onMove = (move: LegalMove) => {
    if (!live || !myTurn || judge.pending || over.current) return;
    setMiss(null);
    const prep = prepHere(game.source, game.state);
    if (prep.includes(move.san)) {
      buzz(10);
      // A position your prep answers is a card on the schedule, and finding
      // the answer reviews it.
      if (run.repertoireId) answered(run.repertoireId, run.fen, move.san, gradeForTime(clock.elapsedNow()));
      tally(run.played, true);
      setPrepSeen(true);
      afterMove({ ...game, state: playYours(game.state, move.san) });
      return;
    }
    judge.submit(run.fen, move);
  };

  /** Your move stands on the board while the engine judges it. */
  const shownFen = judge.pending ? (applySan(run.fen, judge.pending.san)?.after ?? run.fen) : run.fen;
  const shownLine = judge.pending ? [...run.played, judge.pending.san] : run.played;
  const glow = prefs.boardGlow && evalCp !== null ? glowFor(run.color, evalCp) : null;

  return (
    <>
      {intro.cover}
      <AppBar
        title="Survival"
        subtitle={
          <span className="sub-row">
            <span className="truncate">{selectionText(run.color, headerOpening)}</span>
            {headerRating?.label}
          </span>
        }
        edge={headerRating?.edge}
        onClose={onExit}
        actions={
          <div className="row gap-6">
            {live && myTurn && <ClockHud clock={clock} />}
            <span className="chip num wide">{game.state.moves}</span>
          </div>
        }
      />

      <div className="screen no-nav">
        <Board
          fen={intro.fen ?? shownFen}
          orientation={run.color}
          interactive={live && myTurn && !thinking && !judge.pending}
          movableFor={run.color}
          onMove={onMove}
          lastMove={intro.fen ? intro.lastMove : lastMoveOf(shownLine)}
          arrows={miss ? [{ from: miss.from, to: miss.to, color: 'var(--good)' }] : []}
          showCoordinates={settings.showCoordinates}
          theme={settings.boardTheme}
          captured
          glow={glow}
          overlay={
            <>
              {intro.overlay}
              {pop && <MoveScore key={pop.key} pop={pop} orientation={run.color} />}
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

        {intro.below ??
          (run.opened > 0 && (
            <div className="center small muted mt-8">From {sansToMoveText(run.played.slice(0, run.opened))}</div>
          ))}

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
          {(prepSeen || prepStatus === 'off' || (prepStatus === 'on' && prepHere(game.source, game.state).length > 0)) && (
            <div className="ctx" style={{ color: PREP_STATUS[prepStatus].color, fontWeight: 600 }}>
              {PREP_STATUS[prepStatus].text}
            </div>
          )}
          {prepStatus === 'off' && (
            <button className="btn sm mt-8" onClick={() => finish(game.state, { kind: 'ended' })}>
              End run
            </button>
          )}
          {game.state.misses.length > 0 && (
            <div className="ctx">
              {game.state.misses.length} miss{game.state.misses.length === 1 ? '' : 'es'} so far
            </div>
          )}
        </div>
      </div>
    </>
  );
}

/** A move's cost, over the square it landed on. */
function MoveScore({ pop, orientation }: { pop: ScorePop; orientation: 'w' | 'b' }) {
  const file = pop.square.charCodeAt(0) - 97;
  const rank = Number(pop.square[1]) - 1;
  const col = orientation === 'w' ? file : 7 - file;
  const row = orientation === 'w' ? 7 - rank : rank;
  return (
    <div className={`move-score ${pop.tone}`} style={{ left: `${col * 12.5}%`, top: `${row * 12.5}%` }}>
      <span>{pop.cp > 0 ? `+${pop.cp}` : `−${-pop.cp}`}</span>
    </div>
  );
}
