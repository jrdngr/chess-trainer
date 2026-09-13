import { useEffect, useMemo, useRef, useState } from 'react';
import { Board } from '../../components/Board';
import { ExplorerPanel } from '../../components/ExplorerPanel';
import { AppBar, haptic, Icons, Sheet, Strip, type StripItem } from '../../components/ui';
import {
  applySan,
  fenTurn,
  fullmoveNumber,
  sansToMoveText,
  walkSan,
  type Color,
  type LegalMove,
  type Square,
} from '../../chess/core';
import type { BoardTheme } from '../../components/Board';
import { formatScore } from '../../engine/types';
import { useEngine } from '../../engine/useEngine';
import {
  buildSession,
  checkAnswer,
  extraPractice,
  mulberry32,
  weakestFirst,
  type SessionMode,
  type TrainingItem,
} from '../../model/session';
import { DEFAULT_DRILL, type DrillPrefs } from '../../model/modes';
import { createCard } from '../../model/srs';
import { clockSeconds } from '../../model/openingRun';
import { comboBonus, POINTS, speedBonus } from '../../model/scoring';
import type { Card, Grade } from '../../model/types';
import { useStore } from '../../store/useStore';
import { ClockHud, useMoveClock } from '../../components/Clock';
import { selectionText } from '../../components/Selection';
import type { GameSummary } from '../../model/autopilot';

export interface DrillSessionProps {
  /** Everything in scope. The session draws from this for as long as you want. */
  items: TrainingItem[];
  mode: SessionMode;
  title: string;
  /** The mode's own options. Sessions launched from a repertoire use defaults. */
  prefs?: Partial<DrillPrefs>;
  /**
   * Stop after this many answers, as one game of an automatic session; the
   * session then reports rather than offering to keep going.
   */
  limit?: number;
  /** The opening the game is credited to; the selection's, unless steered. */
  openingId?: string;
  onGameOver?: (summary: GameSummary) => void;
  onExit: () => void;
}

/** `flash`: a correct move, shown for a beat before the next position. */
type Phase = 'ask' | 'flash' | 'wrong';

/** The queue, in the order the mode asks for. */
function order(
  batch: TrainingItem[],
  cards: Record<string, Card>,
  weakFirst: boolean,
): TrainingItem[] {
  return weakFirst ? weakestFirst(batch, cards) : batch;
}

/**
 * The grade a correct answer earns by how long it took: under three seconds
 * it was instant, under eight you knew it, past that you got there. Never
 * "guessed" — that is a fact about your head, not about the clock.
 */
export function gradeForTime(seconds: number): Grade {
  if (seconds < 3) return 'easy';
  if (seconds < 8) return 'good';
  return 'hard';
}

/** The speed bonus read at the moment of the move rather than the last tick. */
function speedNow(elapsed: number, budget: number | null): number {
  return speedBonus(elapsed, budget);
}

/** How long a correct move stays on the board before the next position. */
const FLASH_MS = 650;

/** How many positions to line up at a time, and when to line up more. */
const BATCH = 20;
const REFILL_AT = 6;

/**
 * What each button says.
 *
 * The stored grades are Anki's, but "again" and "good" are the names of buttons
 * in a spaced-repetition app, not descriptions of what just happened in your
 * head. These are: you didn't really know it, you got there, you knew it, it
 * was instant.
 */
const GRADE_LABELS: Record<Grade, string> = {
  again: 'Guessed',
  hard: 'Hard',
  good: 'Knew it',
  easy: 'Easy',
};

