import { useEffect, useRef, useState } from 'react';
import { Board } from '../../components/Board';
import { AppBar, haptic, Icons, toast } from '../../components/ui';
import { lastMoveOf, positionStatus, type LegalMove, type Square } from '../../chess/core';
import {
  beginRun,
  bookHas,
  bookSource,
  canKeepLine,
  extend,
  isComplete,
  isExtended,
  isUsersTurn,
  leavePrep,
  lineToKeep,
  movesHere,
  opponentReply,
  outcomeOf,
  play,
  playExtended,
  takeHint,
  weaknessFromCards,
  type LineSource,
  type OpeningRunOptions,
  type Run,
} from '../../model/openingRun';
import { deepestName, deepestNameForColor, openingById } from '../../model/reference';
import { displayName, hasLine } from '../../model/repertoire';
import { referenceIndex } from '../../model/referenceIndex';
import { mulberry32 } from '../../model/session';
import { repertoireList, useStore } from '../../store/useStore';
import { PlayOn } from './PlayOn';
import { Reveal, type Death } from './Reveal';
import { Setup } from './Setup';
import { useReferee } from './useReferee';
import { formatClock, useRunClock } from './useRunClock';

type Phase = 'setup' | 'playing' | 'offprep' | 'dead' | 'survived' | 'playon';

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
  /** Whether there is a repertoire this could be added to. */
  addable: boolean;
}

/**
 * OpeningRun: one secret line, played until the first mistake.
 *
 * This screen owns the run and its rules — the opponent's replies, the clock,
 * hints, stepping out of prep, and the engine as referee once the prep runs
 * out. Nothing on screen names the line while it is live; the reveal is the
 * reward for dying, and lives in its own screen.
 */
