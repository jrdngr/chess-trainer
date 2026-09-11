import { useEffect, useMemo, useRef, useState } from 'react';
import { Board } from '../components/Board';
import { ExplorerPanel } from '../components/ExplorerPanel';
import { haptic, Icons, Sheet, toast } from '../components/ui';
import { applySan, sansToMoveText, type LegalMove, type Square } from '../chess/core';
import { openingNameForPath } from '../model/reference';
import { referenceIndex } from '../model/referenceIndex';
import { checkAnswer, type TrainingItem } from '../model/session';
import { describeDelay, gradePreview, review } from '../model/srs';
import type { Grade } from '../model/types';
import { useStore } from '../store/useStore';

export interface TrainSessionProps {
  queue: TrainingItem[];
  title: string;
  onExit: () => void;
}

type Phase = 'ask' | 'correct' | 'wrong';

export function TrainSession({ queue: initialQueue, title, onExit }: TrainSessionProps) {
  const settings = useStore((s) => s.settings);
  const cards = useStore((s) => s.cards);
  const repertoires = useStore((s) => s.repertoires);
  const grade = useStore((s) => s.grade);
  const ensureCard = useStore((s) => s.ensureCard);

  const [queue, setQueue] = useState(initialQueue);
  const [index, setIndex] = useState(0);
  const [phase, setPhase] = useState<Phase>('ask');
  const [played, setPlayed] = useState<LegalMove | null>(null);
  const [revealLine, setRevealLine] = useState(false);
  const [showMoves, setShowMoves] = useState(false);
  const [explore, setExplore] = useState(false);
  const [stats, setStats] = useState({ answered: 0, correct: 0 });
  const startedAt = useRef(Date.now());

  const item = queue[index];
  const done = index >= queue.length;

  const card = item ? cards[item.cardId] : undefined;
  const preview = useMemo(
    () => (card ? gradePreview(card) : { again: '1m', hard: '1m', good: '10m', easy: '4d' }),
    [card],
  );

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
      // A wrong answer is always a lapse; grade it immediately and let the
      // user spend their attention on understanding rather than on a button.
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
    return queue
      .concat(initialQueue)
      .find((candidate) => candidate.fen === afterReply.after && candidate.cardId !== item.cardId);
  }, [item, queue, initialQueue, repertoires, settings.playOpponentReplies]);

  const onGrade = (value: Grade) => {
    if (!item) return;
    grade(item, value, played?.san ?? null, true);
    if (value === 'again') {
      // Re-queue it for later in this session.
      setQueue((q) => {
        const next = [...q];
        const insertAt = Math.min(q.length, index + 4);
        next.splice(insertAt, 0, item);
        return next;
      });
      advance();
      return;
    }
    advance(followUp ?? undefined);
  };

  const highlights = useMemo(() => {
    const out: { square: Square; kind: 'good' | 'bad' | 'hint' }[] = [];
    if (phase === 'wrong' && played) {
      out.push({ square: played.from, kind: 'bad' }, { square: played.to, kind: 'bad' });
      if (revealLine && expectedMove) {
        out.push({ square: expectedMove.from, kind: 'good' }, { square: expectedMove.to, kind: 'good' });
      }
    }
    if (phase === 'correct' && played) {
      out.push({ square: played.from, kind: 'good' }, { square: played.to, kind: 'good' });
    }
    return out;
  }, [phase, played, revealLine, expectedMove]);

  const boardFen = useMemo(() => {
    if (phase === 'ask' || !played) return item?.fen ?? '';
    if (phase === 'wrong' && !revealLine) return item?.fen ?? '';
    if (phase === 'wrong' && revealLine && expectedMove) return expectedMove.after;
    return played.after;
  }, [phase, played, revealLine, expectedMove, item]);

  if (done) {
    const elapsed = Math.round((Date.now() - startedAt.current) / 1000);
    const accuracy = stats.answered ? Math.round((stats.correct / stats.answered) * 100) : 0;
    return (
      <div className="app">
        <div className="appbar">
          <button className="btn plain sm" onClick={onExit}>
            <Icons.close size={20} />
          </button>
          <div className="appbar-title">
            <h1>Session complete</h1>
          </div>
        </div>
        <div className="screen no-nav">
          <div className="card center" style={{ padding: '26px 16px' }}>
            <div style={{ fontSize: 44, marginBottom: 6 }}>{accuracy >= 80 ? '🎯' : '📈'}</div>
            <div style={{ fontSize: 30, fontWeight: 750 }}>{accuracy}%</div>
            <div className="muted small">
              {stats.correct} of {stats.answered} positions first time
            </div>
          </div>
          <div className="stat-grid" style={{ marginTop: 10 }}>
            <div className="stat">
              <div className="n">{stats.answered}</div>
              <div className="l">Answered</div>
            </div>
            <div className="stat">
              <div className="n">{Math.floor(elapsed / 60)}:{String(elapsed % 60).padStart(2, '0')}</div>
              <div className="l">Time</div>
            </div>
            <div className="stat">
              <div className="n">{stats.answered ? Math.round((elapsed / stats.answered) * 10) / 10 : 0}s</div>
              <div className="l">Per card</div>
            </div>
          </div>
          <div className="spacer" />
          <button className="btn primary block" onClick={onExit}>
            Done
          </button>
        </div>
      </div>
    );
  }

  if (!item) return null;

  const sideLabel = item.orientation === 'white' ? 'White' : 'Black';
  const progress = ((index + (phase === 'ask' ? 0 : 1)) / queue.length) * 100;

  return (
    <div className="app">
      <div className="appbar">
        <button className="btn plain sm" onClick={onExit} aria-label="End session">
          <Icons.close size={20} />
        </button>
        <div className="appbar-title">
          <div className="line" style={{ fontWeight: 650, fontSize: 15 }}>
            {opening?.name ?? title}
          </div>
          <div className="sub">
            {sideLabel} to play · {item.repertoireName}
          </div>
        </div>
        <div className="mono small muted">
          {Math.min(index + 1, queue.length)}/{queue.length}
        </div>
      </div>

      <div className="progress-track" style={{ margin: '0 14px' }}>
        <div className="progress-fill" style={{ width: `${progress}%` }} />
      </div>

      <div className="screen no-nav" style={{ paddingTop: 12 }}>
        <Board
          fen={boardFen}
          orientation={item.orientation === 'white' ? 'w' : 'b'}
          interactive={phase === 'ask'}
          movableFor={item.orientation === 'white' ? 'w' : 'b'}
          onMove={onBoardMove}
          highlights={highlights}
          showCoordinates={settings.showCoordinates}
          theme={settings.boardTheme}
          dimmed={phase === 'wrong'}
        />

        <div className="spacer" />

        {phase === 'ask' && (
          <>
            <div className="center" style={{ fontWeight: 650, fontSize: 17 }}>
              What do you play here?
            </div>
            <div className="center tiny faint" style={{ marginTop: 3 }}>
              Move {Math.floor(item.pathSans.length / 2) + 1} · {item.expected.length > 1
                ? `${item.expected.length} moves in your repertoire`
                : 'from memory'}
            </div>
            <div className="spacer" />
            <div className="row" style={{ gap: 8 }}>
              <button className="btn ghost grow" onClick={() => setShowMoves((v) => !v)}>
                {showMoves ? 'Hide moves' : 'Moves so far'}
              </button>
              <button className="btn ghost grow" onClick={() => setExplore(true)}>
                Explore
              </button>
            </div>
            {showMoves && (
              <div className="card small mono" style={{ marginTop: 10, lineHeight: 1.7 }}>
                {sansToMoveText(item.pathSans) || 'Starting position'}
              </div>
            )}
          </>
        )}

        {phase === 'correct' && (
          <>
            <div className="verdict ok">
              <Icons.check size={22} /> Correct
            </div>
            <div className="center muted small" style={{ marginTop: 2 }}>
              {played?.san}
              {item.expected.find((e) => e.san === played?.san)?.preferred === false && ' · playable alternative'}
            </div>
            {item.expected.find((e) => e.san === played?.san)?.note && (
              <div className="card small" style={{ marginTop: 10 }}>
                {item.expected.find((e) => e.san === played?.san)!.note}
              </div>
            )}
            <div className="spacer" />
            <div className="tiny faint center" style={{ marginBottom: 7 }}>
              How did that feel?
            </div>
            <div className="grade-row">
              {(['again', 'hard', 'good', 'easy'] as Grade[]).map((g) => (
                <button key={g} className={g} onClick={() => onGrade(g)}>
                  <span style={{ textTransform: 'capitalize' }}>{g}</span>
                  <span className="when">{preview[g]}</span>
                </button>
              ))}
            </div>
          </>
        )}

        {phase === 'wrong' && (
          <>
            <div className="verdict no">
              <Icons.cross size={20} /> Not quite
            </div>
            <div className="card" style={{ marginTop: 10 }}>
              <div className="row between">
                <span className="muted small">Your repertoire</span>
                <span style={{ fontWeight: 750, fontSize: 16, color: 'var(--good)' }}>
                  {answer?.preferred?.san}
                </span>
              </div>
              <div className="divider" />
              <div className="row between">
                <span className="muted small">You played</span>
                <span style={{ fontWeight: 700, fontSize: 16, color: 'var(--bad)' }}>
                  {played?.san}
                </span>
              </div>
              {item.expected.length > 1 && (
                <>
                  <div className="divider" />
                  <div className="row between">
                    <span className="muted small">Also prepared</span>
                    <span className="small">
                      {item.expected.filter((e) => !e.preferred).map((e) => e.san).join(', ')}
                    </span>
                  </div>
                </>
              )}
              {answer?.preferred?.note && (
                <>
                  <div className="divider" />
                  <div className="small muted">{answer.preferred.note}</div>
                </>
              )}
            </div>

            {revealLine && (
              <div className="card" style={{ marginTop: 10 }}>
                <div className="section-title" style={{ margin: '0 0 6px' }}>The line continues</div>
                <div className="small mono">{sansToMoveText(item.continuation, item.fen)}</div>
              </div>
            )}

            <div className="spacer" />
            <div className="row" style={{ gap: 8 }}>
              <button className="btn ghost grow" onClick={() => setRevealLine((v) => !v)}>
                {revealLine ? 'Hide line' : 'Show why'}
              </button>
              <button className="btn ghost grow" onClick={() => setExplore(true)}>
                Explore
              </button>
            </div>
            <div className="spacer" />
            <button
              className="btn primary block"
              onClick={() => {
                setQueue((q) => {
                  const next = [...q];
                  next.splice(Math.min(q.length, index + 4), 0, item);
                  return next;
                });
                advance();
              }}
            >
              Continue · back in {describeDelay(review(card ?? ensureCard(item), 'again').delay)}
            </button>
          </>
        )}
      </div>

      <Sheet
        open={explore}
        onClose={() => setExplore(false)}
        title="Reference"
        actions={
          <button className="btn plain sm" onClick={() => setExplore(false)}>
            <Icons.close size={18} />
          </button>
        }
      >
        <div className="tiny faint" style={{ marginBottom: 8 }}>
          {sansToMoveText(item.pathSans) || 'Starting position'}
        </div>
        <ExplorerPanel
          fen={item.fen}
          path={item.pathSans}
          inRepertoire={item.expected.map((e) => e.san)}
          onPlay={(san) => {
            toast(`${san} — open Explore to add lines from here`);
          }}
        />
      </Sheet>
    </div>
  );
}
