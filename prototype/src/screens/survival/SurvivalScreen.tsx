import { useEffect, useMemo, useRef, useState } from 'react';
import { Board } from '../../components/Board';
import { useLens } from '../../components/Lenses';
import { useCashOutCard, usePlanCard } from '../../components/PlanCards';
import { CASH_OUT_FROM } from '../../engine/cashOut';
import { newlyLoose } from '../../model/boardHints';
import { AppBar, haptic, Icons } from '../../components/ui';
import { ClockHud, useMoveClock } from '../../components/Clock';
import { selectionText, selectionTrail } from '../../components/Selection';
import { IntroPlate, PrepSegments } from '../../components/OpeningPlate';
import { prepDepth, type PrepSpan } from '../../model/autopilot';
import { applySan, applyUci, lastMoveOf, sansToMoveText, walkSan, type LegalMove } from '../../chess/core';
import { clockSeconds, fullLine, weaknessFromCards } from '../../model/openingRun';
import type { Color } from '../../chess/core';
import { deepestNodeWithin, nodeById, openingTree } from '../../model/openingTree';
import { referenceIndex } from '../../model/referenceIndex';
import { evidenceFor } from '../../model/growth';
import { bookLength, lossesIn, playedKinds } from '../../model/extensions';
import { seenIn } from '../../model/scoring';
import { growOfferAt, offerOpening, type GrowOffer } from '../../model/growOffer';
import type { Selection } from '../../model/selection';
import { useRatingTracker } from '../../components/Ratings';
import { GrowthScreen } from '../growth/GrowthScreen';
import { mulberry32 } from '../../model/session';
import {
  comboMultiplier,
  glowFor,
  missionText,
  prepSummary,
  startSurvival,
  type SurvivalPrefs,
  type SurvivalRecord,
} from '../../model/survival';
import {
  beginSession,
  bookRanOut,
  bookTurn,
  closeBook,
  endRun,
  engineMove,
  judgedMove,
  missionFrom,
  playPrepared,
  playersTurn,
  prepLabel,
  prepMoves,
  prepRanOut,
  runRound,
  sawEval,
  type Finish,
  type MissFlash,
  type Note,
  type Pop,
  type PrepStatus,
  type RunContext,
  type RunSession,
  type Step,
} from '../../model/survivalController';
import { evidenceIn, takeRoundSelection } from '../../store/recommendation';
import { repertoireList, useStore } from '../../store/useStore';
import type { TidyFind } from '../../model/tidy';
import { useOpponent } from '../openingRun/useOpponent';
import { End, endingTitle } from './End';
import { Setup } from './Setup';
import { useJudge } from './useJudge';
import { useModePrefs } from '../modePrefs';
import { introOpening, useRoundIntro } from '../../components/RoundIntro';
import { env } from '../../model/env';

type Phase = 'setup' | 'playing' | 'over' | 'growing';

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

