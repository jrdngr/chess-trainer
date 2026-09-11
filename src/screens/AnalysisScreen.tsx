import { useMemo, useState } from 'react';
import { AddLineSheet } from '../components/AddLineSheet';
import { Board } from '../components/Board';
import { ExplorerPanel } from '../components/ExplorerPanel';
import { Icons, Sheet, toast } from '../components/ui';
import { applySan, applyUci, positionStatus, sansToMoveText, START_FEN, walkSan, type LegalMove } from '../chess/core';
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
      toast('Could not read that PGN');
      return;
    }
    const moves = mainline(games[0]);
    if (!moves.length) {
      toast('No legal moves in that PGN');
      return;
    }
    setSans(moves);
    setCursor(moves.length);
    setShowPgn(false);
    toast(`Loaded ${Math.ceil(moves.length / 2)} moves`);
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

  return (
    <>
      <div className="appbar">
        <div className="appbar-title">
          <div className="line" style={{ fontWeight: 650, fontSize: 17 }}>Analysis</div>
          <div className="sub">
            {opening?.name ?? 'Free board'}
            {backend === 'heuristic' ? ' · basic evaluator' : backend === 'stockfish' ? ' · Stockfish' : ''}
          </div>
        </div>
        <button className="btn plain sm" onClick={() => setOrientation((o) => (o === 'w' ? 'b' : 'w'))}>
          <Icons.flip size={19} />
        </button>
        <button className="btn plain sm" onClick={() => setShowPgn(true)}>
          <Icons.note size={19} />
        </button>
      </div>

      <div className="screen">
        {settings.engineEnabled && (
          <div className="row" style={{ gap: 9, marginBottom: 9 }}>
            <span className="mono small" style={{ minWidth: 52, fontWeight: 700 }}>
              {best ? formatScore(best) : '—'}
            </span>
            <div className="evalbar grow">
              <i style={{ width: `${fraction * 100}%` }} />
            </div>
            <span className="tiny faint" style={{ minWidth: 34, textAlign: 'right' }}>
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
          arrows={
            settings.engineEnabled && best?.pv[0]
              ? (() => {
                  const move = applyUci(fen, best.pv[0]);
                  return move ? [{ from: move.from, to: move.to }] : [];
                })()
              : []
          }
        />

        <div className="spacer" />

        <div className="row" style={{ gap: 6 }}>
          <button className="btn sm ghost" disabled={cursor === 0} onClick={() => setCursor(0)}>
            <Icons.first size={16} />
          </button>
          <button className="btn sm ghost" disabled={cursor === 0} onClick={() => setCursor((c) => c - 1)}>
            <Icons.prev size={16} />
          </button>
          <div className="strip grow">
            {sans.length === 0 && <span className="tiny faint">Play a move, or paste a PGN</span>}
            {sans.map((san, i) => (
              <button
                key={i}
                className={`mv${i === cursor - 1 ? ' current' : ''}`}
                onClick={() => setCursor(i + 1)}
              >
                {i % 2 === 0 ? `${i / 2 + 1}.` : ''}
                {san}
              </button>
            ))}
          </div>
          <button className="btn sm ghost" disabled={cursor >= sans.length} onClick={() => setCursor((c) => c + 1)}>
            <Icons.next size={16} />
          </button>
        </div>

        {status.gameOver && (
          <div className="banner" style={{ marginTop: 10 }}>
            <span className="ico">⚑</span>
            <span>
              {status.checkmate ? 'Checkmate.' : status.stalemate ? 'Stalemate.' : 'Draw.'}
            </span>
          </div>
        )}

        <div className="spacer" />

        <div className="card">
          <div className="row between" style={{ marginBottom: 6 }}>
            <span className="section-title" style={{ margin: 0 }}>Engine</span>
            <button
              className="chip"
              onClick={() => setSettings({ engineEnabled: !settings.engineEnabled })}
            >
              {settings.engineEnabled ? 'On' : 'Off'}
            </button>
          </div>
          {!settings.engineEnabled && (
            <div className="tiny faint">Turned off. Analysis stays available without it.</div>
          )}
          {settings.engineEnabled && sanLines.length === 0 && (
            <div className="tiny faint">
              {backend === null ? 'Starting engine…' : snapshot.thinking ? 'Thinking…' : 'No lines yet.'}
            </div>
          )}
          {sanLines.map((line) => (
            <button
              key={line.multipv}
              className="engine-line"
              style={{ width: '100%', textAlign: 'left' }}
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
          {backend === 'heuristic' && (
            <div className="tiny faint" style={{ marginTop: 8 }}>
              Stockfish could not start in this browser, so a simple built-in evaluator is
              standing in. Numbers are rough.
            </div>
          )}
        </div>

        <div className="spacer" />

        <div className="row between">
          <span className="section-title" style={{ margin: 0 }}>Reference</span>
          <button className="chip" onClick={() => setShowReference((v) => !v)}>
            {showReference ? 'Hide' : 'Show'}
          </button>
        </div>
        <div className="spacer" style={{ height: 8 }} />
        {showReference && <ExplorerPanel fen={fen} path={visible} onPlay={play} compact />}

        {visible.length > 0 && (
          <>
            <div className="spacer" />
            <div className="row" style={{ gap: 8 }}>
              <button className="btn ghost grow" onClick={exportPgn}>
                Export PGN
              </button>
              <button className="btn grow" onClick={() => setAddLine(visible)}>
                Add to repertoire
              </button>
            </div>
          </>
        )}
      </div>

      <Sheet open={showPgn} onClose={() => setShowPgn(false)} title="PGN">
        <textarea
          className="field"
          style={{ minHeight: 180 }}
          placeholder="Paste a PGN here…"
          value={pgnText}
          onChange={(e) => setPgnText(e.target.value)}
        />
        <div className="spacer" />
        <div className="row" style={{ gap: 8 }}>
          <button className="btn ghost grow" onClick={exportPgn}>
            Fill from board
          </button>
          <button className="btn primary grow" disabled={!pgnText.trim()} onClick={loadPgn}>
            Load PGN
          </button>
        </div>
      </Sheet>

      <AddLineSheet
        open={!!addLine}
        onClose={() => setAddLine(null)}
        sans={addLine ?? []}
        source="pgn"
        title="Add analysed line"
      />
    </>
  );
}

function lastMoveOf(sans: string[]) {
  if (!sans.length) return null;
  const { fens } = walkSan(sans.slice(0, -1));
  const move = applySan(fens[fens.length - 1], sans[sans.length - 1]);
  return move ? { from: move.from, to: move.to } : null;
}
