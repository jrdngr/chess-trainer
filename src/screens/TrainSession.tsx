import { useEffect, useMemo, useRef, useState } from 'react';
import { Board } from '../components/Board';
import { ExplorerPanel } from '../components/ExplorerPanel';
import { AppBar, haptic, Icons, Sheet } from '../components/ui';
import { applySan, sansToMoveText, type LegalMove, type Square } from '../chess/core';
import { openingNameForPath } from '../model/reference';
import { referenceIndex } from '../model/referenceIndex';
import { displayName } from '../model/repertoire';
import {
  buildSession,
  checkAnswer,
  extraPractice,
  mulberry32,
  type SessionMode,
  type TrainingItem,
} from '../model/session';
import type { Grade } from '../model/types';
import { useStore } from '../store/useStore';

export interface TrainSessionProps {
  /** Everything in scope. The session draws from this for as long as you want. */
  items: TrainingItem[];
  mode: SessionMode;
  title: string;
  onExit: () => void;
}

type Phase = 'ask' | 'correct' | 'wrong';

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

export function TrainSession({ items, mode, title, onExit }: TrainSessionProps) {
  const settings = useStore((s) => s.settings);
  const cards = useStore((s) => s.cards);
  const repertoires = useStore((s) => s.repertoires);
  const grade = useStore((s) => s.grade);
  const ensureCard = useStore((s) => s.ensureCard);

  const maxNew = settings.newCardsPerSession;
  const startedAt = useRef(Date.now());
  const shuffler = useRef(mulberry32(Math.floor(Math.random() * 2 ** 31)));
  const [queue, setQueue] = useState<TrainingItem[]>(() =>
    buildSession(items, cards, {
      mode,
      now: Date.now(),
      maxItems: BATCH,
      maxNew,
      seed: Math.floor(Date.now() / 60000),
    }),
  );
  const [index, setIndex] = useState(0);
  const [phase, setPhase] = useState<Phase>('ask');
  const [played, setPlayed] = useState<LegalMove | null>(null);
  const [revealLine, setRevealLine] = useState(false);
  const [showMoves, setShowMoves] = useState(false);
  const [explore, setExplore] = useState(false);
  const [stats, setStats] = useState({ answered: 0, correct: 0 });
  const [stopped, setStopped] = useState(false);

  const item = queue[index];
  const done = stopped;

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
      const batch = [...scheduled, ...filler];
      return batch.length ? [...current, ...batch] : current;
    });
  }, [stopped, items, cards, mode, maxNew, index, queue.length]);

  useEffect(() => {
    if (item) ensureCard(item);
  }, [item, ensureCard]);

  const opening = useMemo(() => {
    if (!item) return null;
    return openingNameForPath(referenceIndex(), item.pathSans);
  }, [item]);

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
    setPhase(result.correct ? 'correct' : 'wrong');
    setStats((s) => ({ answered: s.answered + 1, correct: s.correct + (result.correct ? 1 : 0) }));
    if (settings.hapticFeedback) haptic(result.correct ? 12 : [18, 50, 18]);
    if (!result.correct) {
      // A wrong answer is always a lapse; grade it immediately so the user can
      // spend their attention on understanding rather than on a button.
      grade(item, 'again', move.san, false);
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
    if (!item || !settings.playOpponentReplies) return null;
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
  }, [item, items, repertoires, settings.playOpponentReplies]);

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
    else setStopped(true);
  };

  const onGrade = (value: Grade) => {
    if (!item) return;
    grade(item, value, played?.san ?? null, true);
    if (value === 'again') {
      requeue();
      advance();
      return;
    }
    advance(followUp ?? undefined);
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
    if (phase === 'correct' && played) {
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
            {stats.correct} of {stats.answered} correct
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
          <button className="btn primary block xl" onClick={onExit}>
            Done
          </button>
          <button
            className="btn plain block"
            style={{ marginTop: 8 }}
            onClick={() => setStopped(false)}
          >
            Keep going
          </button>
        </div>
      </>
    );
  }

  if (!item) return null;

  const side = item.orientation === 'white' ? 'w' : 'b';
  const sideLabel = side === 'w' ? 'White' : 'Black';
  const playedEntry = item.expected.find((e) => e.san === played?.san);
  const alternatives = item.expected.filter((e) => !e.preferred).map((e) => e.san);

  return (
    <>
      <AppBar
        title={opening?.name ?? title}
        subtitle={displayName(item.repertoireName)}
        onClose={stop}
        actions={
          <span className="num muted small appbar-gap" style={{ textAlign: 'right' }}>
            {stats.answered}
            {stats.answered > 0 ? ` \u00b7 ${Math.round((stats.correct / stats.answered) * 100)}%` : ''}
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

        {phase === 'correct' && (
          <>
            <div className="verdict ok">
              <span className="ico"><Icons.check size={16} /></span>
              Correct
              {playedEntry?.preferred === false && <span className="chip good">alternative</span>}
            </div>
            {playedEntry?.note && (
              <div className="card small muted mt-8">{playedEntry.note}</div>
            )}
            <div className="spacer" />
            <div className="grades">
              {(['again', 'hard', 'good', 'easy'] as Grade[]).map((g) => (
                <button key={g} className={g} onClick={() => onGrade(g)}>
                  {GRADE_LABELS[g]}
                </button>
              ))}
            </div>
            <div className="center faint tiny" style={{ marginTop: 8 }}>
              How well did you know it?
            </div>
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

            {revealLine && (
              <div className="card movetext mt-8">{sansToMoveText(item.continuation, item.fen)}</div>
            )}

            <div className="spacer" />
            <div className="row gap-8">
              <button className="btn soft grow" onClick={() => setRevealLine((v) => !v)}>
                {revealLine ? 'Hide line' : 'Show line'}
              </button>
              <button className="btn soft grow" onClick={() => setExplore(true)}>
                Explore
              </button>
            </div>
          </>
        )}
      </div>

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
