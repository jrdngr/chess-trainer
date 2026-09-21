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
import { deepestName, formatGameCount, specificNameForColor } from '../../model/reference';
import { nodeById, openingTree } from '../../model/openingTree';
import { referenceIndex } from '../../model/referenceIndex';
import { evidenceFor, movesToDraw } from '../../model/growth';
import { gradeForTime } from '../../model/srs';
import { selectionText } from '../../components/Selection';
import { mulberry32 } from '../../model/session';
import { evidenceIn } from '../../store/recommendation';
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

type Phase = 'setup' | 'playing' | 'checkpoint' | 'gap' | 'dead' | 'survived' | 'playon';

interface Game {
  source: LineSource;
  run: Run;
}

/**
 * Where the drill stopped and the choice is yours: keep playing, or start a
 * new round.
 *
 *   left — you played a sound move your prep does not have. The move is on
 *          the board but not yet in the run, so a new round ends on the
 *          position you left, with the move shown as what ended it.
 *   edge — your prep, or the book on a run through it, has run out. The run
 *          is complete either way; keeping playing is the game past it.
 */
interface Checkpoint {
  kind: 'left' | 'edge';
  san?: string;
  /** Centipawns the move cost, by the engine. */
  lost?: number;
  /** What your prep had instead, when it had anything. */
  expected: string[];
  /** What the database calls the line your move leads into. */
  opening: string | null;
}

/**
 * OpeningRun: the opening of a game, drilled against your prep.
 *
 * This screen owns the run and its rules — the opponent's replies, the clock,
 * hints, the book offered at the edge of the prep, the engine as referee for
 * any move your prep does not have, and the checkpoints where the drill ends
 * and the choice to play on is yours. Nothing on screen names the line while
 * the run is live; the reveal is the reward for the round ending, and lives
 * in its own screen. Nothing here writes to the repertoire but the book
 * offered at the edge, which is chosen up front, and the reveal's one tap.
 */
