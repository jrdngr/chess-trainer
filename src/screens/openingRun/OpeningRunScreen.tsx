import { useEffect, useRef, useState } from 'react';
import { Board } from '../../components/Board';
import { AppBar, haptic, Icons, Section, toast } from '../../components/ui';
import { lastMoveOf, positionStatus, sansToMoveText, type LegalMove, type Square } from '../../chess/core';
import {
  atEdge,
  beginRun,
  carryOn,
  chooseAtEdge,
  classify,
  edgeOptions,
  extend,
  isComplete,
  isExtended,
  isUsersTurn,
  leavePrep,
  lineToKeep,
  longEnough,
  movesHere,
  opponentReply,
  outcomeOf,
  play,
  playExtended,
  playExtendedReply,
  takeHint,
  weaknessFromCards,
  type Begun,
  type LineSource,
  type OpeningRunOptions,
  type OpeningRunPrefs,
  type Run,
} from '../../model/openingRun';
import { deepestName, formatGameCount, specificNameForColor } from '../../model/reference';
import { nodeById, openingTree } from '../../model/openingTree';
import { hasLine } from '../../model/repertoire';
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
import { ClockHud, useMoveClock } from '../../components/Clock';
import { clockSeconds } from '../../model/openingRun';
import { comboBonus, POINTS, seenIn } from '../../model/scoring';
import { deepestNodeWithin } from '../../model/openingTree';
import type { RoundPlan, RoundSummary } from '../../model/autopilot';

type Phase = 'setup' | 'playing' | 'offprep' | 'gap' | 'dead' | 'survived' | 'playon';

interface Game {
  source: LineSource;
  run: Run;
}

/** A move that is theory here, but not in your prep. */
interface OffPrep {
  san: string;
  /** What your prep had instead. */
  expected: string[];
  /** What the database calls the line your move leads into. */
  opening: string | null;
}

