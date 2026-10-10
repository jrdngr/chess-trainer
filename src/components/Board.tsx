import { useCallback, useEffect, useMemo, useRef, useState, type CSSProperties, type ReactNode } from 'react';
import {
  coordsToSquare,
  kingSquare,
  legalMoves,
  material,
  piecesFromFen,
  positionStatus,
  squareToCoords,
  type Color,
  type LegalMove,
  type PieceType,
  type Square,
} from '../chess/core';
import { Piece } from './Pieces';
import type { LensMarks, TintColor } from '../model/boardHints';
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
  /** Show what has been taken, and who is ahead, above the board. */
  captured?: boolean;
  /** Drawn on top of the board, the same size as it, e.g. a verdict flashed over the position. */
  overlay?: ReactNode;
  /**
   * Only these moves, in SAN, may be played. Everything else stops being
   * pickable — the pieces do not lift and no targets are drawn — which is what
   * makes a board that offers a choice of a few moves rather than the position.
   */
  allowed?: string[];
  /** A tint around the board's edge, e.g. Survival's hint of who is better. */
  glow?: { tone: 'green' | 'yellow' | 'red'; strength: number } | null;
  /** What a held lens draws over the position — see `model/boardHints.ts`. */
  marks?: LensMarks | null;
}

const TINT_RGB: Record<TintColor, string> = {
  blue: '59, 130, 246',
  red: '239, 68, 68',
  purple: '168, 85, 247',
  'purple-blue': '125, 105, 250',
  'purple-red': '205, 80, 190',
  green: '34, 197, 94',
  amber: '245, 158, 11',
};
const TINT_ALPHA = { 1: 0.3, 2: 0.44, 3: 0.58 } as const;

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
  captured = false,
  overlay,
  allowed,
  glow = null,
  marks = null,
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

  const allowedKey = allowed?.join(' ');
  const moves = useMemo(() => {
    if (!interactive) return [];
    const legal = legalMoves(fen);
    if (allowedKey === undefined) return legal;
    const only = new Set(allowedKey ? allowedKey.split(' ') : []);
    return legal.filter((move) => only.has(move.san));
    // The list is compared by its contents, so a caller need not memoise it.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fen, interactive, allowedKey]);
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
    <>
      {captured &&
        (marks?.caption ? (
          <div className="captured lens-caption-row">{marks.caption}</div>
        ) : (
          <Captured fen={fen} orientation={orientation} />
        ))}
      <div
        className={`board-wrap${dimmed ? ' dimmed' : ''}${glow ? ` glow glow-${glow.tone}` : ''}`}
        style={glow ? ({ '--glow-k': 0.2 + 0.8 * glow.strength } as CSSProperties) : undefined}
      >
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

          {marks && <LensUnder marks={marks} styleFor={styleFor} />}

          {placed.map((p) => (
            <div
              key={p.key}
              className={`piece${dragging === p.square ? ' dragging' : ''}${marks?.ghost && p.type !== 'p' ? ' ghost' : ''}`}
              style={styleFor(p.square)}
            >
              <Piece type={p.type} color={p.color} />
            </div>
          ))}

          {marks && <LensOver marks={marks} styleFor={styleFor} orientation={orientation} />}

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
              {(() => {
                const drawn = arrows.map((a) => {
                  const f = squareToCoords(a.from);
                  const t = squareToCoords(a.to);
                  const from = { x: (orientation === 'w' ? f.file : 7 - f.file) + 0.5, y: (orientation === 'w' ? 7 - f.rank : f.rank) + 0.5 };
                  const to = { x: (orientation === 'w' ? t.file : 7 - t.file) + 0.5, y: (orientation === 'w' ? 7 - t.rank : t.rank) + 0.5 };
                  return { color: a.color ?? 'var(--accent)', ...arrowShape(from, to, 0.13) };
                });
                // Every shaft first, then every head: a head is never hidden under another arrow's tail.
                return (
                  <>
                    {drawn.map((d, i) => (
                      <line key={`s${i}`} {...d.shaft} stroke={d.color} strokeWidth={0.13} strokeLinecap="round" opacity={0.85} />
                    ))}
                    {drawn.map((d, i) => (
                      <polygon key={`h${i}`} points={d.head} fill={d.color} opacity={0.85} />
                    ))}
                  </>
                );
              })()}
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

        {marks?.caption && !captured && (
          <div className="lens-caption">
            <span>{marks.caption}</span>
          </div>
        )}

        {overlay}
      </div>
    </>
  );
}

type StyleFor = (square: Square) => CSSProperties;

/** A lens's marks that sit under the pieces: tints, a king's zone, holes, missing shield pawns. */
function LensUnder({ marks, styleFor }: { marks: LensMarks; styleFor: StyleFor }) {
  return (
    <>
      {marks.tints?.map((t) => (
        <div
          key={`tint-${t.square}`}
          className="lens-tint"
          style={{ ...styleFor(t.square), background: `rgba(${TINT_RGB[t.color]}, ${TINT_ALPHA[t.strength]})` }}
        />
      ))}
      {marks.zone?.map((square) => (
        <div key={`zone-${square}`} className="lens-zone" style={styleFor(square)} />
      ))}
      {marks.dots?.map((square) => (
        <div key={`dot-${square}`} className="lens-dot" style={styleFor(square)}>
          <i />
        </div>
      ))}
      {marks.emptyPawns?.map((square) => (
        <div key={`empty-${square}`} className="lens-empty" style={styleFor(square)}>
          <i />
        </div>
      ))}
    </>
  );
}

