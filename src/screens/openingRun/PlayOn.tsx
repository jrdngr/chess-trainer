import { useEffect, useState } from 'react';
import { Board } from '../../components/Board';
import { AppBar, haptic, Icons, Section } from '../../components/ui';
import {
  applyUci,
  fenTurn,
  lastMoveOf,
  positionStatus,
  sansToMoveText,
  walkSan,
  type Color,
  type LegalMove,
} from '../../chess/core';
import { formatScore } from '../../engine/types';
import { useEngine } from '../../engine/useEngine';
import { useStore } from '../../store/useStore';

/**
 * A game carried on past the end of a run, against the engine.
 *
 * Stockfish if its worker starts, the heuristic evaluator otherwise. You keep
 * your own colour, the engine answers with a short fixed think, moves can be
 * taken back a pair at a time, and nothing here touches the record.
 */
export function PlayOn({
  from,
  color,
  label,
  onBack,
}: {
  /** The position the continuation starts from. */
  from: string;
  color: Color;
  label: string;
  onBack: () => void;
}) {
  const settings = useStore((s) => s.settings);
  const [sans, setSans] = useState<string[]>([]);
  const { fens } = walkSan(sans, from);
  const fen = fens[fens.length - 1];
  const status = positionStatus(fen);
  const engineTurn = fenTurn(fen) !== color;

  const { snapshot } = useEngine(fen, { enabled: true, movetime: 700, multiPv: 1, debounceMs: 120 });

  useEffect(() => {
    if (!engineTurn || status.gameOver) return;
    // A stopped search reports back under its old position, so check the fen.
    if (snapshot.fen !== fen || snapshot.thinking) return;
    const best = snapshot.lines[0]?.pv[0];
    const move = best ? applyUci(fen, best) : null;
    if (move) setSans((s) => [...s, move.san]);
  }, [engineTurn, status.gameOver, snapshot, fen]);

  const onMove = (move: LegalMove) => {
    if (engineTurn || status.gameOver) return;
    if (settings.hapticFeedback) haptic(10);
    setSans((s) => [...s, move.san]);
  };

  /** Undo your move and the engine's reply together. */
  const takeBack = () => setSans((s) => s.slice(0, -2));

  const yourMoves = sans.filter((_, i) => fenTurn(fens[i]) === color).length;
  const best = snapshot.fen === fen ? snapshot.lines[0] : undefined;
  const won = status.checkmate && fenTurn(fen) !== color;
  const result = !status.gameOver
    ? null
    : status.checkmate
      ? won
        ? 'Checkmate — you won'
        : 'Checkmate — you lost'
      : status.stalemate
        ? 'Stalemate'
        : 'Drawn';

  return (
    <>
      <AppBar
        title="Playing on"
        subtitle={label}
        onBack={onBack}
        actions={<span className="chip num wide">{best ? formatScore(best) : '—'}</span>}
      />

      <div className="screen no-nav">
        <Board
          fen={fen}
          orientation={color}
          interactive={!engineTurn && !status.gameOver}
          movableFor={color}
          onMove={onMove}
          lastMove={lastMoveOf(sans, from)}
          showCoordinates={settings.showCoordinates}
          theme={settings.boardTheme}
          dimmed={status.gameOver}
        />

        <div className="spacer" />

        {result ? (
          <div className={`verdict ${won ? 'ok' : 'no'}`}>
            <span className="ico">{won ? <Icons.check size={18} /> : <Icons.cross size={18} />}</span>
            {result}
          </div>
        ) : (
          <div className="prompt">
            <div className="who">
              {engineTurn ? <span className="spinner" /> : <span className={`side ${color}`} />}
              {engineTurn ? 'Thinking' : 'Your move'}
            </div>
          </div>
        )}

        {sans.length > 0 && (
          <>
            <Section title="From the end of the line" />
            <div className="card movetext">{sansToMoveText(sans, from)}</div>
          </>
        )}

        <div className="spacer" />
        <div className="actions">
          <button className="btn block" disabled={yourMoves === 0 || engineTurn} onClick={takeBack}>
            <Icons.prev size={18} />
            Take back
          </button>
          <button className="btn plain block" onClick={onBack}>
            Back to the line
          </button>
        </div>
      </div>
    </>
  );
}
