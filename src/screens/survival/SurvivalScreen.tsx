import { useEffect, useRef, useState } from 'react';
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
import { deepestNodeWithin, nodeById, openingTree } from '../../model/openingTree';
import { referenceIndex } from '../../model/referenceIndex';
import { evidenceFor } from '../../model/growth';
import { seenIn } from '../../model/scoring';
import { gradeForTime } from '../../model/srs';
import { mulberry32 } from '../../model/session';
import {
  bookReply,
  playTheirs,
  playYours,
  prepHere,
  startSurvival,
  type SurvivalPrefs,
  type SurvivalRecord,
  type SurvivalRun,
  type SurvivalStart,
} from '../../model/survival';
import { evidenceIn } from '../../store/recommendation';
import { repertoireList, useStore } from '../../store/useStore';
import { useOpponent } from '../openingRun/useOpponent';
import { End, type Ending } from './End';
import { Setup } from './Setup';
import { useJudge } from './useJudge';

type Phase = 'setup' | 'playing' | 'over';

/** How long a miss stays over the board before the game goes on. */
const MISS_MS = 2000;

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
 * Its own screen, sharing no state with Run or Autopilot: it rates nothing,
 * adds nothing to the repertoire, and keeps its own record of moves survived.
 */
export function SurvivalScreen({ onExit }: { onExit: () => void }) {
  const state = useStore();
  const { settings, cards } = state;
  const recordMove = useStore((s) => s.recordMove);
  const endRound = useStore((s) => s.endRound);
  const endSurvival = useStore((s) => s.endSurvival);
  const answered = useStore((s) => s.answeredInOpeningRun);
  const missed = useStore((s) => s.missedInOpeningRun);
  const index = referenceIndex();
  const tree = openingTree(index);
  const selection = settings.selection;
  /** What your games say, read once a visit, for the steers. */
  const [evidence] = useState(() => evidenceIn(state));

  const [phase, setPhase] = useState<Phase>('setup');
  const [prefs, setPrefs] = useState<SurvivalPrefs>(settings.survival);
  const [game, setGame] = useState<Game | null>(null);
  const [ending, setEnding] = useState<Ending | null>(null);
  const [before, setBefore] = useState<SurvivalRecord>(state.survival);
  const [thinking, setThinking] = useState(false);
  /** The book has nothing for the opponent here, so the engine plays. */
  const [engineTurn, setEngineTurn] = useState(false);
  const [miss, setMiss] = useState<MissFlash | null>(null);
  const picker = useRef(mulberry32(Math.floor(Math.random() * 2 ** 31)));
  /** True once the run has ended, so a late verdict or engine move lands nowhere. */
  const over = useRef(false);

  const run = game?.state.run ?? null;
  const live = phase === 'playing' && !!run;
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
    endSurvival(line, ended.moves);
    const region = nodeById(tree, ended.run.openingId);
    endRound({
      mode: 'survival',
      openingId: deepestNodeWithin(tree, region, line).id,
      color: ended.run.color,
      answered: ended.moves + (how.kind === 'blunder' ? 1 : 0),
      correct: ended.moves,
      perfect: how.kind !== 'blunder' && how.kind !== 'lost' && ended.misses.length === 0,
    });
    buzz(how.kind === 'blunder' || how.kind === 'lost' ? [22, 60, 22] : 14);
    setEnding(how);
    setMiss(null);
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

  /** Counted as activity, never rated: Survival does not move a rating. */
  const tally = (line: string[], correct: boolean) => {
    if (!run) return;
    recordMove({ mode: 'survival', line, color: run.color, correct, rated: false });
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
        if (run.repertoireId) missed(run.repertoireId, run.fen, judged.san, expected[0]);
      }
      if (!judged.ok) {
        finish(game.state, { kind: 'blunder', played: judged.san, best: judged.best, lost: judged.lost });
        return;
      }
      buzz(expected.length ? 14 : 10);
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

  /** A miss clears itself, and a tap clears it sooner. */
  useEffect(() => {
    if (!miss) return;
    const timer = window.setTimeout(() => setMiss(null), MISS_MS);
    return () => window.clearTimeout(timer);
  }, [miss]);

  const start = (chosen: SurvivalPrefs) => {
    const begun = startSurvival({
      steer: chosen.steer,
      tree,
      reps: repertoireList(useStore.getState()),
      node: nodeById(tree, selection.opening),
      color: selection.color,
      weakness: weaknessFromCards(cards, evidence),
      growth: settings.growth,
      holeWeight: evidenceFor(evidence),
      seen: seenIn(useStore.getState().score),
    });
    if (!begun) return;
    over.current = false;
    judge.reset();
    setPrefs(chosen);
    setEnding(null);
    setMiss(null);
    setEngineTurn(false);
    setThinking(false);
    setGame({ source: begun.source, state: begun.state, redraw: begun.redraw });
    setPhase('playing');
  };

  if (phase === 'setup' || !game || !run) {
    return <Setup onStart={start} onExit={onExit} />;
  }

  if (phase === 'over' && ending) {
    return (
      <End
        state={game.state}
        ending={ending}
        before={before}
        onNext={() => start(prefs)}
        onChangeOptions={() => setPhase('setup')}
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
      afterMove({ ...game, state: playYours(game.state, move.san) });
      return;
    }
    judge.submit(run.fen, move);
  };

  /** Your move stands on the board while the engine judges it. */
  const shownFen = judge.pending ? (applySan(run.fen, judge.pending.san)?.after ?? run.fen) : run.fen;
  const shownLine = judge.pending ? [...run.played, judge.pending.san] : run.played;

  return (
    <>
      <AppBar
        title="Survival"
        subtitle={selectionText(run.color, run.enteredIn ?? run.openingId)}
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
          fen={shownFen}
          orientation={run.color}
          interactive={live && myTurn && !thinking && !judge.pending}
          movableFor={run.color}
          onMove={onMove}
          lastMove={lastMoveOf(shownLine)}
          arrows={miss ? [{ from: miss.from, to: miss.to, color: 'var(--good)' }] : []}
          showCoordinates={settings.showCoordinates}
          theme={settings.boardTheme}
          captured
          overlay={
            miss && (
              <div className="board-flash top" onPointerDown={() => setMiss(null)}>
                <div className="flash-pill">
                  <div className="verdict accent" style={{ padding: 0 }}>
                    Off your prep · {miss.expected} was yours
                  </div>
                </div>
              </div>
            )
          }
        />

        {run.opened > 0 && (
          <div className="center small muted mt-8">From {sansToMoveText(run.played.slice(0, run.opened))}</div>
        )}

        <div className="spacer" />

        <div className="prompt">
          <div className="who">
            {thinking || judge.pending || engineTurn ? (
              <span className="spinner" />
            ) : (
              <span className={`side ${run.color}`} />
            )}
            {judge.pending ? 'Judging' : thinking || engineTurn || !myTurn ? 'Reply' : 'Your move'}
          </div>
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
