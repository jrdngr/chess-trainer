import { useEffect, useMemo, useRef, useState } from 'react';
import { Board } from '../components/Board';
import {
  copyText,
  haptic,
  IconButton,
  Icons,
  Sheet,
  Strip,
  toast,
  type StripItem,
} from '../components/ui';
import {
  applySan,
  applyUci,
  fenTurn,
  positionStatus,
  sansToMoveText,
  walkSan,
  type LegalMove,
  type Square,
} from '../chess/core';
import { formatScore } from '../engine/types';
import { useEngine } from '../engine/useEngine';
import { formatGameCount, type CatalogueEntry } from '../model/reference';
import { referenceIndex } from '../model/referenceIndex';
import {
  beginRun,
  clockDescription,
  clockLabel,
  clockSpec,
  CLOCK_MODES,
  HINT_BUDGETS,
  fullLine,
  extend,
  extendedMoves,
  isComplete,
  isExtended,
  isUsersTurn,
  judgeByEval,
  playExtended,
  BLUNDER_LIMIT,
  lineName,
  lineRecords,
  movesHere,
  opponentReply,
  other,
  outcomeOf,
  play,
  playableRepertoires,
  revealText,
  takeHint,
  timeOut,
  weaknessFromCards,
  type ClockMode,
  type ColorChoice,
  type DeathCause,
  type LineSource,
  type PermadeathOptions,
  type PermadeathRecord,
  type Run,
  type SourceKind,
} from '../model/permadeath';
import { mulberry32 } from '../model/session';
import { displayName } from '../model/repertoire';
import type { Repertoire } from '../model/types';
import { repertoireList, useStore } from '../store/useStore';

export interface PermadeathSessionProps {
  onExit: () => void;
}

type Phase = 'setup' | 'playing' | 'dead' | 'survived' | 'playon';

/** Your move past the prep, held until the engine has scored it. */
interface Pending {
  /** The position you moved in. */
  from: string;
  san: string;
  /** The position you left behind. */
  after: string;
}

/** A game carried on past the end of a line, against the engine. */
interface PlayOn {
  /** The position the continuation started from. */
  from: string;
  fen: string;
  sans: string[];
}

/**
 * One secret line, played until the first mistake.
 *
 * Nothing on screen names the line while it is running — no opening name, no
 * move list, no explore. The reveal is the reward for dying.
 */
