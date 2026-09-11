import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  coordsToSquare,
  kingSquare,
  legalMoves,
  piecesFromFen,
  positionStatus,
  squareToCoords,
  type Color,
  type LegalMove,
  type PieceType,
  type Square,
} from '../chess/core';
import { Piece } from './Pieces';
import './board.css';

export type BoardTheme = 'slate' | 'walnut' | 'ocean';

export interface Arrow {
  from: Square;
  to: Square;
  color?: string;
}

export interface BoardProps {
  fen: string;
  orientation: Color;
  /** Called with the chosen move. Return false to reject (e.g. wrong answer animation). */
  onMove?: (move: LegalMove) => void;
  /** Disables all interaction. */
  interactive?: boolean;
  /** Only allow moves by this side. Defaults to the side to move. */
  movableFor?: Color | 'both';
  lastMove?: { from: Square; to: Square } | null;
  /** Squares to tint, e.g. feedback after a wrong answer. */
  highlights?: { square: Square; kind: 'good' | 'bad' | 'hint' }[];
  arrows?: Arrow[];
  showCoordinates?: boolean;
  theme?: BoardTheme;
  /** Renders the board slightly dimmed (e.g. while the answer is revealed). */
  dimmed?: boolean;
}

const FILES = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];

interface Placed {
  key: string;
  square: Square;
  type: PieceType;
  color: Color;
}

/** Stable ids per piece so React can animate a piece between squares. */
function placePieces(fen: string, previous: Placed[]): Placed[] {
  const pieces = piecesFromFen(fen);
  const used = new Set<string>();
  const out: Placed[] = [];

  // Reuse a previous id when a piece of the same kind is already on the square.
  for (const p of pieces) {
    const same = previous.find(
      (q) => q.square === p.square && q.type === p.type && q.color === p.color && !used.has(q.key),
    );
    if (same) {
      used.add(same.key);
      out.push({ ...same, square: p.square });
    } else {
      out.push({ key: '', square: p.square, type: p.type, color: p.color });
    }
  }

  // Then match by kind (a moved piece) before minting new ids.
  for (const p of out) {
    if (p.key) continue;
    const moved = previous.find((q) => q.type === p.type && q.color === p.color && !used.has(q.key));
    if (moved) {
      used.add(moved.key);
      p.key = moved.key;
    } else {
      p.key = `${p.color}${p.type}${p.square}${Math.random().toString(36).slice(2, 7)}`;
    }
  }
  return out;
}