/** A lens's marks over the pieces: rings, tags, stars, pips, shields, lines and arrows. */
function LensOver({ marks, styleFor, orientation }: { marks: LensMarks; styleFor: StyleFor; orientation: Color }) {
  const point = (square: Square) => {
    const { file, rank } = squareToCoords(square);
    return { x: (orientation === 'w' ? file : 7 - file) + 0.5, y: (orientation === 'w' ? 7 - rank : rank) + 0.5 };
  };
  const hasSvg = !!marks.lines?.length || !!marks.arrows?.length;
  return (
    <>
      {marks.rings?.map((r) => (
        <div key={`ring-${r.square}`} className={`lens-ring ${r.tone}`} style={styleFor(r.square)} />
      ))}
      {marks.tags?.map((t) => (
        <div key={`tag-${t.square}`} className={`lens-tag ${t.tone}`} style={styleFor(t.square)}>
          <i />
        </div>
      ))}
      {marks.stars?.map((s) => (
        <div key={`star-${s.square}`} className={`lens-star ${s.side}`} style={styleFor(s.square)}>
          <span>★</span>
        </div>
      ))}
      {marks.pips?.map((p) => (
        <div key={`pip-${p.square}`} className="lens-pips" style={styleFor(p.square)}>
          <span>
            {Array.from({ length: Math.min(p.attackers, 4) }, (_, i) => (
              <i key={`a${i}`} className="atk" />
            ))}
            {Array.from({ length: Math.min(p.defenders, 4) }, (_, i) => (
              <i key={`d${i}`} className="def" />
            ))}
          </span>
        </div>
      ))}
      {marks.shields?.map((s) => (
        <div key={`shield-${s.square}`} className={`lens-shield ${s.grade}`} style={styleFor(s.square)}>
          <svg viewBox="0 0 24 24" aria-hidden>
            <path d="M12 2 4 5v6c0 5 3.4 9.4 8 11 4.6-1.6 8-6 8-11V5l-8-3z" />
          </svg>
        </div>
      ))}
      {hasSvg && (
        <svg className="arrows lens-lines" viewBox="0 0 8 8">
          {marks.lines?.map((l, i) => {
            const a = point(l.from);
            const b = point(l.to);
            return <line key={`l${i}`} className="lens-line" x1={a.x} y1={a.y} x2={b.x} y2={b.y} />;
          })}
          {/* Every shaft first, then every head: a head is never hidden under another arrow's tail. */}
          {(() => {
            const drawn = (marks.arrows ?? []).map((l) => ({
              tone: l.tone,
              ...arrowShape(point(l.from), point(l.to), l.tone === 'route' ? 0.09 : 0.13),
            }));
            return (
              <>
                {drawn.map((d, i) => (
                  <line key={`a${i}`} className={`lens-arrow ${d.tone}`} {...d.shaft} />
                ))}
                {drawn.map((d, i) => (
                  <polygon key={`h${i}`} className={`lens-head ${d.tone}`} points={d.head} />
                ))}
              </>
            );
          })()}
        </svg>
      )}
    </>
  );
}

/**
 * An arrow as a shaft and a separate head, so a board can draw all the
 * shafts before any head. The head is three stroke widths long and its tip
 * sits a little past the target square's center; the shaft stops at the
 * head's base (its round cap just reaching it) so a see-through color does
 * not darken where they meet.
 */
export function arrowShape(from: { x: number; y: number }, to: { x: number; y: number }, width: number) {
  const dx = to.x - from.x;
  const dy = to.y - from.y;
  const len = Math.hypot(dx, dy) || 1;
  const ux = dx / len;
  const uy = dy / len;
  const tip = { x: to.x + ux * width * 1.4, y: to.y + uy * width * 1.4 };
  const base = { x: tip.x - ux * width * 3, y: tip.y - uy * width * 3 };
  const half = width * 1.5;
  const head = [
    `${tip.x},${tip.y}`,
    `${base.x - uy * half},${base.y + ux * half}`,
    `${base.x + uy * half},${base.y - ux * half}`,
  ].join(' ');
    const back = width / 2 - 0.01;
  return { shaft: { x1: from.x, y1: from.y, x2: base.x - ux * back, y2: base.y - uy * back }, head };
}

/**
 * What has come off the board, and who is ahead by how much.
 *
 * One row above the board rather than a side each: the pieces you have taken
 * sit next to the pieces they have taken, so the trade is read at a glance on a
 * phone, and the lead is named by colour — "+3 white" — because a minus sign in
 * front of a number leaves you working out whose number it is.
 */
export function Captured({ fen, orientation }: { fen: string; orientation: Color }) {
  const { byWhite, byBlack, lead } = useMemo(() => material(fen), [fen]);
  // Yours first, wherever you are sitting.
  const mine = orientation === 'w' ? byWhite : byBlack;
  const theirs = orientation === 'w' ? byBlack : byWhite;
  const taken = orientation === 'w' ? 'b' : 'w';
  const ahead = lead === 0 ? null : lead > 0 ? 'white' : 'black';

  return (
    <div className="captured">
      <Taken pieces={mine} color={taken} />
      {mine.length > 0 && theirs.length > 0 && <span className="captured-gap" />}
      <Taken pieces={theirs} color={orientation} />
      <span className="grow" />
      {ahead && (
        <span className={`chip ${ahead === 'white' ? 'w' : 'b'}`}>
          +{Math.abs(lead)} {ahead}
        </span>
      )}
    </div>
  );
}

function Taken({ pieces, color }: { pieces: PieceType[]; color: Color }) {
  return (
    <>
      {pieces.map((type, i) => (
        <span className="captured-piece" key={`${type}${i}`}>
          <Piece type={type} color={color} size={18} />
        </span>
      ))}
    </>
  );
}