export function PermadeathSession({ onExit }: PermadeathSessionProps) {
  const state = useStore();
  const reps = repertoireList(state);
  const settings = state.settings;
  const cards = state.cards;
  const setSettings = useStore((s) => s.setSettings);
  const endRun = useStore((s) => s.endPermadeathRun);
  const missed = useStore((s) => s.missedInPermadeath);
  const record = useStore((s) => s.permadeath);

  const options = useMemo<PermadeathOptions>(
    () => ({
      kind: settings.permadeathSource,
      color: settings.permadeathColor,
      repertoireId: settings.permadeathRepertoire,
      openingId: settings.permadeathOpening,
      reverse: settings.permadeathReverse,
      weakFirst: settings.permadeathWeakFirst,
      clock: settings.permadeathClock,
      hints: settings.permadeathHints,
      extended: settings.permadeathExtended,
    }),
    [settings],
  );

  const [phase, setPhase] = useState<Phase>('setup');
  const [game, setGame] = useState<{ source: LineSource; run: Run } | null>(null);
  const [death, setDeath] = useState<{
    cause: DeathCause;
    played?: string;
    expected: string[];
    /** Centipawns dropped, for a blunder. */
    lost?: number;
  } | null>(null);
  const [thinking, setThinking] = useState(false);
  const [hintSquare, setHintSquare] = useState<Square | null>(null);
  /** Where the post-mortem board is looking. Meaningless while the run is live. */
  const [cursor, setCursor] = useState(0);
  const [playOn, setPlayOn] = useState<PlayOn | null>(null);
  /** A move played past the prep, waiting on the engine's verdict. */
  const [pending, setPending] = useState<Pending | null>(null);
  /** The engine's read on the position you are about to move in. */
  const [baseline, setBaseline] = useState<{ fen: string; cp: number } | null>(null);
  const picker = useRef(mulberry32(Math.floor(Math.random() * 2 ** 31)));
  const settled = useRef(false);

  const source = game?.source ?? null;
  const run = game?.run ?? null;
  const myTurn = run ? isUsersTurn(run) : false;
  const over = phase === 'dead' || phase === 'survived';
  const playing = phase === 'playon';
  const extended = !!run && isExtended(run);

  /* ── clock ─────────────────────────────────────────────────────────────
   * Only your own thinking is charged, so the opponent's beat is free. A
   * per-move budget is refilled at the start of each of your turns; a per-run
   * budget carries what is left of it from turn to turn.
   */
  const spec = useMemo(() => clockSpec(options.clock), [options.clock]);
  const budget = useRef<number | null>(null);
  const [shown, setShown] = useState<number | null>(null);
  const expire = useRef<() => void>(() => {});

  useEffect(() => {
    if (phase !== 'playing' || !myTurn || thinking || pending || budget.current === null) return;
    if (spec.perMove !== null) budget.current = spec.perMove;
    const from = budget.current;
    const startedAt = Date.now();
    setShown(from);
    const timer = setInterval(() => {
      const left = from - (Date.now() - startedAt) / 1000;
      setShown(Math.max(0, left));
      if (left <= 0) {
        clearInterval(timer);
        expire.current();
      }
    }, 100);
    return () => {
      clearInterval(timer);
      // Charge only the time actually spent on this turn.
      budget.current = Math.max(0, from - (Date.now() - startedAt) / 1000);
    };
  }, [phase, myTurn, thinking, !!pending, spec.perMove]);

  const finish = (ended: Run, completed: boolean) => {
    settled.current = true;
    endRun(outcomeOf(ended, completed));
  };

  expire.current = () => {
    if (!run || !source || settled.current || phase !== 'playing') return;
    if (settings.hapticFeedback) haptic([22, 60, 22]);
    setDeath({ cause: 'time', expected: movesHere(source, run) });
    setGame({ source, run: timeOut(run) });
    setPhase('dead');
    finish(run, false);
  };

  // The opponent answers on its own, after a beat.
  useEffect(() => {
    if (!source || !run || phase !== 'playing' || myTurn || run.over || extended) return;
    if (movesHere(source, run).length === 0) return;
    setThinking(true);
    const timer = setTimeout(() => {
      setThinking(false);
      setGame((g) => (g ? { ...g, run: opponentReply(g.source, g.run, picker.current) } : g));
    }, 420);
    return () => clearTimeout(timer);
  }, [source, run, myTurn, phase, extended]);

  /**
   * Lines finish on the user's own move, so the position that ends a run is the
   * opponent's turn with nothing left — checking whose turn it is would miss it.
   */
  /**
   * The prep running out ends the run — unless extended mode is on, in which
   * case the engine takes over the judging and the run carries on.
   */
  useEffect(() => {
    if (!source || !run || phase !== 'playing' || settled.current) return;
    if (!isComplete(source, run)) return;
    if (options.extended) {
      setGame({ source, run: extend(run) });
      return;
    }
    setPhase('survived');
    finish(run, true);
  }, [source, run, phase, options.extended]);

  /* ── the engine ────────────────────────────────────────────────────────
   * Used by two modes: playing on after a run, and extended play inside one.
   * It runs whether or not evaluations are switched on elsewhere — that setting
   * is about seeing numbers during recall, and here the engine is the referee.
   * A short fixed think keeps it quick on the asm.js build, and the heuristic
   * engine covers the case where no worker can start at all.
   *
   * In extended play it is asked about two positions in turn: the one you are
   * about to move in, which gives the score your move is measured against, and
   * the one you leave behind, which gives both the verdict and the reply.
   */
  const gameOverNow = extended && run ? positionStatus(run.fen).gameOver : false;
  const probeFen = playing
    ? (playOn?.fen ?? null)
    : extended && run && !run.over && !gameOverNow
      ? pending
        ? baseline?.fen === pending.from
          ? pending.after
          : pending.from
        : isUsersTurn(run)
          ? run.fen
          : null
      : null;
  const { snapshot } = useEngine(probeFen, {
    enabled: playing || extended,
    movetime: 700,
    multiPv: 1,
    debounceMs: 120,
  });
  const engineTurn = !!playOn && !!run && fenTurn(playOn.fen) !== run.color;
  const finished = playOn ? positionStatus(playOn.fen) : null;

  useEffect(() => {
    if (!playing || !playOn || !engineTurn || finished?.gameOver) return;
    // A stopped search reports back under its old position, so check the fen.
    if (snapshot.fen !== playOn.fen || snapshot.thinking) return;
    const best = snapshot.lines[0]?.pv[0];
    if (!best) return;
    const move = applyUci(playOn.fen, best);
    if (!move) return;
    setPlayOn({ ...playOn, fen: move.after, sans: [...playOn.sans, move.san] });
  }, [playing, playOn, engineTurn, finished?.gameOver, snapshot]);

  /** Keep the score your next move will be measured against. */
  useEffect(() => {
    if (!extended || !run || snapshot.thinking) return;
    const line = snapshot.lines[0];
    if (!snapshot.fen || !line || line.cp === null) return;
    if (snapshot.fen === run.fen && baseline?.fen !== run.fen) {
      setBaseline({ fen: run.fen, cp: line.cp });
    }
    if (pending && snapshot.fen === pending.from && baseline?.fen !== pending.from) {
      setBaseline({ fen: pending.from, cp: line.cp });
    }
  }, [extended, run, pending, snapshot, baseline?.fen]);

  /** Score the move you played, and let the engine answer if it stands. */
  useEffect(() => {
    if (!extended || !run || !source || !pending || settled.current) return;
    if (baseline?.fen !== pending.from) return;
    if (snapshot.fen !== pending.after || snapshot.thinking) return;
    const line = snapshot.lines[0];
    if (!line) return;

    // A forced mate against you reads as a huge swing; take it as one.
    const after = line.cp ?? (line.mate !== null ? (line.mate > 0 ? 10_000 : -10_000) : null);
    if (after === null) return;
    const verdict = judgeByEval(run.color, baseline.cp, after);
    setPending(null);

    if (!verdict.ok) {
      if (settings.hapticFeedback) haptic([22, 60, 22]);
      setDeath({ cause: 'blunder', played: pending.san, expected: [], lost: verdict.lost });
      setGame({ source, run: { ...run, over: true } });
      setPhase('dead');
      finish(run, false);
      return;
    }

    if (settings.hapticFeedback) haptic(10);
    const replyUci = positionStatus(pending.after).gameOver ? null : (line.pv[0] ?? null);
    const reply = replyUci ? applyUci(pending.after, replyUci)?.san ?? null : null;
    setGame({ source, run: playExtended(run, pending.san, reply) });
  }, [extended, run, source, pending, baseline, snapshot]);

  /** Extended play ends with the game, not with the prep. */
  useEffect(() => {
    if (!extended || !run || !source || phase !== 'playing' || settled.current) return;
    if (!gameOverNow) return;
    setPhase('survived');
    finish(run, true);
  }, [extended, run, source, phase, gameOverNow]);

  /** A hint belongs to one position only. */
  useEffect(() => {
    setHintSquare(null);
  }, [run?.fen]);

  /**
   * The line as a board you can walk. Built only once the run is over — while it
   * is live, the continuation is exactly what must not be on screen.
   *
   * The cursor starts where the run ended, so the first thing you see is the
   * position you got wrong, with the next moves a tap away.
   */
  const review = useMemo(() => {
    if (!over || !source || !run) return null;
    const sans = fullLine(source, run);
    return { sans, fens: walkSan(sans).fens, deathPly: run.played.length };
  }, [over, source, run]);

  useEffect(() => {
    if (review) setCursor(review.deathPly);
  }, [review?.deathPly, review?.sans.length]);

  /**
   * The line as chips: your moves, the opponent's, the move that ended the run
   * beside the one that would have continued it, and the rest of the line in
   * grey. The two moves at the death ply share a move number, which is not
   * notation anybody writes — it is the only honest way to show both.
   */
  const strip = useMemo<StripItem[]>(() => {
    if (!review || !run) return [];
    const label = (ply: number) => (ply % 2 === 0 ? `${ply / 2 + 1}.` : undefined);
    const mine = (ply: number) => (ply % 2 === 0) === (run.color === 'w');
    const items: StripItem[] = [];
    // On the losing position the red chip is where you are, so the move that
    // led there does not also claim the cursor.
    const onBlunder = !!death?.played && cursor === review.deathPly;
    const bad = (ply: number): StripItem => ({
      san: death!.played!,
      label: label(ply),
      tone: 'bad',
      seek: review.deathPly,
      current: onBlunder,
    });

    review.sans.forEach((san, ply) => {
      if (ply === review.deathPly && death?.played) {
        // The move you actually played, then the move that was prepared.
        items.push(bad(ply));
        items.push({ san, label: label(ply), tone: 'good', seek: ply + 1, current: cursor === ply + 1 });
        return;
      }
      items.push({
        san,
        label: label(ply),
        tone: ply < review.deathPly ? (mine(ply) ? 'mine' : 'theirs') : 'ghost',
        seek: ply + 1,
        current: !onBlunder && cursor === ply + 1,
      });
    });

    if (death?.played && review.sans.length === review.deathPly) {
      // Nothing was prepared past here, so the losing move is the last chip.
      items.push(bad(review.deathPly));
    }
    return items;
  }, [review, run, death, cursor]);

  /** The line is named only once the run is over, so nothing leaks mid-run. */
  const named = useMemo(
    () =>
      source && run && phase !== 'playing' && phase !== 'setup'
        ? lineName(referenceIndex(), source, run)
        : null,
    [source, run, phase],
  );

  /** Whatever the board is showing: the live position, or the one under review. */
  const shownFen = review ? (review.fens[cursor] ?? run?.fen ?? '') : (run?.fen ?? '');
  /** True when the post-mortem is parked on the position that ended the run. */
  const atDeath = !review || cursor === review.deathPly;

  const lastMove = useMemo(() => {
    const sans = review ? review.sans.slice(0, cursor) : (run?.played ?? []);
    if (sans.length === 0) return null;
    const { fens } = walk(sans.slice(0, -1));
    const move = applySan(fens[fens.length - 1], sans[sans.length - 1]);
    return move ? { from: move.from, to: move.to } : null;
  }, [run, review, cursor]);

  const highlights = useMemo(() => {
    const out: { square: Square; kind: 'good' | 'bad' | 'hint' }[] = [];
    if (phase === 'playing') {
      if (hintSquare) out.push({ square: hintSquare, kind: 'hint' });
      return out;
    }
    if (phase !== 'dead' || !death || !run || !atDeath) return out;
    if (death.played) {
      const wrong = applySan(run.fen, death.played);
      if (wrong) out.push({ square: wrong.from, kind: 'bad' }, { square: wrong.to, kind: 'bad' });
    }
    const right = death.expected[0] ? applySan(run.fen, death.expected[0]) : null;
    if (right) out.push({ square: right.from, kind: 'good' }, { square: right.to, kind: 'good' });
    return out;
  }, [phase, death, run, hintSquare, atDeath]);

  const start = (next: PermadeathOptions) => {
    const started = beginRun({
      ...next,
      reps,
      index: referenceIndex(),
      weakness: weaknessFromCards(cards),
    });
    if (!started) return;
    settled.current = false;
    setDeath(null);
    setHintSquare(null);
    setPending(null);
    setBaseline(null);
    const fresh = clockSpec(next.clock);
    budget.current = fresh.perRun ?? fresh.perMove;
    setShown(budget.current);
    setGame(started);
    setPhase('playing');
  };

  if (phase === 'setup' || !run || !source) {
    return (
      <Setup
        options={options}
        reps={reps}
        record={record}
        perLine={settings.permadeathPerLine}
        favorites={settings.favoriteOpenings}
        onChange={(patch) => setSettings(patch)}
        onStart={start}
        onExit={onExit}
      />
    );
  }

  const onMove = (move: LegalMove) => {
    if (phase !== 'playing' || !myTurn) return;
    if (extended) {
      // Held until the engine has scored it; the board shows it meanwhile.
      if (!pending) setPending({ from: run.fen, san: move.san, after: move.after });
      return;
    }
    const result = play(source, run, move.san);
    if (result.ok) {
      if (settings.hapticFeedback) haptic(10);
      setGame({ source, run: result.run });
      return;
    }
    if (settings.hapticFeedback) haptic([22, 60, 22]);
    setDeath({ cause: 'move', played: result.played, expected: result.expected });
    setGame({ source, run: result.run });
    setPhase('dead');
    finish(run, false);
    // A reversed run is judged on the side you prepared against, so its
    // positions are not decision points and must not touch the schedule.
    if (run.repertoireId && !run.reverse) {
      missed(run.repertoireId, run.fen, result.played, result.expected[0] ?? '');
    }
  };

  const onHint = () => {
    if (phase !== 'playing' || !myTurn || !run.hints) return;
    const taken = takeHint(source, run);
    if (!taken) return;
    if (settings.hapticFeedback) haptic(8);
    setHintSquare(taken.from);
    setGame({ source, run: taken.run });
  };

  /**
   * Carry a finished line on under extended rules.
   *
   * The run itself continues — the score keeps counting and a blunder still ends
   * it — so this is offered only where the prep ran out rather than where you
   * went wrong. Logging it again amends the entry the completed line already
   * made instead of counting a second run.
   */
  const continueExtended = () => {
    if (!run || !source) return;
    settled.current = false;
    setDeath(null);
    setPending(null);
    setBaseline(null);
    setGame({ source, run: extend(run) });
    setPhase('playing');
  };

  /** Carry the game on from whatever the post-mortem board is showing. */
  const beginPlayOn = () => {
    setPlayOn({ from: shownFen, fen: shownFen, sans: [] });
    setPhase('playon');
  };

  /** Back to the line, leaving the cursor where it was. */
  const endPlayOn = () => {
    setPlayOn(null);
    setPhase(death ? 'dead' : 'survived');
  };

  /**
   * Undo your move and the engine's reply together.
   *
   * Only offered when it is your turn and you have actually moved, so the last
   * two plies are always the engine's reply and the move of yours that drew it.
   */
  const takeBack = () => {
    if (!playOn) return;
    const keep = playOn.sans.slice(0, -2);
    setPlayOn({ ...playOn, fen: walkSan(keep, playOn.from).fens[keep.length], sans: keep });
  };

  const onPlayOnMove = (move: LegalMove) => {
    if (!playOn || engineTurn || finished?.gameOver) return;
    if (settings.hapticFeedback) haptic(10);
    setPlayOn({ ...playOn, fen: move.after, sans: [...playOn.sans, move.san] });
  };

  /**
   * The game as it was actually played — your moves and the opponent's, ending
   * on the move that finished the run. Not the continuation: this is meant to be
   * pasted somewhere and discussed.
   */
  const playedText = () => {
    if (!run) return '';
    const sans = death?.played ? [...run.played, death.played] : run.played;
    return sansToMoveText(sans);
  };

  const copyPlayed = async () => {
    const text = playedText();
    if (!text) return;
    if (await copyText(text)) {
      if (settings.hapticFeedback) haptic(10);
      toast('Moves copied');
    } else {
      toast('Could not copy');
    }
  };

  const seek = (n: number) => {
    if (!review) return;
    setCursor(Math.max(0, Math.min(review.sans.length, n)));
  };

  if (playing && playOn) {
    const fens = walkSan(playOn.sans, playOn.from).fens;
    const yourMoves = playOn.sans.filter((_, i) => fenTurn(fens[i]) === run.color).length;
    const previous = fens[playOn.sans.length - 1];
    const played = playOn.sans.length ? applySan(previous, playOn.sans[playOn.sans.length - 1]) : null;
    const best = snapshot.fen === playOn.fen ? snapshot.lines[0] : undefined;
    const result = !finished?.gameOver
      ? null
      : finished.checkmate
        ? fenTurn(playOn.fen) === run.color
          ? 'Checkmate — you lost'
          : 'Checkmate — you won'
        : finished.stalemate
          ? 'Stalemate'
          : 'Drawn';

    return (
      <div className="app">
        <div className="appbar compact">
          <IconButton label="Back to the line" onClick={endPlayOn}>
            <Icons.back size={20} />
          </IconButton>
          <div className="appbar-title">
            <div className="line">Playing on</div>
            <div className="sub">{run.sourceLabel}</div>
          </div>
          <span className="chip num" style={{ minWidth: 52, justifyContent: 'center' }}>
            {best ? formatScore(best) : '—'}
          </span>
        </div>

        <div className="screen no-nav">
          <Board
            fen={playOn.fen}
            orientation={run.color}
            interactive={!engineTurn && !finished?.gameOver}
            movableFor={run.color}
            onMove={onPlayOnMove}
            lastMove={played ? { from: played.from, to: played.to } : null}
            showCoordinates={settings.showCoordinates}
            theme={settings.boardTheme}
            dimmed={!!finished?.gameOver}
          />

          <div className="spacer" />

          {result ? (
            <div className={`verdict ${finished?.checkmate && fenTurn(playOn.fen) !== run.color ? 'ok' : 'no'}`}>
              <span className="ico">
                {finished?.checkmate && fenTurn(playOn.fen) !== run.color ? (
                  <Icons.check size={18} />
                ) : (
                  <Icons.cross size={18} />
                )}
              </span>
              {result}
            </div>
          ) : (
            <div className="prompt">
              <div className="who">
                {engineTurn ? <span className="spinner" /> : <span className={`side ${run.color}`} />}
                {engineTurn ? 'Thinking' : 'Your move'}
              </div>
              <div className="ctx">Nothing here counts against your record</div>
            </div>
          )}

          {playOn.sans.length > 0 && (
            <>
              <div className="section">From the end of the line</div>
              <div className="card">
                <div className="movetext">{sansToMoveText(playOn.sans, playOn.from)}</div>
              </div>
            </>
          )}

          <div className="spacer" />
          <button
            className="btn block"
            disabled={yourMoves === 0 || engineTurn}
            onClick={takeBack}
          >
            <Icons.prev size={18} />
            Take back
          </button>
          <button className="btn plain block" style={{ marginTop: 8 }} onClick={endPlayOn}>
            Back to the line
          </button>
        </div>
      </div>
    );
  }

  const survivedLabel = run.survived === 1 ? '1 move' : `${run.survived} moves`;
  const urgent = shown !== null && shown <= 5;
  const past = extendedMoves(run);
  const liveScore =
    baseline?.fen === run.fen ? formatScore({ cp: baseline.cp, mate: null }) : null;

  return (
    <div className="app">
      <div className="appbar compact">
        <IconButton label="Close" onClick={onExit}>
          <Icons.close size={20} />
        </IconButton>
        <div className="appbar-title">
          <div className="line">Permadeath</div>
          {over && <div className="sub">{phase === 'survived' ? 'Survived' : 'Run over'}</div>}
        </div>
        {!over && extended && (
          <span className="chip accent" style={{ minWidth: 44, justifyContent: 'center' }}>
            {liveScore === null ? '…' : liveScore}
          </span>
        )}
        {!over && shown !== null && (
          <span
            className={`chip${urgent ? ' bad' : ''} num`}
            style={{ minWidth: 52, justifyContent: 'center' }}
          >
            {formatClock(shown)}
          </span>
        )}
        <span className="chip" style={{ minWidth: 38, justifyContent: 'center' }}>
          {run.survived}
        </span>
      </div>

      <div className="screen no-nav">
        <Board
          fen={shownFen}
          orientation={run.color}
          interactive={phase === 'playing' && myTurn && !thinking}
          movableFor={run.color}
          onMove={onMove}
          lastMove={phase === 'dead' && atDeath ? null : lastMove}
          highlights={highlights}
          showCoordinates={settings.showCoordinates}
          theme={settings.boardTheme}
          dimmed={over && atDeath}
        />

        {review && (
          <>
            <div className="spacer sm" />
            <Strip items={strip} cursor={cursor} max={review.sans.length} onSeek={seek} />
            <div className="center faint tiny">
              {whereYouAre(cursor, review.deathPly, phase === 'survived')}
            </div>
          </>
        )}

        <div className="spacer" />

        {phase === 'playing' && (
          <>
            <div className="prompt">
              <div className="who">
                {thinking || pending ? (
                  <span className="spinner" />
                ) : (
                  <span className={`side ${run.color}`} />
                )}
                {pending ? 'Judging' : thinking ? 'Reply' : 'Your move'}
              </div>
              <div className="ctx">
                {hintSquare
                  ? `The move starts on ${hintSquare}`
                  : extended
                    ? 'Past your prep — the engine is calling blunders now'
                    : run.reverse
                      ? 'Play the side your repertoire prepares against'
                      : 'One mistake ends the run'}
              </div>
            </div>
            {run.hints > 0 && !extended && (
              <>
                <div className="spacer sm" />
                <button
                  className="btn soft block"
                  disabled={!myTurn || thinking || hintSquare !== null}
                  onClick={onHint}
                >
                  <Icons.bolt size={18} />
                  {hintSquare ? 'Hint spent' : `Hint (${run.hints} left)`}
                </button>
              </>
            )}
          </>
        )}

        {phase === 'survived' && (
          <>
            <div className="verdict ok">
              <span className="ico">
                <Icons.check size={18} />
              </span>
              Line complete
            </div>
            <div className="center muted small" style={{ marginTop: 2 }}>
              {past > 0 ? (
                <>
                  {survivedLabel} without a slip, {past} of them past{' '}
                  {run.source === 'book' ? 'the book' : 'your prep'} — the game itself ran out
                  before you did.
                </>
              ) : (
                <>
                  You played the whole line — {survivedLabel} without a slip. That is as far as{' '}
                  {run.source === 'book' ? 'the book' : 'your prep'} goes.
                </>
              )}
            </div>
          </>
        )}

        {phase === 'dead' && death && (
          <>
            <div className="verdict no">
              <span className="ico">
                <Icons.cross size={18} />
              </span>
              {death.cause === 'time'
                ? 'Out of time'
                : death.cause === 'blunder'
                  ? 'Blunder'
                  : 'Run over'}
            </div>
            <div className="compare" style={{ marginTop: 10 }}>
              <div className="good">
                <div className="k">
                  {death.cause === 'blunder'
                    ? 'Cost'
                    : run.source === 'book'
                      ? 'Book'
                      : 'Repertoire'}
                </div>
                <div className="v">
                  {death.cause === 'blunder'
                    ? `−${((death.lost ?? 0) / 100).toFixed(2)}`
                    : (death.expected[0] ?? '—')}
                </div>
              </div>
              <div className={death.cause === 'time' ? '' : 'bad'}>
                <div className="k">You played</div>
                <div className="v">{death.played ?? '—'}</div>
              </div>
            </div>
            <div className="center faint tiny" style={{ marginTop: 8 }}>
              {death.cause === 'blunder'
                ? `Past your prep the engine allows a drop of ${(BLUNDER_LIMIT / 100).toFixed(2)} before calling it a blunder.`
                : death.expected.length > 1
                  ? `Any of these would have counted: ${death.expected.slice(0, 6).join(', ')}${death.expected.length > 6 ? '…' : ''}`
                  : death.expected.length === 1
                    ? run.source === 'book'
                      ? 'The only move the database has ever seen here.'
                      : 'The only move you have prepared here — your repertoire is one move wide at this position.'
                    : 'Nothing is prepared here.'}
            </div>
          </>
        )}

        {over && (
          <>
            <div className="spacer" />
            {phase === 'survived' && (
              <>
                <button className="btn accent block xl" onClick={continueExtended}>
                  <Icons.bolt size={18} />
                  Continue in extended mode
                </button>
                <div className="center faint tiny" style={{ marginTop: 6 }}>
                  The prep is done, so the engine takes over the judging. Keep going while your
                  moves stay sound — the run continues and your score keeps counting.
                </div>
                <div className="spacer sm" />
              </>
            )}
            <button
              className={`btn block xl${phase === 'survived' ? '' : ' accent'}`}
              onClick={beginPlayOn}
            >
              <Icons.play size={18} />
              Play from here
            </button>
            <div className="center faint tiny" style={{ marginTop: 6 }}>
              Take the position on the board on against the engine, with nothing at stake.
              Nothing you do there counts against your record.
            </div>

            <div className="section">The line</div>
            <div className="card">
              <div className="row between" style={{ gap: 10 }}>
                <span className="grow" style={{ minWidth: 0 }}>
                  <div style={{ fontWeight: 700, fontSize: 16, letterSpacing: '-0.01em' }}>
                    {named?.name ?? run.sourceLabel}
                  </div>
                  <div className="faint tiny" style={{ marginTop: 2 }}>
                    {named?.specific ? `${run.sourceLabel} · ` : ''}
                    {run.reverse ? 'reversed · ' : ''}
                    {phase === 'survived' && past === 0
                      ? 'played in full'
                      : `${run.survived} correct`}
                    {past > 0 ? ` · ${past} past prep` : ''}
                    {run.hintsUsed > 0
                      ? ` · ${run.hintsUsed} hint${run.hintsUsed === 1 ? '' : 's'}`
                      : ''}
                  </div>
                </span>
                {named?.eco && <span className="chip">{named.eco}</span>}
              </div>
              <div className="divider" />
              <div className="movetext">{revealText(source, run)}</div>
            </div>
            <button className="btn sm block" style={{ marginTop: 8 }} onClick={copyPlayed}>
              <Icons.download size={16} />
              Copy the moves I played
            </button>
            <div className="center faint tiny" style={{ marginTop: 6 }}>
              {playedText() || 'Nothing played'}
            </div>

            <Record record={record} perLine={settings.permadeathPerLine} />

            <div className="spacer" />
            <button className="btn primary block xl" onClick={() => start(options)}>
              New run
            </button>
            <button
              className="btn plain block"
              style={{ marginTop: 8 }}
              onClick={() => setPhase('setup')}
            >
              Change options
            </button>
          </>
        )}
      </div>
    </div>
  );
}