export function Board({
  fen,
  orientation,
  onMove,
  interactive = true,
  movableFor,
  lastMove,
  highlights = [],
  arrows = [],
  showCoordinates = true,
  theme = 'slate',
  dimmed = false,
}: BoardProps) {
  const [selected, setSelected] = useState<Square | null>(null);
  const [promotion, setPromotion] = useState<{ from: Square; to: Square } | null>(null);
  const [placed, setPlaced] = useState<Placed[]>(() => placePieces(fen, []));
  const placedRef = useRef(placed);
  const boardRef = useRef<HTMLDivElement>(null);
  const dragRef = useRef<{ square: Square; pointerId: number; moved: boolean } | null>(null);
  const [dragPos, setDragPos] = useState<{ x: number; y: number; square: Square } | null>(null);

  useEffect(() => {
    const next = placePieces(fen, placedRef.current);
    placedRef.current = next;
    setPlaced(next);
    setSelected(null);
    setPromotion(null);
  }, [fen]);

  const moves = useMemo(() => (interactive ? legalMoves(fen) : []), [fen, interactive]);
  const status = useMemo(() => positionStatus(fen), [fen]);
  const turn: Color = fen.split(' ')[1] === 'b' ? 'b' : 'w';
  const allowedSide = movableFor === 'both' ? null : (movableFor ?? turn);

  const targets = useMemo(() => {
    if (!selected) return new Map<Square, LegalMove[]>();
    const map = new Map<Square, LegalMove[]>();
    for (const m of moves) {
      if (m.from !== selected) continue;
      const list = map.get(m.to) ?? [];
      list.push(m);
      map.set(m.to, list);
    }
    return map;
  }, [moves, selected]);

  const canPickUp = useCallback(
    (square: Square) => {
      if (!interactive) return false;
      const piece = placedRef.current.find((p) => p.square === square);
      if (!piece) return false;
      if (allowedSide && piece.color !== allowedSide) return false;
      return moves.some((m) => m.from === square);
    },
    [allowedSide, interactive, moves],
  );

  const play = useCallback(
    (from: Square, to: Square) => {
      const options = moves.filter((m) => m.from === from && m.to === to);
      if (!options.length) return false;
      if (options.length > 1 && options[0].promotion) {
        setPromotion({ from, to });
        return true;
      }
      setSelected(null);
      onMove?.(options[0]);
      return true;
    },
    [moves, onMove],
  );

  const squareFromPoint = useCallback(
    (clientX: number, clientY: number): Square | null => {
      const rect = boardRef.current?.getBoundingClientRect();
      if (!rect) return null;
      const size = rect.width / 8;
      let col = Math.floor((clientX - rect.left) / size);
      let row = Math.floor((clientY - rect.top) / size);
      if (col < 0 || col > 7 || row < 0 || row > 7) return null;
      const file = orientation === 'w' ? col : 7 - col;
      const rank = orientation === 'w' ? 7 - row : row;
      return coordsToSquare(file, rank);
    },
    [orientation],
  );

  const handlePointerDown = (e: React.PointerEvent, square: Square) => {
    if (!interactive) return;
    if (selected && targets.has(square)) {
      play(selected, square);
      return;
    }
    if (!canPickUp(square)) {
      setSelected(null);
      return;
    }
    setSelected(square);
    dragRef.current = { square, pointerId: e.pointerId, moved: false };
    (e.currentTarget as HTMLElement).setPointerCapture?.(e.pointerId);
  };

  const handlePointerMove = (e: React.PointerEvent) => {
    const drag = dragRef.current;
    if (!drag || drag.pointerId !== e.pointerId) return;
    drag.moved = true;
    setDragPos({ x: e.clientX, y: e.clientY, square: drag.square });
  };

  const handlePointerUp = (e: React.PointerEvent) => {
    const drag = dragRef.current;
    dragRef.current = null;
    setDragPos(null);
    if (!drag || drag.pointerId !== e.pointerId) return;
    if (!drag.moved) return; // treated as a tap: selection stays
    const target = squareFromPoint(e.clientX, e.clientY);
    if (target && target !== drag.square) {
      const ok = play(drag.square, target);
      if (!ok) setSelected(null);
    }
  };

  const checkSquare = status.check ? kingSquare(fen, turn) : null;
  const size = 1 / 8;

  const styleFor = (square: Square): React.CSSProperties => {
    const { file, rank } = squareToCoords(square);
    const col = orientation === 'w' ? file : 7 - file;
    const row = orientation === 'w' ? 7 - rank : rank;
    return {
      left: `${col * 12.5}%`,
      top: `${row * 12.5}%`,
      width: `${size * 100}%`,
      height: `${size * 100}%`,
    };
  };

  const squares: Square[] = [];
  for (let row = 0; row < 8; row += 1) {
    for (let col = 0; col < 8; col += 1) {
      const file = orientation === 'w' ? col : 7 - col;
      const rank = orientation === 'w' ? 7 - row : row;
      squares.push(coordsToSquare(file, rank));
    }
  }

  const highlightMap = new Map(highlights.map((h) => [h.square, h.kind]));
  const dragging = dragPos?.square ?? null;
  const dragRect = boardRef.current?.getBoundingClientRect();

  return (
    <div className={`board-wrap${dimmed ? ' dimmed' : ''}`}>
      <div
        className={`board theme-${theme}`}
        ref={boardRef}
        onPointerMove={handlePointerMove}
        onPointerUp={handlePointerUp}
        onPointerCancel={handlePointerUp}
      >
        {squares.map((square) => {
          const { file, rank } = squareToCoords(square);
          const light = (file + rank) % 2 === 1;
          const hl = highlightMap.get(square);
          const classes = [
            'sq',
            light ? 'light' : 'dark',
            lastMove && (lastMove.from === square || lastMove.to === square) ? 'last' : '',
            selected === square ? 'selected' : '',
            checkSquare === square ? 'check' : '',
            hl ? `hl-${hl}` : '',
          ]
            .filter(Boolean)
            .join(' ');
          return (
            <div
              key={square}
              className={classes}
              style={styleFor(square)}
              onPointerDown={(e) => handlePointerDown(e, square)}
            >
              {showCoordinates && square[1] === (orientation === 'w' ? '1' : '8') && (
                <span className="coord file">{square[0]}</span>
              )}
              {showCoordinates && square[0] === (orientation === 'w' ? 'a' : 'h') && (
                <span className="coord rank">{square[1]}</span>
              )}
            </div>
          );
        })}

        {placed.map((p) => (
          <div
            key={p.key}
            className={`piece${dragging === p.square ? ' dragging' : ''}`}
            style={styleFor(p.square)}
          >
            <Piece type={p.type} color={p.color} />
          </div>
        ))}

        {[...targets.keys()].map((square) => {
          const isCapture = placed.some((p) => p.square === square);
          return (
            <div
              key={`t-${square}`}
              className={`target${isCapture ? ' capture' : ''}`}
              style={styleFor(square)}
              onPointerDown={(e) => handlePointerDown(e, square)}
            >
              <i />
            </div>
          );
        })}

        {arrows.length > 0 && (
          <svg className="arrows" viewBox="0 0 8 8">
            <defs>
              <marker id="ah" markerWidth="3" markerHeight="3" refX="1.6" refY="1.5" orient="auto">
                <path d="M0,0 L3,1.5 L0,3 z" fill="currentColor" />
              </marker>
            </defs>
            {arrows.map((a, i) => {
              const f = squareToCoords(a.from);
              const t = squareToCoords(a.to);
              const fx = (orientation === 'w' ? f.file : 7 - f.file) + 0.5;
              const fy = (orientation === 'w' ? 7 - f.rank : f.rank) + 0.5;
              const tx = (orientation === 'w' ? t.file : 7 - t.file) + 0.5;
              const ty = (orientation === 'w' ? 7 - t.rank : t.rank) + 0.5;
              return (
                <line
                  key={i}
                  x1={fx}
                  y1={fy}
                  x2={tx}
                  y2={ty}
                  stroke={a.color ?? 'var(--accent)'}
                  color={a.color ?? 'var(--accent)'}
                  strokeWidth={0.13}
                  strokeLinecap="round"
                  markerEnd="url(#ah)"
                  opacity={0.85}
                />
              );
            })}
          </svg>
        )}
      </div>

      {dragPos && dragRect && (
        <div
          className="drag-layer"
          style={{
            left: dragPos.x - dragRect.width / 16,
            top: dragPos.y - dragRect.width / 16 - dragRect.width / 22,
            width: dragRect.width / 8,
            height: dragRect.width / 8,
          }}
        >
          {(() => {
            const p = placed.find((q) => q.square === dragPos.square);
            return p ? <Piece type={p.type} color={p.color} /> : null;
          })()}
        </div>
      )}

      {promotion && (
        <div className="promo-backdrop" onPointerDown={() => setPromotion(null)}>
          <div className="promo" onPointerDown={(e) => e.stopPropagation()}>
            <div className="promo-title">Promote to</div>
            <div className="promo-row">
              {(['q', 'r', 'b', 'n'] as PieceType[]).map((t) => (
                <button
                  key={t}
                  className="promo-btn"
                  onClick={() => {
                    const move = moves.find(
                      (m) => m.from === promotion.from && m.to === promotion.to && m.promotion === t,
                    );
                    setPromotion(null);
                    setSelected(null);
                    if (move) onMove?.(move);
                  }}
                >
                  <Piece type={t} color={turn} />
                </button>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export { FILES };