/** A move's score over its square, keyed so each one animates afresh. */
type ScorePop = Pop & { key: number };

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
 * The rules of a run live in `model/survivalController`; this screen feeds it
 * what happens, carries out what it asks, and draws the result.
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
  /** What your games say, read once a visit, for the steers. */
  const [evidence] = useState(() => evidenceIn(state));

  const [phase, setPhase] = useState<Phase>('setup');
  const modes = useModePrefs();
  const [prefs, setPrefs] = useState<SurvivalPrefs>(modes.survival);
  /** With moments, missions or the combo on, a run is scored in points as well as moves. */
  const scoredInPoints = prefs.moments || prefs.missions || prefs.combo;
  /** The run, as the controller has it. The ref is always the latest, for callbacks that land late. */
  const [session, setSession] = useState<RunSession | null>(null);
  const sessionRef = useRef<RunSession | null>(null);
  const [before, setBefore] = useState<SurvivalRecord>(state.survival);
  const [thinking, setThinking] = useState(false);
  /** The book has nothing for the opponent here, so the engine plays. */
  const [engineTurn, setEngineTurn] = useState(false);
  const [miss, setMiss] = useState<MissFlash | null>(null);
  const [pop, setPop] = useState<ScorePop | null>(null);
  /** What your last judged move earned, or "There's something here", over the board. */
  const [note, setNote] = useState<(Note & { key: number }) | null>(null);
  /** The moment's move you missed, drawn green while its note shows. */
  const [missedBest, setMissedBest] = useState<{ from: LegalMove['from']; to: LegalMove['to'] } | null>(null);
  const [picker] = useState(() => ({ current: mulberry32(Math.floor(env.random() * 2 ** 31)) }));
  const [growOffer, setGrowOffer] = useState<GrowOffer | null>(null);
  const ratings = useRatingTracker();

  const ctx: RunContext = {
    index,
    prefs,
    autopilot: !!plan,
    kindOf: (line, san) => playedKinds(index, [...line, san], line.length % 2 === 0 ? 'w' : 'b', losses).at(-1) ?? 'book',
    lossOf: (key) => losses.get(key),
  };

  const run = session?.state.run ?? null;
  const ending = session?.ending ?? null;
  const prepStatus = session?.prepStatus ?? 'on';
  const bookTo = session?.bookTo ?? null;
  /**
   * Autopilot's measure of the run: how far into your prep it stands, out of
   * how far your prep goes along the line it is on. Held where it was once
   * you step off your prep.
   */
  const spanHeld = useRef<PrepSpan | null>(null);
  const span = useMemo(() => {
    if (!plan || !session) return null;
    const now = session.state.run;
    if (prepStatus !== 'off') {
      const total = prepDepth(fullLine(session.source, now), now.color, (fen) => session.source.prepAt(fen), now.opened);
      const book = prepStatus === 'complete' && bookTo !== null ? Math.max(0, bookTo - total) : 0;
      // Where the prep leaves the book, its segments from there on are drawn as an extension.
      const ext = bookLength(playedKinds(index, fullLine(session.source, now).slice(0, total), now.color, losses));
      spanHeld.current = {
        played: Math.min(now.played.length, total),
        total,
        ...(book ? { book } : {}),
        ...(ext < total ? { ext } : {}),
      };
    }
    return spanHeld.current;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [plan, session?.state, session?.source, prepStatus, bookTo, losses]);
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
    (session?.state.moves ?? 0) > 0,
  );
  /** The opening the header names, whose rating the end screen plays. */
  const headerOpening = run ? (run.enteredIn ?? run.openingId) : '';
  /** Under way: past the intro, and not over. Nothing moves and no clock runs until then. */
  const live = phase === 'playing' && !!run && !intro.held && !ending;
  const myTurn = !!session && playersTurn(session);
  const prepNow = session ? prepMoves(session) : [];

  const buzz = (pattern: number | number[]) => {
    if (settings.hapticFeedback) haptic(pattern);
  };

  /** The run is over: log it once and show the end screen. */
  const finish = ({ how, ended, clean, stub, answers }: Finish) => {
    setBefore(useStore.getState().survival);
    const line = ended.run.played;
    // A run you end yourself is counted, but says nothing about how long you survive.
    if (how.kind === 'ended') endSurvivalEarly(line);
    else endSurvival(line, ended.moves, scoredInPoints ? ended.extras.points : ended.moves);
    ratings.track(settleRun(answers, line));
    endRound(runRound({ how, ended, clean, stub, answers }, tree));
    setGrowOffer(clean ? offerFor(ended.run.color, ended.run.enteredIn, ended.run.openingId, clean, stub) : null);
    buzz(how.kind === 'blunder' || how.kind === 'lost' ? [22, 60, 22] : 14);
    setMiss(null);
    setPop(null);
    setNote(null);
    setMissedBest(null);
    setEngineTurn(false);
    setThinking(false);
    // A blunder stays on the board with its threat until you go on (`blunderShown`).
    if (how.kind === 'blunder') return;
    setPhase('over');
  };

  /** Take the controller's step: keep its run, then do what it asks, in order. */
  const apply = ({ session: next, effects }: Step) => {
    sessionRef.current = next;
    setSession(next);
    for (const effect of effects) {
      switch (effect.kind) {
        case 'rate':
          ratings.track(recordMove(effect.result, effect.earlier));
          break;
        case 'answered':
          answered(effect.repertoireId, effect.fen, effect.san, effect.grade);
          break;
        case 'missed':
          missed(effect.repertoireId, effect.fen, effect.played, effect.expected);
          break;
        case 'buzz':
          buzz(effect.pattern);
          break;
        case 'pop':
          setPop({ key: env.now(), ...effect.pop });
          break;
        case 'note':
          setNote(effect.note ? { key: env.now(), ...effect.note } : null);
          break;
        case 'miss':
          setMiss(effect.miss);
          break;
        case 'missedBest':
          setMissedBest(effect.move);
          break;
        case 'finish':
          finish(effect.finish);
          break;
      }
    }
  };

  /** A change to the run that asks nothing of the screen. */
  const update = (next: RunSession) => {
    if (next === sessionRef.current) return;
    apply({ session: next, effects: [] });
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

  /** How long your move took, kept from the moment you played it while the engine judges it. */
  const judgedSeconds = useRef(0);

  const judge = useJudge({
    fen: live && myTurn ? run.fen : null,
    color: run?.color ?? 'w',
    // Kept warm where the engine is sure to be asked: past your prep.
    active: live && myTurn && prepNow.length === 0,
    moments: prefs.moments,
    onJudged: (judged) => {
      if (!sessionRef.current) return;
      apply(judgedMove(sessionRef.current, ctx, judged, judgedSeconds.current, env.now()));
    },
  });

  useOpponent({
    fen: run?.fen ?? null,
    enabled: live && engineTurn && !myTurn && !miss,
    onMove: (san) => {
      if (!sessionRef.current) return;
      setEngineTurn(false);
      apply(engineMove(sessionRef.current, san));
    },
  });

  /**
   * A moment: one move here is far better than the rest. Said over the board
   * when your turn comes, with the clock held while it shows.
   */
  const momentHere =
    prefs.moments && live && myTurn && !judge.pending && !!run && judge.momentAt === run.fen && prepNow.length === 0;
  useEffect(() => {
    if (momentHere) setNote({ key: env.now(), text: "There's something here", tone: 'accent' });
  }, [momentHere]);
  const momentShowing = momentHere && note?.tone === 'accent';

  const clock = useMoveClock({
    seconds: clockSeconds(prefs.clock),
    turnKey: `${run?.id ?? ''}:${run?.played.length ?? 0}`,
    active: live && myTurn && !judge.pending && !momentShowing,
  });

  /** A move held back by the Undefended flash: what it leaves loose, and a moment to take it back. */
  const [flash, setFlash] = useState<{ move: LegalMove; loose: LegalMove['to'][] } | null>(null);

  /**
   * Your move stands on the board while the engine judges it, or while the
   * flash holds it. A blunder stays there while the last rating change plays,
   * rather than vanishing before the end screen.
   */
  const held = flash?.move.san ?? judge.pending?.san ?? (phase === 'playing' && ending?.kind === 'blunder' ? ending.played : null);
  const shownFen = !run ? null : flash ? flash.move.after : held ? (applySan(run.fen, held)?.after ?? run.fen) : run.fen;
  const shownLine = !run ? [] : held ? [...run.played, held] : run.played;
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

  // The opponent answers after a beat, and not while a miss is on the board:
  // from the book while it has a move, then the engine.
  useEffect(() => {
    if (!session || !live || myTurn || miss || engineTurn || ending) return;
    setThinking(true);
    const timer = setTimeout(() => {
      setThinking(false);
      const now = sessionRef.current;
      if (!now || now.ending) return;
      const step = bookTurn(now, index, picker.current);
      if (!step) {
        setEngineTurn(true);
        return;
      }
      apply(step);
    }, 420);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session?.state, live, myTurn, miss, engineTurn]);

  // Your turn with nothing prepared, having followed your prep so far: the line is done.
  const ranOut = live && myTurn && !judge.pending && prepNow.length === 0;
  useEffect(() => {
    if (ranOut && sessionRef.current) update(prepRanOut(sessionRef.current, index));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ranOut]);

  // The book phase ends where the book has nothing more to say, whoever left it.
  const bookDone = live && myTurn && !!session && bookRanOut(session, index);
  useEffect(() => {
    if (bookDone && sessionRef.current) update(closeBook(sessionRef.current, index));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [bookDone]);
  const label = session ? prepLabel(session) : null;

  // The engine's score for the position in front of you steers the glow.
  const baselineCp = judge.baseline && run && judge.baseline.fen === run.fen ? judge.baseline.cp : null;
  useEffect(() => {
    if (baselineCp !== null && sessionRef.current) update(sawEval(sessionRef.current, baselineCp));
    // eslint-disable-next-line react-hooks/exhaustive-deps
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
    if (!sessionRef.current || !live || !myTurn || baselineCp === null) return;
    update(missionFrom(sessionRef.current, prefs, baselineCp));
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
    ratings.reset();
    setGrowOffer(null);
    judge.reset();
    setPrefs(chosen);
    setMiss(null);
    setPop(null);
    setNote(null);
    setMissedBest(null);
    setEngineTurn(false);
    setThinking(false);
    apply({ session: beginSession(begun), effects: [] });
    setPhase('playing');
  };

  // Autopilot's run starts the moment the screen opens, on your saved options.
  useEffect(() => {
    if (plan) start(modes.survival);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (phase === 'setup' || !session || !run) {
    // Autopilot's run starts itself; there is nothing to set up.
    if (plan) return <div className="screen no-nav" style={{ display: 'grid', placeItems: 'center' }}><div className="spinner" /></div>;
    return <Setup onStart={start} onExit={onExit} />;
  }
  const game = session;

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
    // The header's opening plays on its own card; the list names the rest.
    const own = ratings.moved.find((change) => change.id === headerOpening && !change.ext);
    const rating = own && nodeById(tree, headerOpening).depth > 0
      ? { id: own.id, name: openingName(headerOpening), before: own.after - own.delta, after: own.after }
      : null;
    const shown = ratings.moved.filter(
      (change) =>
        (change.id === playedIn || settings.favoriteOpenings.includes(change.id)) &&
        !(rating && change.id === rating.id && !change.ext),
    );
    return (
      <End
        name={plan ? openingName(headerOpening) : undefined}
        state={game.state}
        ending={ending}
        before={before}
        moved={shown}
        rating={rating}
        grow={growOffer ? () => setPhase('growing') : null}
        prepPly={game.prepEnd?.length ?? game.state.misses[0]?.ply ?? null}
        prep={
          plan
            ? prepSummary(
                game.answers.filter((answer) => answer.correct).length,
                game.answers.length,
                game.prepTimes,
                game.bookMoves,
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
    if (!live || !myTurn || judge.pending || ending || flash) return;
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
    const now = sessionRef.current;
    if (!live || !myTurn || judge.pending || !now || now.ending) return;
    setMiss(null);
    if (prepMoves(now).includes(move.san)) {
      apply(playPrepared(now, ctx, move, clock.elapsedNow(), env.now()));
      return;
    }
    judgedSeconds.current = clock.elapsedNow();
    judge.submit(run.fen, move);
  };
  commitRef.current = commit;

  const glow = prefs.boardGlow && game.evalCp !== null ? glowFor(run.color, game.evalCp) : null;

  /**
   * A blunder stays on the board before the end screen: your move in red, and
   * the opponent's best answer to it as a red arrow, the threat that made it
   * one. Continue goes on to the end screen.
   */
  const blunderShown = phase === 'playing' && ending?.kind === 'blunder' ? ending : null;
  const blunderMove = blunderShown ? applySan(run.fen, blunderShown.played) : null;
  const threat = blunderMove && blunderShown?.reply ? applyUci(blunderMove.after, blunderShown.reply) : null;

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
            </span>
          )
        }
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
          interactive={live && myTurn && !thinking && !held}
          movableFor={run.color}
          onMove={onMove}
          lastMove={intro.fen ? intro.lastMove : blunderMove ? null : lastMoveOf(shownLine)}
          highlights={
            blunderMove
              ? [
                  { square: blunderMove.from, kind: 'bad' },
                  { square: blunderMove.to, kind: 'bad' },
                ]
              : undefined
          }
          arrows={
            blunderShown
              ? threat
                ? [{ from: threat.from, to: threat.to, color: 'var(--bad)' }]
                : []
              : miss
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

        {!blunderShown && cashOut.card}
        {!blunderShown && planCard.card}

        <div className="spacer" />

        {blunderShown ? (
          <div className="prompt">
            <div className="verdict no" style={{ padding: 0 }}>
              <span className="ico">
                <Icons.cross size={18} />
              </span>
              {endingTitle(blunderShown, run.played.length)}
            </div>
            <button className="btn primary block mt-12" onClick={() => setPhase('over')}>
              Continue
              <Icons.next size={18} />
            </button>
          </div>
        ) : (
        <div className="prompt" style={intro.held ? { visibility: 'hidden' } : undefined}>
          <div className="who">
            {thinking || judge.pending || engineTurn ? (
              <span className="spinner" />
            ) : (
              <span className={`side ${run.color}`} />
            )}
            {judge.pending ? 'Judging' : thinking || engineTurn || !myTurn ? 'Reply' : 'Your move'}
          </div>
          {label && (
            <div className="ctx" style={{ color: PREP_STATUS[label].color, fontWeight: 600 }}>
              {PREP_STATUS[label].text}
            </div>
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
          {/* The way out, there from the first move: ending at the end of your
              prep, or after a slip, still gets the end screen. Quiet, since
              playing on is the game. */}
          <button
            className="btn sm soft mt-12"
            style={{ color: 'var(--text-2)' }}
            onClick={() => sessionRef.current && apply(endRun(sessionRef.current))}
          >
            {plan ? 'End round' : 'End run'}
          </button>
          {game.state.misses.length > 0 && (
            <div className="ctx">
              {game.state.misses.length} miss{game.state.misses.length === 1 ? '' : 'es'} so far
            </div>
          )}
        </div>
        )}
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
