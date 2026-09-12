import { useMemo, useState } from 'react';
import { Board } from '../../components/Board';
import { AppBar, Icons, Section, Sheet, toast } from '../../components/ui';
import { applySan, sansToMoveText } from '../../chess/core';
import { formatGameCount, movePercent, totalGamesAt, lookup } from '../../model/reference';
import { referenceIndex } from '../../model/referenceIndex';
import { displayName } from '../../model/repertoire';
import { candidateAnswers, findGaps, type Gap } from '../../model/gaps';
import { repertoireList, useStore } from '../../store/useStore';

export interface GapScreenProps {
  onExit: () => void;
}

const THRESHOLDS = [3, 1, 0.2];

/**
 * Gap: replies the world plays that your repertoire has no answer to.
 *
 * The list is the mode. Each row is one decision — pick a move from the book
 * and it goes straight into the repertoire, which is the only thing that makes
 * the gap stop existing.
 */
export function GapScreen({ onExit }: GapScreenProps) {
  const state = useStore();
  const reps = repertoireList(state);
  const addLine = useStore((s) => s.addLine);
  const index = referenceIndex();

  const [minShare, setMinShare] = useState(THRESHOLDS[1]);
  const [open, setOpen] = useState<Gap | null>(null);

  const gaps = useMemo(
    () => reps.flatMap((rep) => findGaps(rep, index, { minShare })),
    [reps, index, minShare],
  );

  const fix = (gap: Gap, answer: string) => {
    addLine(gap.repertoireId, [...gap.path, gap.san, answer], 'manual');
    setOpen(null);
    toast(`${answer} added`);
  };

  return (
    <>
      <AppBar
        title="Gap"
        subtitle={gaps.length === 1 ? '1 reply unanswered' : `${gaps.length} replies unanswered`}
        onClose={onExit}
      />

      <div className="screen no-nav">
        <div className="segmented">
          {THRESHOLDS.map((value) => (
            <button
              key={value}
              className={minShare === value ? 'active' : ''}
              onClick={() => setMinShare(value)}
            >
              {value >= 1 ? `${value}% and up` : 'Anything played'}
            </button>
          ))}
        </div>

        {gaps.length === 0 ? (
          <div className="empty">
            <div className="t">Nothing missing</div>
            <div className="h">
              Your repertoire answers every reply the database plays here, down to {minShare}% of
              games. Gaps appear as you add lines of your own.
            </div>
          </div>
        ) : (
          <>
            <Section title="Unanswered" aside={`${gaps.length}`} />
            <div className="list">
              {gaps.slice(0, 40).map((gap) => (
                <button
                  className="list-row"
                  key={`${gap.repertoireId}-${gap.path.join('')}-${gap.san}`}
                  onClick={() => setOpen(gap)}
                >
                  <span className="grow" style={{ minWidth: 0 }}>
                    <div className="title">
                      {gap.san} <span className="faint">after</span>{' '}
                      {sansToMoveText(gap.path) || 'the start'}
                    </div>
                    <div className="meta">
                      {gap.share}% of games · {formatGameCount(gap.games)} · you answer{' '}
                      {gap.have.join(', ')}
                    </div>
                  </span>
                  <Icons.chevron size={18} />
                </button>
              ))}
            </div>
            {gaps.length > 40 && (
              <div className="note center">
                Showing the 40 shallowest. Fix these and the rest move up.
              </div>
            )}
          </>
        )}
      </div>

      <GapSheet gap={open} onClose={() => setOpen(null)} onPick={fix} />
    </>
  );
}

/** One gap, with the book's answers to choose between. */
function GapSheet({
  gap,
  onClose,
  onPick,
}: {
  gap: Gap | null;
  onClose: () => void;
  onPick: (gap: Gap, answer: string) => void;
}) {
  const state = useStore();
  const index = referenceIndex();
  const answers = useMemo(() => (gap ? candidateAnswers(index, gap.after, 6) : []), [gap, index]);
  const total = useMemo(
    () => (gap ? totalGamesAt(lookup(index, gap.after)) : 0),
    [gap, index],
  );
  if (!gap) return null;

  const rep = state.repertoires[gap.repertoireId];
  const move = applySan(gap.fen, gap.san);

  return (
    <Sheet open onClose={onClose} title={`Answer ${gap.san}`}>
      <div className="note center" style={{ marginTop: 0 }}>
        {sansToMoveText([...gap.path, gap.san])} · {rep ? displayName(rep.name) : ''}
      </div>
      <div className="spacer sm" />
      <Board
        fen={gap.after}
        orientation={rep?.color ?? 'w'}
        interactive={false}
        lastMove={move ? { from: move.from, to: move.to } : null}
        showCoordinates={state.settings.showCoordinates}
        theme={state.settings.boardTheme}
      />
      <div className="spacer" />

      {answers.length === 0 ? (
        <div className="card small muted">
          The database has nothing after {gap.san}. Add an answer from the Repertoire screen.
        </div>
      ) : (
        <div className="list">
          {answers.map((answer) => (
            <button className="list-row" key={answer.san} onClick={() => onPick(gap, answer.san)}>
              <span className="tree-san">{answer.san}</span>
              <span className="grow">
                <div className="meta">
                  {formatGameCount(answer.games)} games ·{' '}
                  {Math.round(movePercent(answer, total))}% of replies
                </div>
              </span>
              <Icons.plus size={18} />
            </button>
          ))}
        </div>
      )}
      <div className="note center">
        Picking one adds {gap.san} and your answer to the repertoire, so it turns up in Drill.
      </div>
    </Sheet>
  );
}