/**
 * OpeningRun: one secret line, played until the first mistake.
 *
 * This screen owns the run and its rules — the opponent's replies, the clock,
 * hints, stepping out of prep, the book offered at the edge of the prep, and
 * the engine as referee once it has been handed over. Nothing on screen names
 * the line while it is live; the reveal is the reward for dying, and lives in
 * its own screen.
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
   * automatic run is always on the clock, with no hints and no extended play.
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
    ? { ...settings.openingRun, ...planned.options, clock: 'move10', hints: 0, extended: false }
    : settings.openingRun;
  const endRun = useStore((s) => s.endOpeningRun);
  const earn = useStore((s) => s.earn);
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
   * How to steer the current run again from wherever it has got to. Set
   * when a run is opened, read when the opponent is about to reply with no
   * line left to follow.
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
  const [offPrep, setOffPrep] = useState<OffPrep | null>(null);
  /** Where a game against the engine was started from, after the run. */
  const [playOnFrom, setPlayOnFrom] = useState<string | null>(null);
  const picker = useRef(mulberry32(Math.floor(Math.random() * 2 ** 31)));
  /** True once the run has been logged, so nothing ends it twice. */
  const settled = useRef(false);

  const source = game?.source ?? null;
  const run = game?.run ?? null;
  const live = phase === 'playing';
  const myTurn = run ? isUsersTurn(run) : false;
  const extended = !!run && isExtended(run);

  const buzz = (pattern: number | number[]) => {
    if (settings.hapticFeedback) haptic(pattern);
  };

  /** Points banked this run, for the reveal. */
  const [earned, setEarned] = useState(0);

  /** What the run wrote into the repertoire, for the reveal. */
  const [saved, setSaved] = useState<{ name: string; added: number } | null>(null);

  const finish = (ended: Run, completed: boolean) => {
    settled.current = true;
    endRun(outcomeOf(ended, completed));
    setSaved(keepLine(ended));
    let bonus = 0;
    if (completed && !isExtended(ended)) {
      bonus += POINTS.run.finish + (ended.leftPrep ? 0 : POINTS.run.green);
      earn({ mode: 'run', points: bonus, line: ended.played, color: ended.color, answered: false, correct: false });
    }
    setEarned((total) => total + bonus);
    // A run carried on into extended play amends its record, not its round.
    if (!roundLogged.current) {
      roundLogged.current = true;
      const region = nodeById(tree, ended.openingId);
      const summary: RoundSummary = {
        openingId: deepestNodeWithin(tree, region, ended.played).id,
        color: ended.color,
        score: earned + bonus,
        answered: ended.survived + (completed ? 0 : 1),
        correct: ended.survived,
        perfect: completed && !ended.leftPrep,
      };
      endRound({ mode: 'run', ...summary, line: ended.drawn });
      onRoundOver?.(summary);
    }
  };
  const roundLogged = useRef(false);

  /** A correct move of yours: the base, the speed bonus, and the combo. */
  const credit = (after: Run) => {
    const points =
      POINTS.run.move + clock.bonus + comboBonus(after.survived);
    earn({ mode: 'run', points, line: after.played, color: after.color, answered: true, correct: true });
    setEarned((total) => total + points);
  };

  /** A miss: answered, worth nothing, and counted against the line. */
  const debit = (ended: Run, san: string) => {
    earn({ mode: 'run', points: 0, line: [...ended.played, san], color: ended.color, answered: true, correct: false });
  };

  /**
   * Which opening the saved line belongs to.
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
   * Write what the run survived into the repertoire. Always: a line you have
   * played through is a line you play, which is the whole idea of the app.
   *
   * It joins the one tree for the side you played, whatever the opening. The
   * opening is only what the moves are called once they are in there. Returns
   * what was written, or null when the run survived nothing worth keeping.
   */
  const keepLine = (ended: Run): { name: string; added: number } | null => {
    const line = lineToKeep(ended);
    if (!line.length) return null;
    const existing = reps.find((rep) => rep.color === ended.color) ?? null;
    if (existing && hasLine(existing, line)) return { name: openingOf(ended, line), added: 0 };
    const repId = ensureRepertoire(ended.color);
    const { added } = addToRep(repId, line, 'reference');
    return { name: openingOf(ended, line), added };
  };

  /** End the run here. `ended` may carry state the run picked up on the way out. */
  const die = (ended: Run, how: Death) => {
    if (!source) return;
    buzz([22, 60, 22]);
    setDeath(how);
    setGame({ source, run: { ...ended, over: true } });
    setPhase('dead');
    finish(ended, false);
  };

  const referee = useReferee({
    run,
    active: live && extended,
    onVerdict: (verdict) => {
      if (!run || !source || settled.current) return;
      if (!verdict.ok) {
        debit(run, verdict.san);
        die(run, { cause: 'blunder', played: verdict.san, expected: [], lost: verdict.lost });
        return;
      }
      buzz(10);
      const next = playExtended(run, verdict.san, verdict.reply);
      credit({ ...next, played: [...run.played, verdict.san] });
      setGame({ source, run: next });
    },
    onOpponentMove: (san) => {
      if (!run || !source || settled.current) return;
      setGame({ source, run: playExtendedReply(run, san) });
    },
  });

  const clock = useMoveClock({
    seconds: clockSeconds(prefs.clock),
    turnKey: `${run?.id ?? ''}:${run?.played.length ?? 0}`,
    active: live && myTurn && !thinking && !referee.pending && !referee.replying,
  });

  // The opponent answers on its own, after a beat. With no line left to
  // follow — you stepped off it, or there never was one — a new line is
  // drawn from here first, by the same steer, so the round follows you
  // rather than wandering: the opponent walks you toward your lines, your
  // weak spots or your holes from wherever you have taken it.
  useEffect(() => {
    if (!source || !run || !live || myTurn || run.over || extended) return;
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
  }, [source, run, myTurn, live, extended]);

  /**
   * The prep running out ends the run, once the run is long enough. With
   * moves left to add it pauses at the edge instead and offers the book;
   * while it is still short it carries on into the book, judged by the book;
   * with extended mode on the engine takes over the judging and the run
   * carries on. The book itself running out — no move left at all — ends
   * the run whoever is to move.
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
    if (edge && !longEnough(run)) {
      setGame({ source, run: carryOn(run) });
      return;
    }
    if (prefs.extended) {
      setGame({ source, run: extend(run) });
      return;
    }
    setPhase('survived');
    finish(run, true);
  }, [source, run, live, prefs.extended]);

  /** Extended play ends with the game, not with the prep. */
  useEffect(() => {
    if (!extended || !run || !live || settled.current) return;
    if (!positionStatus(run.fen).gameOver) return;
    setPhase('survived');
    finish(run, true);
  }, [extended, run, live]);

  /** A hint belongs to one position only. */
  useEffect(() => setHintSquare(null), [run?.fen]);

  const begin = (started: Game | null) => {
    if (!started) return;
    settled.current = false;
    roundLogged.current = false;
    setEarned(0);
    setSaved(null);
    setDeath(null);
    setOffPrep(null);
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
        earned={earned}
        auto={!!planned}
        saved={saved}
        onExit={onExit}
        onNewRun={again}
        onChangeOptions={() => setPhase('setup')}
        onPlayOn={(fen) => {
          setPlayOnFrom(fen);
          setPhase('playon');
        }}
        onContinueExtended={() => {
          // The run itself carries on: the score keeps counting and a blunder
          // still ends it. Logging it again amends the completed line's entry.
          settled.current = false;
          setDeath(null);
          referee.reset();
          setGame({ source, run: extend(run) });
          setPhase('playing');
        }}
      />
    );
  }

  const onMove = (move: LegalMove) => {
    if (phase === 'gap') {
      chooseAtGap(move.san);
      return;
    }
    if (!live || !myTurn) return;
    if (extended) {
      referee.submit(move);
      return;
    }
    // A real theory move that your prep simply does not have is not the same
    // mistake as a move nobody plays. Pause and let it be a decision — on a
    // run you set up yourself. Under Autopilot it is simply your move: the
    // round follows you, the book judges from here, and the reveal says the
    // run left your prep.
    if (classify(source, run, move.san) === 'theory') {
      if (planned) {
        buzz(10);
        const next = leavePrep(run, move.san);
        credit(next);
        setGame({ source, run: next });
        return;
      }
      buzz(14);
      const named = deepestName(index, [...run.played, move.san]);
      setOffPrep({
        san: move.san,
        expected: source.prepAt(run.fen),
        opening: named && named.ply >= 3 ? named.name : null,
      });
      setPhase('offprep');
      return;
    }
    const result = play(source, run, move.san);
    if (result.ok) {
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
    debit(run, move.san);
    die(run, { cause: 'move', played: result.played, expected: result.expected });
    // Only a position your prep has an answer to is a card on the schedule.
    if (run.repertoireId && source.prepAt(run.fen).length) {
      missed(run.repertoireId, run.fen, result.played, source.prepAt(run.fen)[0] ?? '');
    }
  };

  /** Where an out-of-prep move goes: the tree for the side being played. */
  const repertoireForAdding = (): string => run.repertoireId ?? ensureRepertoire(run.color);

  /** The book at the edge of the prep, and the moves drawn on the board for it. */
  const inRegion = phase === 'gap' ? movesHere(source, run) : [];
  const gap = edgeOptions(index, run.fen).filter((option) => inRegion.includes(option.san));
  const drawn = movesToDraw(index, run.fen).filter((move) => inRegion.includes(move.san));

  /**
   * Take a move from the book at the edge of the prep. It goes into the
   * repertoire and the run carries on; it earns nothing, since you did not
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

  /** Keep the move, and let the book judge the rest of the run. */
  const acceptOffPrep = (addToRepertoire: boolean) => {
    if (!offPrep) return;
    if (addToRepertoire) {
      addToRep(repertoireForAdding(), [...run.played, offPrep.san], 'manual');
      toast(`${offPrep.san} added`);
    }
    buzz(10);
    setOffPrep(null);
    const next = leavePrep(run, offPrep.san);
    credit(next);
    setGame({ source, run: next });
    setPhase('playing');
  };

  /** Stop here instead. A softer ending than a move nobody plays. */
  const declineOffPrep = () => {
    if (!offPrep) return;
    setOffPrep(null);
    debit(run, offPrep.san);
    die({ ...run, leftPrep: true }, { cause: 'offprep', played: offPrep.san, expected: offPrep.expected });
    if (run.repertoireId) {
      missed(run.repertoireId, run.fen, offPrep.san, offPrep.expected[0] ?? '');
    }
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
            {live && myTurn && <ClockHud clock={clock} />}
            <span className={`chip num wide${run.leftPrep ? ' accent' : ''}`}>{run.survived}</span>
          </div>
        }
      />

      <div className="screen no-nav">
        <Board
          fen={run.fen}
          orientation={run.color}
          interactive={(live && myTurn && !thinking) || phase === 'gap'}
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

        {phase === 'offprep' && offPrep && (
          <>
            <div className="verdict accent">
              <span className="ico">
                <Icons.book size={16} />
              </span>
              Out of prep
            </div>
            {offPrep.opening && <div className="center small muted">{offPrep.opening}</div>}
            <div className="compare mt-12">
              <div>
                <div className="k">Your prep</div>
                <div className="v">{offPrep.expected[0] ?? '—'}</div>
              </div>
              <div className="accent">
                <div className="k">You played</div>
                <div className="v">{offPrep.san}</div>
              </div>
            </div>
            <div className="spacer" />
            <div className="actions">
              <button className="btn accent block xl" onClick={() => acceptOffPrep(true)}>
                <Icons.plus size={18} />
                Add {offPrep.san} and carry on
              </button>
              <button className="btn block" onClick={() => acceptOffPrep(false)}>
                Carry on without adding it
              </button>
              <button className="btn plain block" onClick={declineOffPrep}>
                End the run here
              </button>
            </div>
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
                {thinking || referee.pending || referee.replying ? (
                  <span className="spinner" />
                ) : (
                  <span className={`side ${run.color}`} />
                )}
                {referee.pending
                  ? 'Judging'
                  : thinking || referee.replying
                    ? 'Reply'
                    : 'Your move'}
              </div>
              {run.pastPrep !== null && !extended && <div className="ctx">Past your prep · the book judges</div>}
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
