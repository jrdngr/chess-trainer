import { useEffect, useMemo, useState } from 'react';
import { Board } from '../../components/Board';
import { AppBar, haptic, Icons, Section } from '../../components/ui';
import { applySan, sansToMoveText, type LegalMove, type Square } from '../../chess/core';
import { openingNameForPath } from '../../model/reference';
import { referenceIndex } from '../../model/referenceIndex';
import { displayName } from '../../model/repertoire';
import { findPuzzle, isPunishment, type Puzzle } from '../../model/punish';
import { mulberry32 } from '../../model/session';
import { repertoireList, useStore } from '../../store/useStore';

export interface PunishScreenProps {
  onExit: () => void;
}

type Phase = 'ask' | 'right' | 'wrong';

/**
 * Punish: the opponent leaves the book with a move that drops material.
 *
 * Every puzzle comes from a position your own repertoire reaches, so the trap
 * is one you could actually be offered rather than a position from nowhere.
 */
export function PunishScreen({ onExit }: PunishScreenProps) {
  const state = useStore();
  const reps = repertoireList(state);
  const settings = state.settings;
  const index = referenceIndex();

  const [puzzle, setPuzzle] = useState<Puzzle | null>(null);
  const [phase, setPhase] = useState<Phase>('ask');
  const [played, setPlayed] = useState<LegalMove | null>(null);
  const [stats, setStats] = useState({ seen: 0, solved: 0 });
  const [seed, setSeed] = useState(() => Math.floor(Math.random() * 2 ** 31));

  useEffect(() => {
    if (!reps.length) return;
    const rand = mulberry32(seed);
    // Try each repertoire in turn: a thin one may have no trap in it at all.
    const order = [...reps].sort(() => rand() - 0.5);
    for (const rep of order) {
      const found = findPuzzle(rep, index, { seed });
      if (found) {
        setPuzzle(found);
        setPhase('ask');
        setPlayed(null);
        return;
      }
    }
    setPuzzle(null);
  }, [seed, reps.length]);

  const rep = puzzle ? state.repertoires[puzzle.repertoireId] : null;
  const opening = useMemo(
    () => (puzzle ? openingNameForPath(index, [...puzzle.path, puzzle.blunder]) : null),
    [puzzle, index],
  );

  const blunderSquares = useMemo(() => {
    if (!puzzle) return null;
    const move = applySan(puzzle.fen, puzzle.blunder);
    return move ? { from: move.from, to: move.to } : null;
  }, [puzzle]);

  const highlights = useMemo(() => {
    const out: { square: Square; kind: 'good' | 'bad' | 'hint' }[] = [];
    if (!puzzle || phase === 'ask') return out;
    if (phase === 'wrong' && played) {
      out.push({ square: played.from, kind: 'bad' }, { square: played.to, kind: 'bad' });
    }
    const right = applySan(puzzle.after, puzzle.answers[0]);
    if (right) out.push({ square: right.from, kind: 'good' }, { square: right.to, kind: 'good' });
    return out;
  }, [puzzle, phase, played]);

  const onMove = (move: LegalMove) => {
    if (!puzzle || phase !== 'ask') return;
    const right = isPunishment(puzzle, move.san);
    setPlayed(move);
    setPhase(right ? 'right' : 'wrong');
    setStats((s) => ({ seen: s.seen + 1, solved: s.solved + (right ? 1 : 0) }));
    if (settings.hapticFeedback) haptic(right ? 12 : [18, 50, 18]);
  };

  const next = () => setSeed(Math.floor(Math.random() * 2 ** 31));

  if (!puzzle) {
    return (
      <>
        <AppBar title="Punish" onClose={onExit} />
        <div className="screen no-nav">
          <div className="empty">
            <div className="t">No traps to set</div>
            <div className="h">
              {reps.length
                ? 'Nothing in your repertoire offers a move that drops material. Add some lines and come back.'
                : 'Add a repertoire first.'}
            </div>
          </div>
        </div>
      </>
    );
  }

  const answered = phase !== 'ask';
  const board = answered && phase === 'right' && played ? played.after : puzzle.after;

  return (
    <>
      <AppBar
        title={opening?.name ?? 'Punish'}
        subtitle={rep ? displayName(rep.name) : undefined}
        onClose={onExit}
        actions={
          <span className="num muted small appbar-gap" style={{ textAlign: 'right' }}>
            {stats.solved}/{stats.seen}
          </span>
        }
      />

      <div className="screen no-nav">
        <Board
          fen={board}
          orientation={puzzle.color}
          interactive={phase === 'ask'}
          movableFor={puzzle.color}
          onMove={onMove}
          lastMove={phase === 'ask' ? blunderSquares : null}
          highlights={highlights}
          showCoordinates={settings.showCoordinates}
          theme={settings.boardTheme}
          dimmed={phase === 'wrong'}
        />

        <div className="spacer" />

        {phase === 'ask' && (
          <div className="prompt">
            <div className="who">
              <span className={`side ${puzzle.color}`} />
              They played {puzzle.blunder}
            </div>
            <div className="ctx">Win the material</div>
          </div>
        )}

        {answered && (
          <>
            <div className="row between">
              <div className={`verdict ${phase === 'right' ? 'ok' : 'no'}`} style={{ padding: 0 }}>
                <span className="ico">
                  {phase === 'right' ? <Icons.check size={16} /> : <Icons.cross size={14} />}
                </span>
                {phase === 'right' ? `Won ${puzzle.gain} pawns` : 'Not that one'}
              </div>
              <button className="btn primary sm" onClick={next}>
                Next
                <Icons.next size={16} />
              </button>
            </div>
            {phase === 'wrong' && (
              <div className="compare mt-8">
                <div className="good">
                  <div className="k">Punishment</div>
                  <div className="v">{puzzle.answers[0]}</div>
                </div>
                <div className="bad">
                  <div className="k">You played</div>
                  <div className="v">{played?.san}</div>
                </div>
              </div>
            )}
            <div className="note center">
              {puzzle.answers.length > 1
                ? `${puzzle.answers.join(' and ')} both win it.`
                : `${puzzle.answers[0]} wins ${puzzle.gain} pawns.`}
            </div>

            <Section title="The line" />
            <div className="card">
              <div className="movetext">
                {sansToMoveText([...puzzle.path, puzzle.blunder, puzzle.answers[0]])}
              </div>
            </div>
          </>
        )}
      </div>
    </>
  );
}