/** Where the post-mortem cursor sits, relative to the end of the run. */
function whereYouAre(cursor: number, deathPly: number, survived: boolean): string {
  const anchor = survived ? 'the end' : 'your mistake';
  const distance = Math.abs(cursor - deathPly);
  const moves = `${distance} move${distance === 1 ? '' : 's'}`;
  if (cursor === deathPly) return survived ? 'The end of the line' : 'Where the run ended';
  return cursor < deathPly ? `${moves} before ${anchor}` : `${moves} after ${anchor}`;
}

function formatClock(seconds: number): string {
  const whole = Math.ceil(seconds);
  if (whole < 60) return `${whole}s`;
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, '0')}`;
}

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div className="list-row">
      <span className="grow">
        <div className="title">{label}</div>
      </span>
      <span className="val num">{value}</span>
    </div>
  );
}

/** The global tally, optionally broken down by opening and side. */
function Record({ record, perLine }: { record: PermadeathRecord; perLine: boolean }) {
  const lines = perLine ? lineRecords(record) : [];
  return (
    <>
      <div className="section">Record</div>
      <div className="list">
        <Stat label="Best run" value={record.best} />
        <Stat label="Runs" value={record.runs} />
        <Stat label="Lines completed" value={record.survivals} />
      </div>
      {perLine && (
        <>
          <div className="section">By opening</div>
          {lines.length === 0 ? (
            <div className="card small muted">
              Nothing yet. Each opening keeps its own best once you have played it.
            </div>
          ) : (
            <div className="list">
              {lines.map((line) => (
                <div className="list-row" key={line.key}>
                  <span className={`side ${line.color}`} />
                  <span className="grow" style={{ minWidth: 0 }}>
                    <div className="title truncate">{line.label}</div>
                    <div className="meta">
                      {line.runs} run{line.runs === 1 ? '' : 's'}
                      {line.survivals > 0 ? ` · ${line.survivals} completed` : ''}
                    </div>
                  </span>
                  <span className="val num">{line.best}</span>
                </div>
              ))}
            </div>
          )}
        </>
      )}
    </>
  );
}

function walk(sans: string[]) {
  const fens = ['rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'];
  for (const san of sans) {
    const move = applySan(fens[fens.length - 1], san);
    if (!move) break;
    fens.push(move.after);
  }
  return { fens };
}

/* ── options ────────────────────────────────────────────────────────────── */

type SettingsPatch = {
  permadeathColor?: ColorChoice;
  permadeathSource?: SourceKind;
  permadeathRepertoire?: string;
  permadeathOpening?: string;
  favoriteOpenings?: string[];
  permadeathReverse?: boolean;
  permadeathWeakFirst?: boolean;
  permadeathClock?: ClockMode;
  permadeathHints?: number;
  permadeathPerLine?: boolean;
  permadeathExtended?: boolean;
};

interface SetupProps {
  options: PermadeathOptions;
  reps: Repertoire[];
  record: PermadeathRecord;
  perLine: boolean;
  favorites: string[];
  onChange: (patch: SettingsPatch) => void;
  onStart: (options: PermadeathOptions) => void;
  onExit: () => void;
}

function Setup({
  options,
  reps,
  record,
  perLine,
  favorites,
  onChange,
  onStart,
  onExit,
}: SetupProps) {
  const repertoire = options.kind === 'repertoire';
  const byOpening = options.kind === 'opening';
  const [browsing, setBrowsing] = useState(false);
  const catalogue = referenceIndex().catalogue;

  const pool = playableRepertoires(reps, options.color, { reverse: options.reverse });
  // A repertoire the colour no longer allows quietly falls back to "any".
  const chosenId = pool.some((r) => r.id === options.repertoireId) ? options.repertoireId : '';
  const starred = favorites
    .map((id) => catalogue.find((entry) => entry.id === id))
    .filter((entry): entry is CatalogueEntry => !!entry);
  const chosenOpening = catalogue.find((entry) => entry.id === options.openingId) ?? null;
  // A pick that was never starred still belongs on this screen, and first, so
  // what the run will actually play is never hidden behind the full list.
  const openingRows =
    chosenOpening && !favorites.includes(chosenOpening.id) ? [chosenOpening, ...starred] : starred;
  const effective = { ...options, repertoireId: chosenId };
  const blocked =
    (repertoire && pool.length === 0) || (byOpening && !chosenOpening);

  const toggleFavorite = (id: string) => {
    onChange({
      favoriteOpenings: favorites.includes(id)
        ? favorites.filter((f) => f !== id)
        : [...favorites, id],
    });
  };

  const pickOpening = (entry: CatalogueEntry) => {
    onChange({ permadeathOpening: entry.id, permadeathSource: 'opening' });
    setBrowsing(false);
  };

  /** Picking an opening settles which side you are on, so say so. */
  const chooseRepertoire = (rep: Repertoire | null) => {
    if (!rep) {
      onChange({ permadeathRepertoire: '' });
      return;
    }
    onChange({
      permadeathRepertoire: rep.id,
      permadeathColor: options.reverse ? other(rep.color) : rep.color,
    });
  };

  return (
    <div className="app">
      <div className="appbar compact">
        <IconButton label="Close" onClick={onExit}>
          <Icons.close size={20} />
        </IconButton>
        <div className="appbar-title">
          <div className="line">Permadeath</div>
          <div className="sub">One secret line. One mistake.</div>
        </div>
        <span style={{ width: 38 }} />
      </div>

      <div className="screen no-nav">
        <button className="btn primary block xl" disabled={blocked} onClick={() => onStart(effective)}>
          {!blocked
            ? 'Start run'
            : byOpening
              ? 'Pick an opening first'
              : options.reverse
                ? 'Nothing to play against'
                : 'No lines for that colour'}
        </button>

        <div className="section">Play as</div>
        <div className="segmented">
          {(['w', 'b', 'random'] as ColorChoice[]).map((value) => (
            <button
              key={value}
              className={options.color === value ? 'active' : ''}
              onClick={() => onChange({ permadeathColor: value })}
            >
              {value === 'w' ? 'White' : value === 'b' ? 'Black' : 'Random'}
            </button>
          ))}
        </div>

        <div className="section">Lines</div>
        <div className="list">
          <button className="list-row" onClick={() => onChange({ permadeathSource: 'repertoire' })}>
            <span className="grow" style={{ minWidth: 0 }}>
              <div className="title">My repertoire</div>
              <div className="meta truncate">
                {pool.length > 0
                  ? pool.map((r) => displayName(r.name)).join(', ')
                  : options.reverse
                    ? 'Nothing prepared against that side'
                    : 'No repertoire for that colour'}
              </div>
            </span>
            {repertoire && <Icons.check size={18} />}
          </button>
          <button className="list-row" onClick={() => onChange({ permadeathSource: 'opening' })}>
            <span className="grow" style={{ minWidth: 0 }}>
              <div className="title">Openings</div>
              <div className="meta truncate">
                {chosenOpening
                  ? chosenOpening.name
                  : starred.length > 0
                    ? `${starred.length} favourite${starred.length === 1 ? '' : 's'} — pick one below`
                    : 'Pick one opening and play it out'}
              </div>
            </span>
            {byOpening && <Icons.check size={18} />}
          </button>
          <button className="list-row" onClick={() => onChange({ permadeathSource: 'book' })}>
            <span className="grow">
              <div className="title">Book</div>
              <div className="meta">Every line in the reference database</div>
            </span>
            {options.kind === 'book' && <Icons.check size={18} />}
          </button>
        </div>

        {byOpening && (
          <>
            <div className="section">
              <span>Your openings</span>
              {starred.length > 0 && <span className="faint tiny">star to keep, tap to pick</span>}
            </div>
            {openingRows.length === 0 ? (
              <div className="card small muted">
                No favourites yet. Open the full list and star the openings you want to
                practise — they will show up here.
              </div>
            ) : (
              <div className="list">
                {openingRows.map((entry) => (
                  <div className="list-row" key={entry.id}>
                    <button
                      className="grow row"
                      style={{ minWidth: 0, gap: 10 }}
                      onClick={() => pickOpening(entry)}
                    >
                      <span className="grow" style={{ minWidth: 0 }}>
                        <div className="title truncate">{entry.name}</div>
                        <div className="meta">
                          {entry.eco} · {sansToMoveText(entry.sans)}
                        </div>
                      </span>
                      {options.openingId === entry.id && <Icons.check size={18} />}
                    </button>
                    <button
                      className="icon-btn plain"
                      aria-label={`${favorites.includes(entry.id) ? 'Unstar' : 'Star'} ${entry.name}`}
                      onClick={() => toggleFavorite(entry.id)}
                    >
                      <Icons.star size={18} filled={favorites.includes(entry.id)} />
                    </button>
                  </div>
                ))}
              </div>
            )}
            <button className="btn sm block" style={{ marginTop: 8 }} onClick={() => setBrowsing(true)}>
              <Icons.book size={16} />
              All openings
            </button>
          </>
        )}

        <OpeningPicker
          open={browsing}
          onClose={() => setBrowsing(false)}
          catalogue={catalogue}
          favorites={favorites}
          selected={options.openingId}
          onPick={pickOpening}
          onToggleFavorite={toggleFavorite}
        />

        {repertoire && pool.length > 1 && (
          <>
            <div className="section">Which repertoire</div>
            <div className="list">
              <button className="list-row" onClick={() => chooseRepertoire(null)}>
                <span className="grow">
                  <div className="title">Any of mine</div>
                  <div className="meta">Drawn across every repertoire that fits</div>
                </span>
                {chosenId === '' && <Icons.check size={18} />}
              </button>
              {pool.map((rep) => (
                <button key={rep.id} className="list-row" onClick={() => chooseRepertoire(rep)}>
                  <span className={`side ${options.reverse ? other(rep.color) : rep.color}`} />
                  <span className="grow" style={{ minWidth: 0 }}>
                    <div className="title truncate">{displayName(rep.name)}</div>
                  </span>
                  {chosenId === rep.id && <Icons.check size={18} />}
                </button>
              ))}
            </div>
          </>
        )}

        <div className="section">Clock</div>
        <div className="segmented">
          {CLOCK_MODES.map((mode) => (
            <button
              key={mode}
              className={options.clock === mode ? 'active' : ''}
              onClick={() => onChange({ permadeathClock: mode })}
            >
              {clockLabel(mode)}
            </button>
          ))}
        </div>
        <div className="faint tiny" style={{ margin: '6px 4px 0' }}>
          {clockDescription(options.clock)}
        </div>

        <div className="section">Hints</div>
        <div className="segmented">
          {HINT_BUDGETS.map((n) => (
            <button
              key={n}
              className={options.hints === n ? 'active' : ''}
              onClick={() => onChange({ permadeathHints: n })}
            >
              {n === 0 ? 'None' : `${n} hint${n === 1 ? '' : 's'}`}
            </button>
          ))}
        </div>
        <div className="faint tiny" style={{ margin: '6px 4px 0' }}>
          {options.hints === 0
            ? 'No help. The position is the whole question.'
            : 'A hint shows the square the move starts from — never where it lands.'}
        </div>

        <div className="section">Extras</div>
        <div className="list">
          {repertoire && (
            <>
              <Toggle
                label="Target weak spots"
                hint="Draw lines you get wrong or have let lapse more often"
                on={options.weakFirst}
                onToggle={() => onChange({ permadeathWeakFirst: !options.weakFirst })}
              />
              <Toggle
                label="Play the other side"
                hint="Sit on the side your repertoire prepares against"
                on={options.reverse}
                onToggle={() =>
                  onChange({ permadeathReverse: !options.reverse, permadeathRepertoire: '' })
                }
              />
            </>
          )}
          <Toggle
            label="Extended mode"
            hint="When the prep runs out, keep going while the engine calls your moves sound"
            on={options.extended}
            onToggle={() => onChange({ permadeathExtended: !options.extended })}
          />
          <Toggle
            label="Per-opening records"
            hint="Keep a separate best for each opening and side"
            on={perLine}
            onToggle={() => onChange({ permadeathPerLine: !perLine })}
          />
        </div>

        <div className="card" style={{ marginTop: 12 }}>
          <div className="small muted">
            {byOpening
              ? chosenOpening
                ? `The opponent walks you into the ${chosenOpening.name}, and its move order is the only thing that counts while you are still in it. After that the book takes over.`
                : 'Pick an opening to play out. Its move order is the only thing that counts while you are still in it; after that the book takes over.'
              : options.kind === 'book'
                ? 'Any move played in the reference database keeps you alive, so the book forgives more than your repertoire does. It is a curated sample, not every game ever played.'
                : options.reverse
                ? 'You play the side your repertoire answers. Staying alive means knowing what your opponent is meant to do — the run ends on any move you have not prepared for.'
                  : 'A line is drawn from your repertoire. Any move you have prepared from a position counts — the run ends the moment you leave your own prep.'}
            {options.extended && (
              <div style={{ marginTop: 8 }}>
                In extended mode the run does not stop there: the engine takes over and you
                survive as long as your moves do not drop more than{' '}
                {(BLUNDER_LIMIT / 100).toFixed(2)}.
              </div>
            )}
          </div>
        </div>

        {record.runs > 0 && <Record record={record} perLine={perLine} />}
      </div>
    </div>
  );
}

/**
 * The full catalogue, most played first, with favourites pulled to the top.
 *
 * Tapping a row picks the opening; the star keeps it on the setup screen so the
 * list only has to be opened once.
 */
function OpeningPicker({
  open,
  onClose,
  catalogue,
  favorites,
  selected,
  onPick,
  onToggleFavorite,
}: {
  open: boolean;
  onClose: () => void;
  catalogue: CatalogueEntry[];
  favorites: string[];
  selected: string;
  onPick: (entry: CatalogueEntry) => void;
  onToggleFavorite: (id: string) => void;
}) {
  const [query, setQuery] = useState('');

  const rows = useMemo(() => {
    const needle = query.trim().toLowerCase();
    const matching = needle
      ? catalogue.filter(
          (entry) =>
            entry.name.toLowerCase().includes(needle) ||
            entry.eco.toLowerCase().startsWith(needle) ||
            entry.sans.join(' ').toLowerCase().includes(needle),
        )
      : catalogue;
    const starred = matching.filter((entry) => favorites.includes(entry.id));
    const rest = matching.filter((entry) => !favorites.includes(entry.id));
    return { starred, rest };
  }, [catalogue, favorites, query]);

  const row = (entry: CatalogueEntry) => (
    <div className="list-row" key={entry.id}>
      <button className="grow row" style={{ minWidth: 0, gap: 10 }} onClick={() => onPick(entry)}>
        <span className="grow" style={{ minWidth: 0 }}>
          <div className="title truncate">{entry.name}</div>
          <div className="meta truncate">
            {entry.eco} · {sansToMoveText(entry.sans)}
            {entry.games > 0 ? ` · ${formatGameCount(entry.games)} games` : ''}
          </div>
        </span>
        {selected === entry.id && <Icons.check size={18} />}
      </button>
      <button
        className="icon-btn plain"
        aria-label={`${favorites.includes(entry.id) ? 'Unstar' : 'Star'} ${entry.name}`}
        onClick={() => onToggleFavorite(entry.id)}
      >
        <Icons.star size={18} filled={favorites.includes(entry.id)} />
      </button>
    </div>
  );

  return (
    <Sheet open={open} onClose={onClose} title="All openings">
      <input
        className="field"
        placeholder="Search by name, ECO or moves"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
      />
      {rows.starred.length > 0 && (
        <>
          <div className="section">Favourites</div>
          <div className="list">{rows.starred.map(row)}</div>
        </>
      )}
      <div className="section">
        <span>{rows.starred.length > 0 ? 'Everything else' : 'Most played first'}</span>
        <span className="faint tiny">{rows.rest.length}</span>
      </div>
      {rows.rest.length === 0 ? (
        <div className="card small muted">Nothing matches that.</div>
      ) : (
        <div className="list">{rows.rest.map(row)}</div>
      )}
    </Sheet>
  );
}

function Toggle({
  label,
  hint,
  on,
  onToggle,
}: {
  label: string;
  hint?: string;
  on: boolean;
  onToggle: () => void;
}) {
  return (
    <button className="list-row" onClick={onToggle}>
      <span className="grow" style={{ minWidth: 0 }}>
        <div className="title">{label}</div>
        {hint && <div className="meta">{hint}</div>}
      </span>
      <span className={`switch${on ? ' on' : ''}`}>
        <i />
      </span>
    </button>
  );
}
