import { useMemo } from 'react';

import { lookup, movePercent, formatGameCount, totalGamesAt, openingNameForPath } from '../model/reference';
import { referenceIndex } from '../model/referenceIndex';
import type { ExplorerMove, ReferenceGame } from '../model/types';

export interface ExplorerPanelProps {
  fen: string;
  /** SAN path to this position, used to name the opening. */
  path: string[];
  /** Moves already in the user's repertoire from this position. */
  inRepertoire?: string[];
  onPlay: (san: string) => void;
  onPickGame?: (game: ReferenceGame) => void;
  compact?: boolean;
}

export function ExplorerPanel({
  fen,
  path,
  inRepertoire = [],
  onPlay,
  onPickGame,
  compact = false,
}: ExplorerPanelProps) {
  const index = useMemo(() => referenceIndex(), []);
  const entry = lookup(index, fen);
  const total = totalGamesAt(entry);
  const named = useMemo(() => openingNameForPath(index, path), [index, path]);

  if (!entry || !entry.moves.length) {
    return (
      <div className="card">
        {named && (
          <div className="row between" style={{ marginBottom: 8 }}>
            <div className="grow truncate" style={{ fontWeight: 650 }}>{named.name}</div>
            <span className="chip">{named.eco}</span>
          </div>
        )}
        <div className="tiny faint">
          Out of the reference sample. This is a small curated database — only mainstream lines
          are covered.
        </div>
      </div>
    );
  }

  const moves = compact ? entry.moves.slice(0, 5) : entry.moves;

  return (
    <div className="card" style={{ padding: '10px 6px 6px' }}>
      <div className="row between" style={{ padding: '0 8px 8px' }}>
        <div className="grow truncate">
          {(named?.name ?? entry.opening) && (
            <div style={{ fontWeight: 650, fontSize: 14 }}>{named?.name ?? entry.opening}</div>
          )}
          <div className="tiny faint">{formatGameCount(total)} games in sample</div>
        </div>
        {(named?.eco ?? entry.eco) && <span className="chip">{named?.eco ?? entry.eco}</span>}
      </div>

      {moves.map((move) => (
        <ExplorerRow
          key={move.san}
          move={move}
          total={total}
          inRepertoire={inRepertoire.includes(move.san)}
          onPlay={() => onPlay(move.san)}
        />
      ))}

      {entry.topGames?.length && !compact ? (
        <div style={{ padding: '10px 8px 4px' }}>
          <div className="section-title" style={{ margin: '4px 0 6px' }}>Master games</div>
          {entry.topGames.map((game, i) => (
            <button
              key={i}
              className="exp-row"
              style={{ padding: '8px 0' }}
              onClick={() => onPickGame?.(game)}
            >
              <div className="grow" style={{ minWidth: 0 }}>
                <div className="small truncate" style={{ fontWeight: 600 }}>
                  {game.white} – {game.black}
                </div>
                <div className="tiny faint truncate">
                  {game.event} · {game.year}
                </div>
              </div>
              <span className="chip">{game.result}</span>
            </button>
          ))}
        </div>
      ) : null}
    </div>
  );
}

function ExplorerRow({
  move,
  total,
  inRepertoire,
  onPlay,
}: {
  move: ExplorerMove;
  total: number;
  inRepertoire: boolean;
  onPlay: () => void;
}) {
  const pct = movePercent(move, total);
  const results = move.white + move.draw + move.black || 1;
  const w = (move.white / results) * 100;
  const d = (move.draw / results) * 100;
  const b = (move.black / results) * 100;
  return (
    <button className="exp-row" onClick={onPlay}>
      <span className="exp-san">
        {move.san}
        {inRepertoire && <span className="exp-inrep"> ★</span>}
      </span>
      <span className="exp-bar">
        <span className="w" style={{ width: `${w}%` }}>{w > 17 ? Math.round(w) : ''}</span>
        <span className="d" style={{ width: `${d}%` }}>{d > 17 ? Math.round(d) : ''}</span>
        <span className="b" style={{ width: `${b}%` }}>{b > 17 ? Math.round(b) : ''}</span>
      </span>
      <span className="exp-count">
        {pct >= 1 ? `${Math.round(pct)}%` : '<1%'}
        <br />
        <span className="faint" style={{ fontSize: 10.5 }}>{formatGameCount(move.games)}</span>
      </span>
    </button>
  );
}

