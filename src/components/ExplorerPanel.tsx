import { useMemo } from 'react';

import { lookup, movePercent, formatGameCount, totalGamesAt, openingNameForPath } from '../model/reference';
import { BOOK_SOURCE } from '../model/book';
import { referenceIndex } from '../model/referenceIndex';
import type { ExplorerMove, ReferenceGame } from '../model/types';
import { Icons } from './ui';

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
          <div className="row between" style={{ marginBottom: 6 }}>
            <div className="grow truncate" style={{ fontWeight: 700 }}>{named.name}</div>
            <span className="chip">{named.eco}</span>
          </div>
        )}
        <div className="small faint">No reference games</div>
      </div>
    );
  }

  const moves = compact ? entry.moves.slice(0, 5) : entry.moves;
  const name = named?.name ?? entry.opening;
  const eco = named?.eco ?? entry.eco;

  return (
    <div className="list">
      <div className="exp-head">
        <div className="grow truncate">
          {name && <div className="name truncate">{name}</div>}
          <div className="games">{formatGameCount(total)} games</div>
        </div>
        {eco && <span className="chip">{eco}</span>}
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
        <>
          <div className="exp-head" style={{ paddingTop: 16, borderTop: '1px solid var(--line)' }}>
            <div className="name">Games</div>
          </div>
          {entry.topGames.map((game, i) => (
            <button key={i} className="list-row" onClick={() => onPickGame?.(game)}>
              <span className="grow">
                <div className="title truncate">
                  {game.white} – {game.black}
                </div>
                <div className="meta truncate">
                  {game.event} · {game.year}
                </div>
              </span>
              <span className="chip">{game.result}</span>
              <Icons.chevron size={16} />
            </button>
          ))}
        </>
      ) : null}

      {!compact && (
        <div className="small faint" style={{ padding: '10px 2px 0' }}>
          {BOOK_SOURCE}
        </div>
      )}
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
        {inRepertoire && <span className="star"><Icons.star size={12} filled /></span>}
      </span>
      <span className="exp-bar">
        <span className="w" style={{ width: `${w}%` }}>{w > 17 ? Math.round(w) : ''}</span>
        <span className="d" style={{ width: `${d}%` }}>{d > 17 ? Math.round(d) : ''}</span>
        <span className="b" style={{ width: `${b}%` }}>{b > 17 ? Math.round(b) : ''}</span>
      </span>
      <span className="exp-pct">
        {pct >= 1 ? `${Math.round(pct)}%` : '<1%'}
        <span className="n">{formatGameCount(move.games)}</span>
      </span>
    </button>
  );
}