export function DrillSession({
  items,
  mode,
  title,
  prefs,
  limit,
  openingId,
  onGameOver,
  onExit,
}: DrillSessionProps) {
  const options: DrillPrefs = { ...DEFAULT_DRILL, ...prefs };
  const settings = useStore((s) => s.settings);
  const cards = useStore((s) => s.cards);
  const repertoires = useStore((s) => s.repertoires);
  const grade = useStore((s) => s.grade);
  const regrade = useStore((s) => s.regrade);
  const ensureCard = useStore((s) => s.ensureCard);
  const logMistake = useStore((s) => s.logMistake);
  const earn = useStore((s) => s.earn);
  const endGame = useStore((s) => s.endGame);

  const maxNew = options.newPerSession;
  const weakFirst = options.weakFirst;
  const startedAt = useRef(Date.now());
  const shuffler = useRef(mulberry32(Math.floor(Math.random() * 2 ** 31)));
  const [queue, setQueue] = useState<TrainingItem[]>(() =>
    order(
      buildSession(items, cards, {
        mode,
        now: Date.now(),
        maxItems: BATCH,
        maxNew,
        seed: Math.floor(Date.now() / 60000),
      }),
      cards,
      weakFirst,
    ),
  );
  const [index, setIndex] = useState(0);
  const [phase, setPhase] = useState<Phase>('ask');
  const [played, setPlayed] = useState<LegalMove | null>(null);
  const [revealLine, setRevealLine] = useState(false);
  const [showMoves, setShowMoves] = useState(false);
  const [explore, setExplore] = useState(false);
  const [why, setWhy] = useState(false);
  const [stats, setStats] = useState({ answered: 0, correct: 0, earned: 0, streak: 0 });
  const [stopped, setStopped] = useState(false);
  /**
   * The last correct answer, graded off the clock and already on the schedule.
   * The grade buttons stay on screen for the next position and re-grade it,
   * so the flow is move, move, move — with a way to say "I guessed that".
   */
  const [last, setLast] = useState<{ item: TrainingItem; before: Card; grade: Grade; played: string } | null>(null);
  /** Logged once, however the session ends. */
  const logged = useRef(false);

  const item = queue[index];
  const done = stopped;

  const clock = useMoveClock({
    seconds: clockSeconds(options.clock),
    turnKey: `${index}:${item?.cardId ?? ''}`,
    active: phase === 'ask' && !!item && !explore && !showMoves,
  });

  /** Count the session as one game, against the opening it was played in. */
  const log = () => {
    if (logged.current || stats.answered === 0) return;
    logged.current = true;
    const summary = {
      mode: 'drill' as const,
      openingId: openingId ?? settings.selection.opening,
      color: item?.orientation === 'black' ? ('b' as const) : ('w' as const),
      score: stats.earned,
      answered: stats.answered,
      correct: stats.correct,
      perfect: stats.correct === stats.answered && stats.answered >= 5,
    };
    endGame(summary);
    onGameOver?.(summary);
  };

  const card = item ? cards[item.cardId] : undefined;
  /** True once the schedule is clear and this is practice, not a review. */
  const extra = !!card && card.stage === 'review' && card.due > Date.now();

  /**
   * Keep the queue stocked. Scheduled work first; when the schedule is clear,
   * the stalest positions, so the session only ends when you end it.
   */
  useEffect(() => {
    if (stopped || !items.length) return;
    if (queue.length - index > REFILL_AT) return;
    setQueue((current) => {
      const ahead = new Set(current.slice(index).map((i) => i.cardId));
      const now = Date.now();
      const scheduled = buildSession(items, cards, {
        mode,
        now,
        maxItems: BATCH,
        maxNew,
        seed: now,
      }).filter((i) => !ahead.has(i.cardId));
      const taken = new Set(scheduled.map((i) => i.cardId));
      const filler =
        scheduled.length >= BATCH
          ? []
          : extraPractice(
              items,
              cards,
              BATCH - scheduled.length,
              shuffler.current,
              (id) => ahead.has(id) || taken.has(id),
            );
      const batch = order([...scheduled, ...filler], cards, weakFirst);
      return batch.length ? [...current, ...batch] : current;
    });
  }, [stopped, items, cards, mode, maxNew, weakFirst, index, queue.length]);

  useEffect(() => {
    if (item) ensureCard(item);
  }, [item, ensureCard]);

  const answer = useMemo(() => (item && played ? checkAnswer(item, played.san) : null), [item, played]);

  const expectedMove = useMemo(() => {
    if (!item) return null;
    const san = item.expected.find((e) => e.preferred)?.san ?? item.expected[0]?.san;
    return san ? applySan(item.fen, san) : null;
  }, [item]);

  const onBoardMove = (move: LegalMove) => {
    if (!item || phase !== 'ask') return;
    const result = checkAnswer(item, move.san);
    setPlayed(move);
    if (!result.correct) setPhase('wrong');
    const took = clock.elapsedNow();
    // What this answer pays: the base, more for a card you had lapsed on, the
    // speed bonus at the moment of the move, and the combo.
    const streak = result.correct ? stats.streak + 1 : 0;
    const points = result.correct
      ? POINTS.drill.answer +
        (card && card.lapses > 0 ? POINTS.drill.lapsed : 0) +
        speedNow(took, clock.budget) +
        comboBonus(streak)
      : 0;
    earn({
      mode: 'drill',
      points,
      line: [...item.pathSans, move.san],
      color: item.orientation === 'black' ? 'b' : 'w',
      answered: true,
      correct: result.correct,
    });
    setStats((s) => ({
      answered: s.answered + 1,
      correct: s.correct + (result.correct ? 1 : 0),
      earned: s.earned + points,
      streak,
    }));
    if (settings.hapticFeedback) haptic(result.correct ? 12 : [18, 50, 18]);
    if (result.correct) {
      // Graded by the clock and straight on to the next position. The card is
      // kept as it was, so the grade can still be changed from the next screen.
      const auto = gradeForTime(took);
      const before = card ?? createCard(item.cardId, item.repertoireId, item.key, item.fen);
      grade(item, auto, move.san, true);
      setLast({ item, before, grade: auto, played: move.san });
      // A beat on the move you just made, so it registers before the board
      // changes under you.
      setPhase('flash');
      const next = followUp ?? undefined;
      window.setTimeout(() => advance(next), FLASH_MS);
      return;
    }
    if (!result.correct) {
      // A wrong answer is always a lapse; grade it immediately so the user can
      // spend their attention on understanding rather than on a button.
      grade(item, 'again', move.san, false);
      // And it is a real mistake at a real position, so Repair should be able
      // to come back to it later.
      logMistake({
        source: 'drill',
        repertoireId: item.repertoireId,
        key: item.key,
        fen: item.fen,
        path: item.pathSans,
        played: move.san,
        expected: item.expected.find((e) => e.preferred)?.san ?? item.expected[0]?.san ?? '',
      });
    }
  };

  const advance = (extra?: TrainingItem) => {
    setPhase('ask');
    setPlayed(null);
    setRevealLine(false);
    setShowMoves(false);
    if (extra) {
      setQueue((q) => {
        const without = q.filter((i, idx) => idx <= index || i.cardId !== extra.cardId);
        const next = [...without];
        next.splice(index + 1, 0, extra);
        return next;
      });
    }
    setIndex((i) => i + 1);
  };

  /** The next decision point down this line, when following the line through. */
  const followUp = useMemo(() => {
    if (!item || !options.followLine) return null;
    const rep = repertoires[item.repertoireId];
    if (!rep) return null;
    const [mine, reply] = item.continuation;
    if (!mine || !reply) return null;
    const afterMine = applySan(item.fen, mine);
    if (!afterMine) return null;
    const afterReply = applySan(afterMine.after, reply);
    if (!afterReply) return null;
    return items.find(
      (candidate) => candidate.fen === afterReply.after && candidate.cardId !== item.cardId,
    );
  }, [item, items, repertoires, options.followLine]);

  const requeue = () => {
    if (!item) return;
    setQueue((q) => {
      const next = [...q];
      next.splice(Math.min(q.length, index + 4), 0, item);
      return next;
    });
  };

  /** End the session. Answering nothing at all just leaves. */
  const stop = () => {
    if (stats.answered === 0) onExit();
    else {
      log();
      setStopped(true);
    }
  };

  /** A limited session ends itself once the last answer has been dealt with. */
  useEffect(() => {
    if (!limit || phase !== 'ask' || stats.answered < limit || stopped) return;
    log();
    setStopped(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [limit, phase, stats.answered, stopped]);

  /** Change the grade of the last correct answer. Guessed also brings it back soon. */
  const onRegrade = (value: Grade) => {
    if (!last || value === last.grade) return;
    regrade(last.item, last.before, value, last.played);
    if (value === 'again') {
      setQueue((q) => {
        const next = [...q];
        next.splice(Math.min(q.length, index + 4), 0, last.item);
        return next;
      });
    }
    setLast({ ...last, grade: value });
  };

  const highlights = useMemo(() => {
    const out: { square: Square; kind: 'good' | 'bad' | 'hint' }[] = [];
    if (phase === 'wrong' && played) {
      // Green after red, so a square both moves share reads as the right one:
      // the map keeps the last kind written for a square.
      out.push({ square: played.from, kind: 'bad' }, { square: played.to, kind: 'bad' });
      if (expectedMove) {
        out.push({ square: expectedMove.from, kind: 'good' }, { square: expectedMove.to, kind: 'good' });
      }
    }
    if (phase === 'flash' && played) {
      out.push({ square: played.from, kind: 'good' }, { square: played.to, kind: 'good' });
    }
    return out;
  }, [phase, played, expectedMove]);

  const boardFen = useMemo(() => {
    if (phase === 'ask' || !played) return item?.fen ?? '';
    if (phase === 'wrong' && !revealLine) return item?.fen ?? '';
    if (phase === 'wrong' && revealLine && expectedMove) return expectedMove.after;
    return played.after;
  }, [phase, played, revealLine, expectedMove, item]);

  if (done) {
    const elapsed = Math.round((Date.now() - startedAt.current) / 1000);
    const accuracy = stats.answered ? Math.round((stats.correct / stats.answered) * 100) : 0;
    const r = 60;
    const c = 2 * Math.PI * r;
    return (
      <>
        <AppBar title="Session over" onClose={onExit} />
        <div className="screen no-nav">
          <div className="done-ring">
            <svg width="132" height="132" viewBox="0 0 132 132">
              <circle cx="66" cy="66" r={r} fill="none" stroke="var(--surface-2)" strokeWidth="8" />
              <circle
                cx="66"
                cy="66"
                r={r}
                fill="none"
                stroke={accuracy >= 80 ? 'var(--good)' : 'var(--accent)'}
                strokeWidth="8"
                strokeLinecap="round"
                strokeDasharray={c}
                strokeDashoffset={c * (1 - accuracy / 100)}
              />
            </svg>
            <div className="pct">{accuracy}%</div>
          </div>
          <div className="center muted" style={{ marginTop: 14 }}>
            {stats.correct} of {stats.answered} correct · +{stats.earned}
          </div>
          <div className="stat-grid" style={{ marginTop: 24 }}>
            <div className="stat">
              <div className="n">{stats.answered}</div>
              <div className="l">Positions</div>
            </div>
            <div className="stat">
              <div className="n">{Math.floor(elapsed / 60)}:{String(elapsed % 60).padStart(2, '0')}</div>
              <div className="l">Time</div>
            </div>
            <div className="stat">
              <div className="n">{stats.answered ? Math.round((elapsed / stats.answered) * 10) / 10 : 0}s</div>
              <div className="l">Per move</div>
            </div>
          </div>
          <div className="spacer" />
          {!limit && (
            <button className="btn primary block xl" onClick={onExit}>
              Done
            </button>
          )}
          {!limit && (
            <button
              className="btn plain block"
              style={{ marginTop: 8 }}
              onClick={() => setStopped(false)}
            >
              Keep going
            </button>
          )}
        </div>
      </>
    );
  }

  if (!item) return null;

  const side = item.orientation === 'white' ? 'w' : 'b';
  const sideLabel = side === 'w' ? 'White' : 'Black';
  const alternatives = item.expected.filter((e) => !e.preferred).map((e) => e.san);

  return (
    <>
      <AppBar
        title={title}
        subtitle={selectionText(side, openingId ?? settings.selection.opening)}
        onClose={stop}
        actions={
          <span className="row gap-6">
            {phase === 'ask' && <ClockHud clock={clock} />}
            <span className="chip num wide">
              {limit ? `${stats.answered}/${limit}` : stats.answered}
            </span>
          </span>
        }
      />

      <div className="screen no-nav">
        <Board
          fen={boardFen}
          orientation={side}
          interactive={phase === 'ask'}
          movableFor={side}
          onMove={onBoardMove}
          highlights={highlights}
          showCoordinates={settings.showCoordinates}
          theme={settings.boardTheme}
          dimmed={phase === 'wrong'}
          captured
        />

        <div className="spacer" />

        {phase === 'ask' && (
          <>
            <div className="prompt">
              <div className="who">
                <span className={`side ${side}`} />
                {sideLabel} to move
              </div>
              <div className="ctx">
                Move {Math.floor(item.pathSans.length / 2) + 1}
                {item.expected.length > 1 ? ` · ${item.expected.length} options` : ''}
                {extra ? ' · extra practice' : ''}
              </div>
            </div>
            {last && (
              <>
                <div className="spacer sm" />
                <div className="note center">Last move{last.item.expected[0] ? ` · ${last.played}` : ''}</div>
                <div className="grades sm mt-8">
                  {(['again', 'hard', 'good', 'easy'] as Grade[]).map((g) => (
                    <button
                      key={g}
                      className={`${g}${last.grade === g ? ' selected' : ''}`}
                      aria-pressed={last.grade === g}
                      onClick={() => onRegrade(g)}
                    >
                      {GRADE_LABELS[g]}
                    </button>
                  ))}
                </div>
              </>
            )}
            <div className="spacer" />
            <div className="row gap-8">
              <button className="btn soft grow" onClick={() => setShowMoves((v) => !v)}>
                {showMoves ? 'Hide moves' : 'Moves'}
              </button>
              <button className="btn soft grow" onClick={() => setExplore(true)}>
                Explore
              </button>
              <button className="btn soft grow" onClick={stop}>
                Stop
              </button>
            </div>
            {showMoves && (
              <div className="card movetext mt-8">{sansToMoveText(item.pathSans) || 'Start'}</div>
            )}
          </>
        )}

        {phase === 'wrong' && (
          <>
            <div className="row between">
              <div className="verdict no" style={{ padding: 0 }}>
                <span className="ico"><Icons.cross size={14} /></span>
                Wrong
              </div>
              <button
                className="btn primary sm"
                onClick={() => {
                  requeue();
                  advance();
                }}
              >
                Continue
                <Icons.next size={16} />
              </button>
            </div>
            <div className="compare mt-8">
              <div className="good">
                <div className="k">Repertoire</div>
                <div className="v">{answer?.preferred?.san}</div>
              </div>
              <div className="bad">
                <div className="k">Played</div>
                <div className="v">{played?.san}</div>
              </div>
            </div>
            <div className="spacer" />
            <div className="row gap-8">
              {options.explain && (
                <button className="btn soft grow" onClick={() => setWhy(true)}>
                  Why?
                </button>
              )}
              <button className="btn soft grow" onClick={() => setRevealLine((v) => !v)}>
                {revealLine ? 'Hide line' : 'Show line'}
              </button>
              <button className="btn soft grow" onClick={() => setExplore(true)}>
                Explore
              </button>
            </div>

            {revealLine && (
              <div className="card movetext mt-16">{sansToMoveText(item.continuation, item.fen)}</div>
            )}
            {(alternatives.length > 0 || answer?.preferred?.note) && (
              <div className="card small muted mt-8">
                {answer?.preferred?.note}
                {alternatives.length > 0 && (
                  <div className={answer?.preferred?.note ? 'mt-8 faint' : 'faint'}>
                    Also {alternatives.join(', ')}
                  </div>
                )}
              </div>
            )}
          </>
        )}
      </div>

      {played && (
        <WhySheet
          open={why}
          onClose={() => setWhy(false)}
          fen={item.fen}
          side={side}
          played={played}
          expected={expectedMove}
          expectedSan={answer?.preferred?.san}
          theme={settings.boardTheme}
          showCoordinates={settings.showCoordinates}
        />
      )}

      <Sheet open={explore} onClose={() => setExplore(false)} title="Reference">
        <div className="movetext" style={{ marginBottom: 10 }}>
          {sansToMoveText(item.pathSans) || 'Start'}
        </div>
        <ExplorerPanel
          fen={item.fen}
          path={item.pathSans}
          inRepertoire={item.expected.map((e) => e.san)}
          onPlay={() => setExplore(false)}
        />
      </Sheet>
    </>
  );
}

/* ── why a move is wrong ────────────────────────────────────────────────── */

interface Verdict {
  cp: number | null;
  mate: number | null;
  /** The engine's continuation from the position, in SAN. */
  sans: string[];
  /** Captured with the result: the live snapshot is cleared once it is done. */
  depth: number;
}

/**
 * What happens after a wrong move.
 *
 * "It isn't in your repertoire" is a fact, not a reason. The engine plays the
 * position on from the move you made and shows the reply that punishes it,
 * beside what the prepared move would have been worth — so the answer to "why"
 * is a line you can step through rather than a verdict.
 */
function WhySheet({
  open,
  onClose,
  fen,
  side,
  played,
  expected,
  expectedSan,
  theme,
  showCoordinates,
}: {
  open: boolean;
  onClose: () => void;
  /** The position that was asked about. */
  fen: string;
  side: Color;
  played: LegalMove;
  expected: LegalMove | null;
  expectedSan?: string;
  theme: BoardTheme;
  showCoordinates: boolean;
}) {
  const [found, setFound] = useState<{ played?: Verdict; best?: Verdict }>({});
  const [cursor, setCursor] = useState(1);

  // One search at a time: the move you played first, so there is something to
  // read while the prepared move is still being weighed.
  const probe = !open
    ? null
    : !found.played
      ? played.after
      : expected && !found.best
        ? expected.after
        : null;

  const { snapshot, sanLines, backend } = useEngine(probe, {
    enabled: open,
    movetime: 1500,
    multiPv: 1,
    debounceMs: 80,
  });

  useEffect(() => {
    if (!open) return;
    setFound({});
    setCursor(1);
  }, [open, fen, played.san]);

  useEffect(() => {
    if (!open || !probe || snapshot.thinking || snapshot.fen !== probe) return;
    const line = sanLines[0];
    if (!line || (line.cp === null && line.mate === null)) return;
    const verdict: Verdict = {
      cp: line.cp,
      mate: line.mate,
      sans: line.sans,
      depth: line.depth || snapshot.depth,
    };
    setFound((current) =>
      probe === played.after ? { ...current, played: verdict } : { ...current, best: verdict },
    );
  }, [open, probe, snapshot, sanLines, played.after]);

  /**
   * Your move, then how the engine says it gets punished — five moves a side,
   * which is enough to see an idea through rather than just the first hit.
   */
  const line = useMemo(
    () => (found.played ? [played.san, ...found.played.sans.slice(0, 9)] : [played.san]),
    [found.played, played.san],
  );
  const fens = useMemo(() => walkSan(line, fen).fens, [line, fen]);
  const at = Math.min(cursor, fens.length - 1);
  const lastMove = at > 0 ? applySan(fens[at - 1], line[at - 1]) : null;

  /** Scores read from the side that was to move, not from White's. */
  const score = (v?: Verdict) =>
    !v
      ? null
      : formatScore({
          cp: v.cp === null ? null : side === 'w' ? v.cp : -v.cp,
          mate: v.mate === null ? null : side === 'w' ? v.mate : -v.mate,
        });

  const items: StripItem[] = line.map((san, i) => ({
    san,
    label: fenTurn(fens[i]) === 'w' ? `${fullmoveNumber(fens[i])}.` : undefined,
    tone: i === 0 ? 'bad' : 'ghost',
    current: at === i + 1,
    seek: i + 1,
  }));

  return (
    <Sheet open={open} onClose={onClose} title={`Why not ${played.san}?`}>
      <div className="compare">
        <div className="bad">
          <div className="k">{played.san}</div>
          <div className="v">{score(found.played) ?? '…'}</div>
        </div>
        <div className="good">
          <div className="k">{expectedSan ?? 'Repertoire'}</div>
          <div className="v">{expected ? (score(found.best) ?? '…') : '—'}</div>
        </div>
      </div>

      <div className="spacer sm" />
      <Board
        fen={fens[at]}
        orientation={side}
        interactive={false}
        lastMove={lastMove ? { from: lastMove.from, to: lastMove.to } : null}
        showCoordinates={showCoordinates}
        theme={theme}
      />
      <div className="spacer sm" />
      <Strip items={items} cursor={at} max={line.length} onSeek={setCursor} />

      {/* Only what the strip cannot say for itself: that it is still coming, or
          that there is nothing to come. */}
      {(!found.played || found.played.sans.length === 0) && (
        <div className="center faint tiny" style={{ marginTop: 8 }}>
          {!found.played
            ? 'Playing it out…'
            : 'The engine finds nothing forced here — this one is a matter of plan, not tactics.'}
        </div>
      )}
      {found.played && (
        <div className="center faint tiny" style={{ marginTop: 6 }}>
          {backend === 'stockfish' ? 'Stockfish' : 'Rough estimate'} at depth{' '}
          {found.played.depth || '?'}, from the position after each move.
        </div>
      )}
    </Sheet>
  );
}
