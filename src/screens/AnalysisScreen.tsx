import { useMemo, useState } from 'react';
import { AddLineSheet } from '../components/AddLineSheet';
import { Board } from '../components/Board';
import { ExplorerPanel } from '../components/ExplorerPanel';
import { IconButton, Icons, MoveStrip, Sheet, toast } from '../components/ui';
import { applySan, applyUci, lastMoveOf, positionStatus, sansToMoveText, START_FEN, walkSan, type LegalMove } from '../chess/core';
import { mainline, parsePgn, toPgn, wrapPgn } from '../chess/pgn';
import { formatScore, winFraction } from '../engine/types';
import { useEngine } from '../engine/useEngine';
import { openingNameForPath } from '../model/reference';
import { referenceIndex } from '../model/referenceIndex';
import { useStore } from '../store/useStore';

export function AnalysisScreen() {
  const settings = useStore((s) => s.settings);
  const setSettings = useStore((s) => s.setSettings);
  const [sans, setSans] = useState<string[]>([]);
  const [cursor, setCursor] = useState(0);
  const [orientation, setOrientation] = useState<'w' | 'b'>('w');
  const [showPgn, setShowPgn] = useState(false);
  const [pgnText, setPgnText] = useState('');
  const [addLine, setAddLine] = useState<string[] | null>(null);
  const [showReference, setShowReference] = useState(true);

  const visible = sans.slice(0, cursor);
  const { fens } = useMemo(() => walkSan(visible, START_FEN), [visible]);
  const fen = fens[fens.length - 1];
  const status = useMemo(() => positionStatus(fen), [fen]);

  const { snapshot, sanLines, backend } = useEngine(settings.engineEnabled ? fen : null, {
    enabled: settings.engineEnabled,
    depth: 16,
    multiPv: 3,
  });

  const best = sanLines[0];
  const fraction = winFraction(best);
  const opening = useMemo(() => openingNameForPath(referenceIndex(), visible), [visible]);
  const bestArrow = useMemo(() => {
    const move = settings.engineEnabled && best?.pv[0] ? applyUci(fen, best.pv[0]) : null;
    return move ? [{ from: move.from, to: move.to }] : [];
  }, [settings.engineEnabled, best, fen]);

  const play = (san: string) => {
    const move = applySan(fen, san);
    if (!move) return;
    const next = [...visible, move.san];
    setSans(next);
    setCursor(next.length);
  };

  const onBoardMove = (move: LegalMove) => play(move.san);

  const loadPgn = () => {
    const games = parsePgn(pgnText);
    if (!games.length) {
      toast("Couldn't read that PGN");
      return;
    }
    const moves = mainline(games[0]);
    if (!moves.length) {
      toast('No moves found');
      return;
    }
    setSans(moves);
    setCursor(moves.length);
    setShowPgn(false);
  };

  const exportPgn = () => {
    const nodes = visible.reduceRight<{ san: string; children: never[] }[]>((children, san) => {
      return [{ san, children: children as never[] }];
    }, []);
    const pgn = toPgn(
      { Event: 'Analysis', Result: '*', Date: new Date().toISOString().slice(0, 10).replace(/-/g, '.') },
      nodes,
    );
    setPgnText(wrapPgn(pgn));
    setShowPgn(true);
  };

  const engineLabel =
    backend === 'stockfish' ? 'Stockfish' : backend === 'heuristic' ? 'Basic evaluator' : 'Engine';

  return (
    <>
      <div className="appbar">
        <div className="appbar-title">
          {opening ? (
            <>
              <div className="line" style={{ fontSize: 20 }}>{opening.name}</div>
              <div className="sub">{opening.eco}</div>
            </>
          ) : (
            <h1>Analysis</h1>
          )}
        </div>
        <IconButton label="Flip board" onClick={() => setOrientation((o) => (o === 'w' ? 'b' : 'w'))}>
          <Icons.flip size={20} />
        </IconButton>
        <IconButton label="PGN" onClick={() => setShowPgn(true)}>
          <Icons.note size={20} />
        </IconButton>
      </div>

      <div className="screen">
        {settings.engineEnabled && (
          <div className="row" style={{ gap: 10, marginBottom: 10, padding: '0 2px' }}>
            <span className="num" style={{ minWidth: 50, fontWeight: 700, fontSize: 15 }}>
              {best ? formatScore(best) : '—'}
            </span>
            <div className="evalbar grow">
              <i style={{ width: `${fraction * 100}%` }} />
            </div>
            <span className="tiny faint num" style={{ minWidth: 30, textAlign: 'right' }}>
              d{snapshot.depth || 0}
            </span>
          </div>
        )}

        <Board
          fen={fen}
          orientation={orientation}
          onMove={onBoardMove}
          movableFor="both"
          lastMove={lastMoveOf(visible)}
          showCoordinates={settings.showCoordinates}
          theme={settings.boardTheme}
          arrows={bestArrow}
          captured
        />

        <div className="spacer sm" />
        <MoveStrip sans={sans} cursor={cursor} onSeek={setCursor} hint="Play a move" />

        {status.gameOver && (
          <div className="card center mt-8" style={{ fontWeight: 700 }}>
            {status.checkmate ? 'Checkmate' : status.stalemate ? 'Stalemate' : 'Draw'}
          </div>
        )}

        <div className="section">
          <span>{engineLabel}</span>
          <button
            className={`chip${settings.engineEnabled ? ' on' : ''}`}
            onClick={() => setSettings({ engineEnabled: !settings.engineEnabled })}
          >
            {settings.engineEnabled ? 'On' : 'Off'}
          </button>
        </div>
        {settings.engineEnabled && (
          <div className="list">
            {sanLines.length === 0 && (
              <div className="list-row small faint" style={{ minHeight: 46 }}>
                {backend === null ? 'Starting…' : snapshot.thinking ? 'Thinking…' : 'No lines'}
              </div>
            )}
            {sanLines.map((line) => (
              <button
                key={line.multipv}
                className="engine-line"
                onClick={() => {
                  const move = applyUci(fen, line.pv[0]);
                  if (move) play(move.san);
                }}
              >
                <span className={`engine-score ${(line.cp ?? 0) >= 0 ? 'pos' : 'neg'}`}>
                  {formatScore(line)}
                </span>
                <span className="engine-pv">{sansToMoveText(line.sans, fen)}</span>
              </button>
            ))}
          </div>
        )}

        <div className="section">
          <span>Reference</span>
          <button className="chip" onClick={() => setShowReference((v) => !v)}>
            {showReference ? 'Hide' : 'Show'}
          </button>
        </div>
        {showReference && <ExplorerPanel fen={fen} path={visible} onPlay={play} compact />}

        {visible.length > 0 && (
          <>
            <div className="spacer" />
            <div className="row gap-8">
              <button className="btn soft grow" onClick={exportPgn}>
                PGN
              </button>
              <button className="btn primary grow" onClick={() => setAddLine(visible)}>
                <Icons.plus size={18} /> Add to repertoire
              </button>
            </div>
          </>
        )}
      </div>

      <Sheet open={showPgn} onClose={() => setShowPgn(false)} title="PGN">
        <textarea
          className="field"
          style={{ minHeight: 180 }}
          placeholder="Paste PGN"
          value={pgnText}
          onChange={(e) => setPgnText(e.target.value)}
        />
        <div className="spacer sm" />
        <div className="row gap-8">
          <button className="btn grow" onClick={exportPgn} disabled={!visible.length}>
            From board
          </button>
          <button className="btn primary grow" disabled={!pgnText.trim()} onClick={loadPgn}>
            Load
          </button>
        </div>
      </Sheet>

      <AddLineSheet
        open={!!addLine}
        onClose={() => setAddLine(null)}
        sans={addLine ?? []}
        source="pgn"
        title="Add to repertoire"
      />
    </>
  );
}

