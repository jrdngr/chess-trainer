import { useEffect, useRef, useState } from 'react';
import { Board } from '../../components/Board';
import { AppBar, haptic, Icons, Section, toast } from '../../components/ui';
import {
  applySan,
  lastMoveOf,
  positionStatus,
  sansToMoveText,
  type LegalMove,
  type Square,
} from '../../chess/core';
import {
  atEdge,
  beginRun,
  chooseAtEdge,
  classify,
  edgeOptions,
  finishPrep,
  isComplete,
  isUsersTurn,
  keepPlaying,
  leavePrep,
  lineToKeep,
  movesHere,
  opponentReply,
  outcomeOf,
  play,
  playPast,
  playReply,
  takeHint,
  weaknessFromCards,
  type Begun,
  type DeathCause,
  type LineSource,
  type OpeningRunOptions,
  type OpeningRunPrefs,
  type Run,
} from '../../model/openingRun';
import { formatGameCount, specificNameForColor } from '../../model/reference';
import { nodeById, openingTree } from '../../model/openingTree';
import { referenceIndex } from '../../model/referenceIndex';
import { evidenceFor, movesToDraw, optionsAt } from '../../model/growth';
import { gradeForTime } from '../../model/srs';
import { selectionText } from '../../components/Selection';
import { mulberry32 } from '../../model/session';
import { evidenceIn, withSelection } from '../../store/recommendation';
import type { Selection } from '../../model/selection';
import { repertoireList, useStore } from '../../store/useStore';
import { PlayOn } from './PlayOn';
import { Reveal, type Death } from './Reveal';
import { Setup } from './Setup';
import { useReferee } from './useReferee';
import { useOpponent } from './useOpponent';
import { ClockHud, useMoveClock } from '../../components/Clock';
import { clockSeconds } from '../../model/openingRun';
import { seenIn, type RatingMove } from '../../model/scoring';
import { deepestNodeWithin } from '../../model/openingTree';
import type { RatingChange, RoundPlan, RoundSummary } from '../../model/autopilot';
import {
  growLaunch,
  holeAtEnd,
  isStubFinish,
  offerOpening,
  readyToGrow,
  yourLastMove,
  type GrowLaunch,
} from '../../model/growOffer';
import { GrowthScreen } from '../growth/GrowthScreen';

type Phase = 'setup' | 'playing' | 'gap' | 'dead' | 'survived' | 'playon' | 'growing';

interface Game {
  source: LineSource;
  run: Run;
}

/**
 * What Keep playing carries on from, once a round has ended.
 *
 *   run  — the run itself, past the prep, with the engine judging. After a
 *          sound move off your prep the move is played; at the end of your
 *          prep there was nothing to leave, so a finish stays green.
 *   game — a free game against the engine, from the position a blunder left.
 *          The run is over, so this is the play-on screen, not the run.
 *
 * Null when there is nothing to carry on: mate, a draw, or a move that ended
 * the game itself.
 */
type Onward = { kind: 'run'; run: Run } | { kind: 'game'; fen: string } | null;

/**
 * The end-of-round way into Growth, and where growing starts.
 *
 *   opening — the offer: the opening is a stub, or every line in it is
 *             finished clean. A card above Next run says why, and Growth
 *             points back once the opening owes its cap of practice.
 *   line    — the quiet button at the bottom, at any other clean end of prep:
 *             grow the line just played. Growth points back after one batch.
 */
interface GrowOffer {
  kind: 'opening' | 'line';
  text: string;
  launch: GrowLaunch;
}

/** How a round ended, as the end-of-round screen is to show it. */
interface Ending {
  /** The run as the screen shows it. */
  run: Run;
  /** What ended it short of finishing, for the red and green on the board. */
  death: Death | null;
  /** How it is graded, which is not always what the board shows. */
  cause: DeathCause | null;
  onward: Onward;
  /** Said in place of the usual verdict. */
  headline?: string;
}

/**
 * OpeningRun: the opening of a game, drilled against your prep.
 *
 * This screen owns the run and its rules — the opponent's replies, the clock,
 * hints, the book offered at the edge of the prep, and the engine as referee
 * for any move your prep does not have. Nothing on screen names the line
 * while the run is live; the reveal is the reward for the round ending.
 *
 * However a round ends — a sound move off your prep, the end of your prep, a
 * blunder, mate or a draw — it ends on the one reveal, which is also where
 * the choice to play on is yours: Keep playing and Next run, side by side
 * under the board. The round is logged the moment it ends, so playing on
 * carries on a round already counted; nothing past the prep is rated, and a
 * later ending only amends its grade. Nothing here writes to the repertoire
 * but the book offered at the edge, which is chosen up front, and the
 * reveal's one tap.
 */