export function OpeningRunScreen({ onExit }: { onExit: () => void }) {
  const state = useStore();
  const reps = repertoireList(state);
  const { settings, cards } = state;
  const prefs = settings.openingRun;
  const endRun = useStore((s) => s.endOpeningRun);
  const missed = useStore((s) => s.missedInOpeningRun);
  const addToRep = useStore((s) => s.addLine);
  const addRepertoire = useStore((s) => s.addRepertoire);
  const index = referenceIndex();

  const [phase, setPhase] = useState<Phase>('setup');
  const [game, setGame] = useState<Game | null>(null);
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

  const finish = (ended: Run, completed: boolean) => {
    settled.current = true;
    endRun(outcomeOf(ended, completed));
  };

  /**
   * What to call a repertoire this run is about to create.
   *
   * An opening run has the answer already: you chose the opening, so that is
   * its name, whatever the few moves you survived of it happen to be called. A
   * book run has no such choice, so the line is named from the side you played
   * — a Black repertoire called "Queen's Pawn Opening" describes what your
   * opponent did.
   *
   * The side is stored in the name and stripped for display, which is the
   * convention the rest of the app already reads.
   */
  const newName = (ended: Run, line: string[]): string => {
    const chosen = ended.openingId ? openingById(index, ended.openingId) : null;
    const named = chosen?.name ?? deepestNameForColor(index, line, ended.color)?.name;
    return `${ended.color === 'w' ? 'White' : 'Black'} — ${named ?? ended.sourceLabel}`;
  };

  /** Where a run's line would go, and whether there is anything to put there. */
  const keepTarget = (ended: Run) => {
    if (!canKeepLine(ended.source)) return null;
    const line = lineToKeep(ended);
    if (!line.length) return null;
    return { line, existing: reps.find((rep) => rep.color === ended.color) ?? null };
  };

  /**
   * Has this run's line already been written? Checked rather than discovered on
   * tap, so replaying a line you have kept shows Saved from the start.
   */
  const alreadyKept = (ended: Run): boolean => {
    const target = keepTarget(ended);
    return !!target?.existing && hasLine(target.existing, target.line);
  };

  /**
   * Write what the run survived into a repertoire, when asked to.
   *
   * Offered at the end rather than done automatically: a book run can hand you
   * any opening in the database, and keeping all of them builds a wide, shallow
   * repertoire rather than a coherent one.
   */
  const keepLine = (ended: Run): { name: string; added: number } | null => {
    const target = keepTarget(ended);
    if (!target) return null;
    const { line, existing } = target;
    const name = existing?.name ?? newName(ended, line);
    const repId = existing?.id ?? addRepertoire(name, ended.color);
    const { added } = addToRep(repId, line, 'reference');
    return { name: displayName(name), added };
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
        die(run, { cause: 'blunder', played: verdict.san, expected: [], lost: verdict.lost });
        return;
      }
      buzz(10);
      setGame({ source, run: playExtended(run, verdict.san, verdict.reply) });
    },
  });

  const clock = useRunClock({
    mode: prefs.clock,
    runId: run?.id ?? null,
    active: live && myTurn && !thinking && !referee.pending,
    onExpire: () => {
      if (!run || !source || settled.current || !live) return;
      die(run, { cause: 'time', expected: movesHere(source, run) });
    },
  });

  // The opponent answers on its own, after a beat.
  useEffect(() => {
    if (!source || !run || !live || myTurn || run.over || extended) return;
    if (movesHere(source, run).length === 0) return;
    setThinking(true);
    const timer = setTimeout(() => {
      setThinking(false);
      setGame((g) => (g ? { ...g, run: opponentReply(g.source, g.run, picker.current) } : g));
    }, 420);
    return () => clearTimeout(timer);
  }, [source, run, myTurn, live, extended]);

  /**
   * The prep running out ends the run — unless extended mode is on, in which
   * case the engine takes over the judging and the run carries on. Lines end
   * on your own move, so this is checked whoever is to move.
   */
  useEffect(() => {
    if (!source || !run || !live || settled.current || !isComplete(source, run)) return;
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

  const start = (options: OpeningRunOptions) => {
    const started = beginRun({ ...options, reps, index, weakness: weaknessFromCards(cards) });
    if (!started) return;
    settled.current = false;
    setDeath(null);
    setOffPrep(null);
    referee.reset();
    setGame(started);
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

  if (phase === 'dead' || phase === 'survived') {
    return (
      <Reveal
        source={source}
        run={run}
        death={phase === 'dead' ? death : null}
        canSaveLine={!!keepTarget(run)}
        alreadySaved={alreadyKept(run)}
        onSaveLine={() => keepLine(run)}
        onExit={onExit}
        onNewRun={() => start(prefs)}
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
    if (!live || !myTurn) return;
    if (extended) {
      referee.submit(move);
      return;
    }
    const result = play(source, run, move.san);
    if (result.ok) {
      buzz(10);
      setGame({ source, run: result.run });
      return;
    }
    // A real theory move that your prep simply does not have is not the same
    // mistake as a move nobody plays. Pause and let it be a decision.
    if (!run.leftPrep && run.source !== 'book' && bookHas(index, run.fen, move.san)) {
      buzz(14);
      const named = deepestName(index, [...run.played, move.san]);
      setOffPrep({
        san: move.san,
        expected: result.expected,
        opening: named && named.ply >= 3 ? named.name : null,
        addable: !!run.repertoireId,
      });
      setPhase('offprep');
      return;
    }
    die(run, { cause: 'move', played: result.played, expected: result.expected });
    // A reversed run is judged on the side you prepared against, so its
    // positions are not decision points and must not touch the schedule.
    if (run.repertoireId && !run.reverse) {
      missed(run.repertoireId, run.fen, result.played, result.expected[0] ?? '');
    }
  };

  /** Keep the move, and let the book judge the rest of the run. */
  const acceptOffPrep = (addToRepertoire: boolean) => {
    if (!offPrep) return;
    if (addToRepertoire && run.repertoireId) {
      addToRep(run.repertoireId, [...run.played, offPrep.san], 'manual');
      toast(`${offPrep.san} added`);
    }
    buzz(10);
    setOffPrep(null);
    setGame({ source: bookSource(index, run.color), run: leavePrep(run, offPrep.san) });
    setPhase('playing');
  };

  /** Stop here instead. A softer ending than a move nobody plays. */
  const declineOffPrep = () => {
    if (!offPrep) return;
    setOffPrep(null);
    die({ ...run, leftPrep: true }, { cause: 'offprep', played: offPrep.san, expected: offPrep.expected });
    if (run.repertoireId && !run.reverse) {
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

  const urgent = clock !== null && clock <= 5;

  return (
    <>
      <AppBar
        title="Opening Run"
        onClose={onExit}
        actions={
          <div className="row gap-6">
            {extended && <span className="chip accent wide">{referee.liveScore ?? '…'}</span>}
            {clock !== null && (
              <span className={`chip num wide${urgent ? ' bad' : ''}`}>{formatClock(clock)}</span>
            )}
            <span className={`chip num wide${run.leftPrep ? ' accent' : ''}`}>{run.survived}</span>
          </div>
        }
      />

      <div className="screen no-nav">
        <Board
          fen={run.fen}
          orientation={run.color}
          interactive={live && myTurn && !thinking}
          movableFor={run.color}
          onMove={onMove}
          lastMove={lastMoveOf(run.played)}
          highlights={hintSquare ? [{ square: hintSquare, kind: 'hint' }] : []}
          showCoordinates={settings.showCoordinates}
          theme={settings.boardTheme}
        />

        <div className="spacer" />

        {phase === 'offprep' && offPrep && (
          <>
            <div className="verdict accent">
              <span className="ico">
                <Icons.book size={16} />
              </span>
              Out of prep
            </div>
            <div className="center small muted">
              <b>{offPrep.san}</b> is a real move
              {offPrep.opening ? ` — the ${offPrep.opening}` : ''} — but it is not in your
              repertoire here.
            </div>
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
              {offPrep.addable && (
                <button className="btn accent block xl" onClick={() => acceptOffPrep(true)}>
                  <Icons.plus size={18} />
                  Add {offPrep.san} and carry on
                </button>
              )}
              <button
                className={`btn block${offPrep.addable ? '' : ' accent xl'}`}
                onClick={() => acceptOffPrep(false)}
              >
                Carry on without adding it
              </button>
              <button className="btn plain block" onClick={declineOffPrep}>
                End the run here
              </button>
            </div>
            <div className="note center">
              Carrying on hands the judging to the book, and the run is graded as an out-of-prep
              one however it ends.
            </div>
          </>
        )}

        {live && (
          <>
            <div className="prompt">
              <div className="who">
                {thinking || referee.pending ? (
                  <span className="spinner" />
                ) : (
                  <span className={`side ${run.color}`} />
                )}
                {referee.pending ? 'Judging' : thinking ? 'Reply' : 'Your move'}
              </div>
              <div className="ctx">
                {hintSquare
                  ? `The move starts on ${hintSquare}`
                  : extended
                    ? 'Past your prep — the engine is calling blunders now'
                    : run.leftPrep
                      ? 'Out of your prep — the book is judging now'
                      : run.reverse
                        ? 'Play the side your repertoire prepares against'
                        : 'One mistake ends the run'}
              </div>
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