export function OpeningRunScreen({
  auto,
  plan,
  onRoundOver,
  onExit,
}: {
  auto?: boolean;
  /**
   * What Autopilot decided: the side, the opening to walk toward, and the
   * settings the round is played on. It holds for the whole visit, and an
   * automatic run is always on the clock, with no hints and nothing added.
   */
  plan?: RoundPlan;
  onRoundOver?: (summary: RoundSummary) => void;
  onExit: () => void;
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
  const selection = settings.selection;
  /**
   * What your games say, read once a visit: the positions you got wrong with
   * a move prepared weigh on weak-spot steering, and the ones you kept
   * reaching with nothing weigh on which gap a run walks to.
   */
  const [evidence] = useState(() => evidenceIn(state));

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
  const [checkpoint, setCheckpoint] = useState<Checkpoint | null>(null);
  /** Where a game against the engine was started from, after the run. */
  const [playOnFrom, setPlayOnFrom] = useState<string | null>(null);
  const picker = useRef(mulberry32(Math.floor(Math.random() * 2 ** 31)));
  /** True once the run has been logged, so nothing ends it twice. */
  const settled = useRef(false);
  /** True once a move off your prep was logged as a miss, so the round counts it once. */
  const slipped = useRef(false);

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

  const finish = (ended: Run, cause: DeathCause | null) => {
    settled.current = true;
    endRun(outcomeOf(ended, cause));
    const region = nodeById(tree, ended.openingId);
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

  /** End the run here. `ended` may carry state the run picked up on the way out. */
  const die = (ended: Run, how: Death) => {
    if (!source) return;
    buzz([22, 60, 22]);
    setDeath(how);
    setGame({ source, run: { ...ended, over: true } });
    setPhase('dead');
    finish(ended, how.cause);
  };

  /**
   * The referee has run out: the end of your prep, or of the book on a run
   * through it. That completes the run and pays for it, whatever you choose
   * next — and the choice is a checkpoint, never made for you.
   */
  const arrive = (at: Run) => {
    if (!source) return;
    buzz(14);
    setGame({ source, run: finishPrep(at) });
    setCheckpoint({ kind: 'edge', expected: [], opening: null });
    setPhase('checkpoint');
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
      buzz(14);
      const named = deepestName(index, [...run.played, verdict.san]);
      setCheckpoint({
        kind: 'left',
        san: verdict.san,
        lost: verdict.lost,
        expected,
        opening: named && named.ply >= 3 ? named.name : null,
      });
      setPhase('checkpoint');
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
    setPhase('survived');
    finish(run, null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [extended, run, live]);

  /** A hint belongs to one position only. */
  useEffect(() => setHintSquare(null), [run?.fen]);

  const begin = (started: Game | null) => {
    if (!started) return;
    settled.current = false;
    slipped.current = false;
    ratings.current = new Map();
    setMoved([]);
    setKept(null);
    setDeath(null);
    setCheckpoint(null);
    referee.reset();
    setGame(started);
    setPhase('playing');
  };

  const start = (options: OpeningRunOptions) => begin(open(options));

  /** Another run on the same terms. */
  const again = () => start(prefs);

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

  if (phase === 'dead' || phase === 'survived') {
    return (
      <Reveal
        source={source}
        run={run}
        death={phase === 'dead' ? death : null}
        moved={moved}
        auto={!!planned}
        kept={kept}
        onKeep={keep}
        onExit={onExit}
        onNewRun={again}
        onChangeOptions={() => setPhase('setup')}
        onPlayOn={(fen) => {
          setPlayOnFrom(fen);
          setPhase('playon');
        }}
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

  /** Keep playing from the checkpoint: the engine judges from here. */
  const carryOn = () => {
    if (!checkpoint) return;
    buzz(10);
    const next = checkpoint.kind === 'left' && checkpoint.san ? leavePrep(run, checkpoint.san) : keepPlaying(run);
    setCheckpoint(null);
    referee.reset();
    setGame({ source, run: next });
    setPhase('playing');
  };

  /** Stop at the checkpoint instead: the round is over, and the reveal is next. */
  const stopHere = () => {
    if (!checkpoint) return;
    const at = checkpoint;
    setCheckpoint(null);
    if (at.kind === 'left' && at.san) {
      die({ ...run, leftPrep: true }, { cause: 'offprep', played: at.san, expected: at.expected });
      return;
    }
    setPhase('survived');
    finish(run, null);
  };

  const onHint = () => {
    if (!live || !myTurn || !run.hints) return;
    const taken = takeHint(source, run);
    if (!taken) return;
    buzz(8);
    setHintSquare(taken.from);
    setGame({ source, run: taken.run });
  };

  /** At a checkpoint after a move off your prep, the board shows the move made. */
  const previewed = phase === 'checkpoint' && checkpoint?.san ? applySan(run.fen, checkpoint.san) : null;
  const shownFen = previewed?.after ?? run.fen;
  const shownLast = previewed ? { from: previewed.from, to: previewed.to } : lastMoveOf(run.played);

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
          fen={shownFen}
          orientation={run.color}
          interactive={(live && myTurn && !thinking && !referee.pending) || phase === 'gap'}
          movableFor={run.color}
          allowed={phase === 'gap' ? drawn.map((move) => move.san) : undefined}
          arrows={drawn.map((move) => ({ from: move.from, to: move.to }))}
          onMove={onMove}
          lastMove={shownLast}
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

        {phase === 'checkpoint' && checkpoint && (
          <>
            <div className={`verdict ${checkpoint.kind === 'left' ? 'accent' : 'ok'}`}>
              <span className="ico">
                {checkpoint.kind === 'left' ? <Icons.book size={16} /> : <Icons.check size={18} />}
              </span>
              {checkpoint.kind === 'left'
                ? checkpoint.expected.length
                  ? 'Off your prep, but sound'
                  : 'Out of the book, but sound'
                : run.bookRun
                  ? 'End of the book'
                  : 'End of your prep'}
            </div>
            {checkpoint.opening && <div className="center small muted">{checkpoint.opening}</div>}
            {checkpoint.kind === 'left' ? (
              <div className="compare mt-12">
                <div>
                  <div className="k">{checkpoint.expected.length ? 'Your prep' : 'Cost'}</div>
                  <div className="v">
                    {checkpoint.expected.length
                      ? checkpoint.expected[0]
                      : `−${((checkpoint.lost ?? 0) / 100).toFixed(2)}`}
                  </div>
                </div>
                <div className="accent">
                  <div className="k">You played</div>
                  <div className="v">{checkpoint.san}</div>
                </div>
              </div>
            ) : (
              <div className="center small muted mt-8">
                {run.bookRun
                  ? 'The database knows nothing past here.'
                  : 'Nothing prepared past here. The drill is done; the game need not be.'}
              </div>
            )}
            <div className="spacer" />
            <div className="actions">
              <button className="btn accent block xl" onClick={carryOn}>
                <Icons.play size={18} />
                Keep playing
              </button>
              <button className="btn block" onClick={stopHere}>
                {checkpoint.kind === 'left' ? 'Stop here' : 'New round'}
                <Icons.next size={16} />
              </button>
            </div>
            {checkpoint.kind === 'left' && (
              <div className="center small muted mt-8">
                Past here the engine judges, and nothing is rated.
              </div>
            )}
          </>
        )}

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