export function OpeningRunScreen({
  auto,
  plan,
  onRoundOver,
  onNext,
  onExit,
  scope,
}: {
  auto?: boolean;
  /**
   * What Autopilot decided: the side, the opening to walk toward, and the
   * settings the round is played on. It holds for the whole visit, and an
   * automatic run is always on the clock, with no hints and nothing added.
   */
  plan?: RoundPlan;
  /** Logged once per round, at its first ending, whatever is played after. */
  onRoundOver?: (summary: RoundSummary) => void;
  /** Next run, when something else owns what the next round is. */
  onNext?: () => void;
  onExit: () => void;
  /** Autopilot held to one opening: the selection this visit runs in, in place of the saved one. */
  scope?: Selection;
}) {
  const state = useStore();
  const reps = repertoireList(state);
  const { settings, cards } = state;
  /**
   * What this visit runs on: the saved options, under whatever the
   * recommendation decided.
   *
   * Only the plan is held in state. The saved options stay live, so changing
   * them on the setup screen still takes effect on the next run; the plan is
   * pinned, so every run this visit is on the same terms and none of it is
   * written back as though the player had chosen it.
   */
  const [planned] = useState<RoundPlan | undefined>(() => plan);
  const prefs: OpeningRunPrefs = planned
    ? { ...settings.openingRun, ...planned.options, newMoves: 0, clock: 'move10', hints: 0 }
    : settings.openingRun;
  const endRun = useStore((s) => s.endOpeningRun);
  const recordMove = useStore((s) => s.recordMove);
  const endRound = useStore((s) => s.endRound);
  const answered = useStore((s) => s.answeredInOpeningRun);
  const missed = useStore((s) => s.missedInOpeningRun);
  const addToRep = useStore((s) => s.addLine);
  const ensureRepertoire = useStore((s) => s.ensureRepertoire);
  const index = referenceIndex();
  const tree = openingTree(index);
  const selection = scope ?? settings.selection;
  /**
   * What your games say, read once a visit: the positions you got wrong with
   * a move prepared weigh on weak-spot steering, and the ones you kept
   * reaching with nothing weigh on which gap a run walks to.
   */
  const [evidence] = useState(() => evidenceIn(withSelection(state, scope)));

  /**
   * How to steer the current run again from wherever it has got to, while it
   * is still inside its prep. Set when a run is opened, read when the
   * opponent is about to reply with no line left to follow.
   */
  const redraw = useRef<Begun['redraw'] | null>(null);

  /** A run on these options in the selected region, or null when the book is empty. */
  const open = (options: OpeningRunOptions): Game | null => {
    const begun = beginRun({
      ...options,
      tree,
      reps,
      node: nodeById(tree, selection.opening),
      toward: planned ? nodeById(tree, planned.steer) : undefined,
      color: planned?.color ?? selection.color,
      enter: planned?.start === 'inside',
      weakness: weaknessFromCards(cards, evidence),
      growth: settings.growth,
      holeWeight: evidenceFor(evidence),
      seen: seenIn(state.score),
    });
    if (!begun) return null;
    redraw.current = begun.redraw;
    return { source: begun.source, run: begun.run };
  };

  /**
   * An automatic start begins the run itself, before the first paint, so the
   * setup screen it promised to skip never flashes on the way past.
   */
  const [opened] = useState<Game | null>(() => (auto ? open(prefs) : null));
  const [phase, setPhase] = useState<Phase>(opened ? 'playing' : 'setup');
  const [game, setGame] = useState<Game | null>(opened);
  const [death, setDeath] = useState<Death | null>(null);
  const [thinking, setThinking] = useState(false);
  const [hintSquare, setHintSquare] = useState<Square | null>(null);
  const [onward, setOnward] = useState<Onward>(null);
  const [headline, setHeadline] = useState<string | null>(null);
  /** Where a game against the engine was started from, after the run. */
  const [playOnFrom, setPlayOnFrom] = useState<string | null>(null);
  const picker = useRef(mulberry32(Math.floor(Math.random() * 2 ** 31)));
  /**
   * True while play is stopped at the end of a round, so a late verdict or
   * engine move lands nowhere. Keep playing clears it.
   */
  const settled = useRef(false);
  /** True once the round has been counted, which happens once however often it ends. */
  const logged = useRef(false);
  /** True once a move off your prep was logged as a miss, so the round counts it once. */
  const slipped = useRef(false);
  /**
   * True for a round that asked you nothing: it is not logged at all, at its
   * first ending or any later one.
   */
  const uncounted = useRef(false);
  /** The offer to grow the opening, on a clean end of prep that earns one. */
  const [growOffer, setGrowOffer] = useState<GrowOffer | null>(null);
  /**
   * A clean end of prep where the book has nothing more to play, so there is
   * nothing for Growth to offer: said where "Grow this line" would be, rather
   * than leaving the button to vanish without a reason.
   */
  const [bookEnded, setBookEnded] = useState(false);

  const source = game?.source ?? null;
  const run = game?.run ?? null;
  const live = phase === 'playing';
  const myTurn = run ? isUsersTurn(run) : false;
  const extended = !!run && run.extended;
  /** The book has nothing for the opponent here, so the engine plays. */
  const engineTurn = !!source && !!run && live && extended && !myTurn && !run.over && movesHere(source, run).length === 0;

  const buzz = (pattern: number | number[]) => {
    if (settings.hapticFeedback) haptic(pattern);
  };

  /**
   * Where each rated opening stood when this run first touched it, and where
   * it stands now: the run's own doing, for the reveal. A ref as well as
   * state, because `finish` reads it in the same tick a move writes it.
   */
  const ratings = useRef(new Map<string, { before: number; after: number }>());
  const [moved, setMoved] = useState<RatingChange[]>([]);
  const movedNow = (): RatingChange[] =>
    [...ratings.current]
      .map(([id, seen]) => ({
        id,
        name: nodeById(tree, id).name,
        delta: seen.after - seen.before,
        after: seen.after,
      }))
      .filter((change) => Math.round(change.delta) !== 0);
  const track = (moves: RatingMove[]) => {
    for (const move of moves) {
      const seen = ratings.current.get(move.id);
      if (seen) seen.after = move.after;
      else ratings.current.set(move.id, { before: move.before, after: move.after });
    }
    setMoved(movedNow());
  };

  /** What the reveal's one tap wrote into the repertoire. */
  const [kept, setKept] = useState<{ name: string; added: number } | null>(null);

  /**
   * Log the round. The run's record is amended on every ending, so a blunder
   * after playing on still turns a green finish red; the round itself is
   * counted once, at the first.
   */
  const finish = (ended: Run, cause: DeathCause | null) => {
    settled.current = true;
    if (!logged.current && cause === null && isStubFinish(ended)) uncounted.current = true;
    const region = nodeById(tree, ended.openingId);
    if (uncounted.current) {
      // Nothing was asked, so nothing is logged: no round, no streak mark, no
      // clean finish. Autopilot still hears of it, so its session moves on.
      if (logged.current) return;
      logged.current = true;
      onRoundOver?.({
        openingId: deepestNodeWithin(tree, region, ended.played).id,
        color: ended.color,
        moved: [],
        answered: 0,
        correct: 0,
        perfect: false,
      });
      return;
    }
    endRun(outcomeOf(ended, cause));
    if (logged.current) return;
    logged.current = true;
    const summary: RoundSummary = {
      openingId: deepestNodeWithin(tree, region, ended.played).id,
      color: ended.color,
      moved: movedNow(),
      answered: ended.survived + (slipped.current ? 1 : 0),
      correct: ended.survived,
      perfect: cause === null && !ended.leftPrep,
    };
    endRound({ mode: 'run', ...summary, line: ended.drawn });
    onRoundOver?.(summary);
  };

  /** A prepared position found: one rated result, for every starred opening it is inside. */
  const credit = (after: Run) => {
    track(recordMove({ mode: 'run', line: after.played, color: after.color, correct: true, rated: true }));
  };

  /**
   * A prepared position missed: the same result the other way, which is what
   * makes the rating mean anything.
   *
   * The line is the position you were *asked* about, without the move you
   * played. A wrong move usually leaves the opening altogether — h6 in the
   * Najdorf is no longer a Najdorf — and crediting the miss to wherever it
   * landed would mean a rating that only ever goes up.
   */
  const debit = (ended: Run) => {
    track(recordMove({ mode: 'run', line: ended.played, color: ended.color, correct: false, rated: true }));
  };

  /**
   * Which opening the kept line belongs to.
   *
   * Only for saying where it went: the line is written into the tree for the
   * side you played, and the opening it lands in is derived from the moves
   * afterwards. An opening run has the answer already — you chose the opening.
   * A book run has no such choice, so the name comes from the side you played,
   * since "Queen's Pawn Opening" describes what a Black line's opponent did.
   */
  const openingOf = (ended: Run, line: string[]): string => {
    const named = specificNameForColor(index, line, ended.color)?.name;
    return named ?? ended.sourceLabel;
  };

  /**
   * The reveal's one tap: write the line into the repertoire. The only way a
   * finished run adds anything, and it is never taken for you.
   */
  const keep = () => {
    if (!run) return;
    const line = lineToKeep(index, run);
    if (!line.length) return;
    const repId = ensureRepertoire(run.color);
    const { added } = addToRep(repId, line, 'reference');
    const name = openingOf(run, line);
    setKept({ name, added });
    buzz(10);
    toast(added > 0 ? `${added} move${added === 1 ? '' : 's'} saved to ${name}` : 'Already in your repertoire');
  };

  /** The round is over, for now: log it and show the reveal. */
  const conclude = (ending: Ending) => {
    if (!source) return;
    setDeath(ending.death);
    setOnward(ending.onward);
    setHeadline(ending.headline ?? null);
    setGame({ source, run: { ...ending.run, over: true } });
    setPhase(ending.death ? 'dead' : 'survived');
    finish(ending.run, ending.cause);
  };

  /**
   * A blunder ends the run. Playing on is a game against the engine from the
   * position it left, unless the blunder ended the game outright.
   */
  const die = (ended: Run, how: Death) => {
    buzz([22, 60, 22]);
    const after = how.played ? applySan(ended.fen, how.played) : null;
    const open = after && !positionStatus(after.after).gameOver;
    conclude({
      run: ended,
      death: how,
      cause: how.cause,
      onward: open ? { kind: 'game', fen: after.after } : null,
    });
  };

  /**
   * The referee has run out: the end of your prep, or of the book on a run
   * through it. That completes the run and pays for it, whatever you choose
   * next — and playing on is a choice, never made for you.
   */
  const arrive = (at: Run) => {
    buzz(14);
    const done = finishPrep(at);
    conclude({ run: done, death: null, cause: null, onward: { kind: 'run', run: keepPlaying(done) } });
    const offer = offerFor(done);
    setGrowOffer(offer);
    setBookEnded(!offer && !done.leftPrep && !done.bookRun && optionsAt(index, done.fen, 1).length === 0);
  };

  /**
   * The way into Growth a clean end of prep earns: the offer, when the round
   * asked you nothing or every line in the opening has been finished clean
   * enough times since it last changed, and otherwise the quiet button, when
   * the round ended on a reply you have no answer to. Read after the round is
   * logged, so this round counts toward it. Null when there is nowhere to grow.
   */
  const offerFor = (done: Run): GrowOffer | null => {
    if (done.leftPrep || done.bookRun) return null;
    const now = useStore.getState();
    const rep = repertoireList(now).find((r) => r.color === done.color);
    if (!rep) return null;
    const entered = done.enteredIn ? nodeById(tree, done.enteredIn) : null;
    const opening = offerOpening(tree, nodeById(tree, done.openingId), entered, done.played);
    const opts = {
      minShare: now.settings.growth.minShare,
      maxPly: now.settings.growth.maxPly,
      starred: now.settings.favoriteOpenings,
    };
    const stub = isStubFinish(done);
    if (stub || readyToGrow(rep, tree, opening, now.score.rounds)) {
      const launch = growLaunch(rep, index, tree, opening, done.played, opts);
      if (launch) {
        const last = yourLastMove(done.played, done.color);
        const more =
          launch.widened?.why === 'rarer' ? ' Grow it with rarer replies.' : launch.widened ? ' Grow it deeper.' : '';
        const text = stub
          ? `${opening.name} has nothing past ${last ?? 'the first move'} yet.`
          : `You finish every ${opening.name} line cleanly.${more}`;
        return { kind: 'opening', text, launch };
      }
    }
    // Growing this line means growing from where it ended, not the opening's
    // most urgent gap somewhere else. Nothing else holds it back: it is there
    // to be found, not to suggest, and Growth opened from it points back after
    // one batch anyway. Past Growth's depth it adds a move at a time.
    const hole = holeAtEnd(rep, index, done.played, Infinity);
    if (!hole) return null;
    const launch = growLaunch(rep, index, tree, opening, done.played, { ...opts, maxPly: Infinity });
    return launch ? { kind: 'line', text: 'Grow this line', launch } : null;
  };

  const referee = useReferee({
    run,
    active: live && extended,
    onVerdict: (verdict) => {
      if (!run || !source || settled.current) return;
      if (extended) {
        if (!verdict.ok) {
          die(run, { cause: 'blunder', played: verdict.san, expected: [], lost: verdict.lost });
          return;
        }
        buzz(10);
        setGame({ source, run: playPast(run, verdict.san) });
        return;
      }
      // A move your prep does not have. Where it had one, this is a miss —
      // logged now, whatever you decide, because the drill lives in the
      // schedule rather than in the round ending.
      const expected = source.prepAt(run.fen);
      if (expected.length) {
        slipped.current = true;
        debit(run);
        if (run.repertoireId) missed(run.repertoireId, run.fen, verdict.san, expected[0]);
      }
      if (!verdict.ok) {
        die(run, { cause: 'blunder', played: verdict.san, expected, lost: verdict.lost });
        return;
      }
      // Sound, but not yours: the round stops here, and playing on is the
      // move played with the engine judging from there.
      buzz(14);
      const left = leavePrep(run, verdict.san);
      const onward: Onward = positionStatus(left.fen).gameOver ? null : { kind: 'run', run: left };
      if (expected.length) {
        // A miss: the reveal rewinds to the position you were asked about,
        // your move in red beside the prepared one in green.
        conclude({
          run: { ...run, leftPrep: true },
          death: { cause: 'offprep', played: verdict.san, expected, lost: verdict.lost },
          cause: 'offprep',
          onward,
        });
        return;
      }
      // Nothing was prepared here, so the move is not a miss and is not shown
      // as one: it stands on the board as played.
      conclude({
        run: left,
        death: null,
        cause: 'offprep',
        onward,
        headline: run.bookRun ? 'Out of the book, but sound' : 'Off your prep, but sound',
      });
    },
  });

  useOpponent({
    fen: run?.fen ?? null,
    enabled: engineTurn,
    onMove: (san) => {
      if (!run || !source || settled.current) return;
      setGame({ source, run: playReply(run, san) });
    },
  });

  const clock = useMoveClock({
    seconds: clockSeconds(prefs.clock),
    turnKey: `${run?.id ?? ''}:${run?.played.length ?? 0}`,
    // Past the hand-over nothing is earned, and the clock is the speed bonus.
    active: live && myTurn && !thinking && !referee.pending && !extended,
  });

  // The opponent answers on its own, after a beat. Inside your prep, with no
  // line left to follow — you stepped onto another of your lines, or there
  // never was one — a new line is drawn from here first, by the same steer,
  // so the opponent keeps walking you toward your lines, your weak spots or
  // your holes. Past the hand-over the drill is over and it simply plays the
  // book, by popularity, while the book lasts.
  useEffect(() => {
    if (!source || !run || !live || myTurn || run.over) return;
    if (movesHere(source, run).length === 0) return;
    setThinking(true);
    const timer = setTimeout(() => {
      setThinking(false);
      setGame((g) => {
        if (!g) return g;
        const offLine = g.run.target.length <= g.run.played.length;
        const steered = offLine && redraw.current ? redraw.current(g.run) : g.run;
        return { ...g, run: opponentReply(g.source, steered, picker.current) };
      });
    }, 420);
    return () => clearTimeout(timer);
  }, [source, run, myTurn, live]);

  /**
   * The referee running out is a checkpoint. With moves left to add the run
   * pauses at the edge of the prep instead and offers the book; once they
   * are spent, or with none, the end of the prep — or of the book, on a run
   * through it, whoever is to move — is where the run is complete.
   */
  useEffect(() => {
    if (!source || !run || !live || settled.current) return;
    const complete = isComplete(source, run);
    const edge = !complete && atEdge(source, run);
    if (!complete && !edge) return;
    if (edge && run.newMoves > 0) {
      buzz(14);
      setPhase('gap');
      return;
    }
    arrive(run);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [source, run, live]);

  /** Past the hand-over, play ends with the game, not with the prep. */
  useEffect(() => {
    if (!extended || !run || !live || settled.current) return;
    if (!positionStatus(run.fen).gameOver) return;
    conclude({ run, death: null, cause: null, onward: null });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [extended, run, live]);

  /** A hint belongs to one position only. */
  useEffect(() => setHintSquare(null), [run?.fen]);

  const begin = (started: Game | null) => {
    if (!started) return;
    settled.current = false;
    logged.current = false;
    slipped.current = false;
    uncounted.current = false;
    ratings.current = new Map();
    setGrowOffer(null);
    setBookEnded(false);
    setMoved([]);
    setKept(null);
    setDeath(null);
    setOnward(null);
    setHeadline(null);
    referee.reset();
    setGame(started);
    setPhase('playing');
  };

  const start = (options: OpeningRunOptions) => begin(open(options));

  /** Another run on the same terms. */
  const again = () => start(prefs);

  /** Next run: Autopilot's next round when it owns the next, otherwise another on these terms. */
  const next = () => (onNext ? onNext() : again());

  /**
   * Carry on from the reveal. The run goes on past the prep with the engine
   * judging, still the same round; after a blunder it is a game of its own.
   * A line kept before carrying on is offered again at the next ending,
   * for whatever it has grown by since.
   */
  const keepGoing = () => {
    if (!onward || !source) return;
    if (onward.kind === 'game') {
      setPlayOnFrom(onward.fen);
      setPhase('playon');
      return;
    }
    buzz(10);
    settled.current = false;
    referee.reset();
    setGrowOffer(null);
    setBookEnded(false);
    setKept(null);
    setDeath(null);
    setOnward(null);
    setHeadline(null);
    setGame({ source, run: onward.run });
    setPhase('playing');
  };

  if (phase === 'setup' || !run || !source) {
    return <Setup onStart={start} onExit={onExit} />;
  }

  if (phase === 'playon' && playOnFrom) {
    return (
      <PlayOn
        from={playOnFrom}
        color={run.color}
        label={run.sourceLabel}
        onBack={() => {
          setPlayOnFrom(null);
          setPhase(death ? 'dead' : 'survived');
        }}
      />
    );
  }

  if (phase === 'growing' && growOffer) {
    const { launch } = growOffer;
    return (
      <GrowthScreen
        onExit={onExit}
        launch={{
          row: launch.row,
          hole: launch.hole,
          region: launch.opening.id,
          backLabel: planned ? 'Back to Autopilot' : 'Back to Run',
          onBack: next,
          pointBack: growOffer.kind === 'line' ? 'batch' : 'cap',
          widened: launch.widened,
        }}
      />
    );
  }

  if (phase === 'dead' || phase === 'survived') {
    return (
      <Reveal
        source={source}
        run={run}
        death={phase === 'dead' ? death : null}
        moved={moved}
        auto={!!planned}
        headline={headline}
        kept={kept}
        onKeep={keep}
        grow={growOffer?.kind === 'opening' ? { text: growOffer.text, onGrow: () => setPhase('growing') } : null}
        growLine={growOffer?.kind === 'line' ? () => setPhase('growing') : null}
        bookEnded={bookEnded}
        onExit={onExit}
        onKeepPlaying={onward ? keepGoing : null}
        onNext={next}
        onChangeOptions={() => setPhase('setup')}
      />
    );
  }

  const onMove = (move: LegalMove) => {
    if (phase === 'gap') {
      chooseAtGap(move.san);
      return;
    }
    if (!live || !myTurn || referee.pending) return;
    if (extended) {
      referee.submit(move);
      return;
    }
    const kind = classify(source, run, move.san);
    if (kind === 'prep') {
      const result = play(source, run, move.san);
      if (!result.ok) return;
      buzz(10);
      // A position your prep has an answer to is a card on the schedule, and
      // finding the answer is a review of it.
      if (run.repertoireId && source.prepAt(run.fen).length) {
        answered(run.repertoireId, run.fen, move.san, gradeForTime(clock.elapsedNow()));
      }
      credit(result.run);
      setGame({ source, run: result.run });
      return;
    }
    // Theory your prep does not have, or a move nobody plays: the engine
    // decides which kind of mistake it is. A blunder ends the run; a sound
    // move is a checkpoint, and the choice to carry on is yours.
    referee.submit(move);
  };

  /** Where a move added at the edge goes: the tree for the side being played. */
  const repertoireForAdding = (): string => run.repertoireId ?? ensureRepertoire(run.color);

  /** The book at the edge of the prep, and the moves drawn on the board for it. */
  const inRegion = phase === 'gap' ? movesHere(source, run) : [];
  const gap = edgeOptions(index, run.fen).filter((option) => inRegion.includes(option.san));
  const drawn = movesToDraw(index, run.fen).filter((move) => inRegion.includes(move.san));

  /**
   * Take a move from the book at the edge of the prep. It goes into the
   * repertoire and the run carries on; it rates nothing, since you did not
   * find it.
   */
  const chooseAtGap = (san: string) => {
    if (phase !== 'gap' || !gap.some((option) => option.san === san)) return;
    const line = [...run.played, san];
    addToRep(repertoireForAdding(), line, 'reference');
    toast(`${san} added`);
    buzz(10);
    setGame({ source, run: chooseAtEdge(run, san) });
    setPhase('playing');
  };

  const onHint = () => {
    if (!live || !myTurn || !run.hints) return;
    const taken = takeHint(source, run);
    if (!taken) return;
    buzz(8);
    setHintSquare(taken.from);
    setGame({ source, run: taken.run });
  };

  return (
    <>
      <AppBar
        title="Run"
        subtitle={selectionText(run.color, run.enteredIn ?? run.openingId)}
        onClose={onExit}
        actions={
          <div className="row gap-6">
            {extended && <span className="chip accent wide">{referee.liveScore ?? '…'}</span>}
            {live && myTurn && !extended && <ClockHud clock={clock} />}
            <span className={`chip num wide${run.leftPrep ? ' accent' : ''}`}>{run.survived}</span>
          </div>
        }
      />

      <div className="screen no-nav">
        <Board
          fen={run.fen}
          orientation={run.color}
          interactive={(live && myTurn && !thinking && !referee.pending) || phase === 'gap'}
          movableFor={run.color}
          allowed={phase === 'gap' ? drawn.map((move) => move.san) : undefined}
          arrows={drawn.map((move) => ({ from: move.from, to: move.to }))}
          onMove={onMove}
          lastMove={lastMoveOf(run.played)}
          highlights={hintSquare ? [{ square: hintSquare, kind: 'hint' }] : []}
          showCoordinates={settings.showCoordinates}
          theme={settings.boardTheme}
          captured
        />

        {run.opened > 0 && (
          <div className="center small muted mt-8">
            From {sansToMoveText(run.played.slice(0, run.opened))}
          </div>
        )}

        <div className="spacer" />

        {phase === 'gap' && (
          <>
            <div className="prompt">
              <div className="who">
                <span className={`side ${run.color}`} />
                Your prep ends here
              </div>
              <div className="ctx">
                {run.newMoves === 1 ? 'One move to add' : `${run.newMoves} moves to add`}
              </div>
            </div>
            <Section title="Choose a move" />
            {gap.length === 0 ? (
              <div className="card small muted">The database has nothing here.</div>
            ) : (
              <div className="list">
                {gap.map((option) => (
                  <button className="list-row" key={option.san} onClick={() => chooseAtGap(option.san)}>
                    <span className="tree-san">{option.san}</span>
                    <span className="grow">
                      <div className="meta">
                        {option.share}% of replies · {formatGameCount(option.games)} games
                      </div>
                    </span>
                    <Icons.plus size={18} />
                  </button>
                ))}
              </div>
            )}
          </>
        )}

        {live && (
          <>
            <div className="prompt">
              <div className="who">
                {thinking || referee.pending || engineTurn ? (
                  <span className="spinner" />
                ) : (
                  <span className={`side ${run.color}`} />
                )}
                {referee.pending
                  ? 'Judging'
                  : thinking || engineTurn
                    ? 'Reply'
                    : 'Your move'}
              </div>
              {extended && <div className="ctx">Past your prep · the engine judges</div>}
            </div>
            {run.hints > 0 && !extended && (
              <button
                className="btn soft block mt-8"
                disabled={!myTurn || thinking || hintSquare !== null}
                onClick={onHint}
              >
                <Icons.bolt size={18} />
                {hintSquare ? 'Hint spent' : `Hint (${run.hints} left)`}
              </button>
            )}
          </>
        )}
      </div>
    </>
  );
}
