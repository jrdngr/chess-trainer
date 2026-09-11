import type { Color, PieceType } from '../chess/core';

/**
 * Piece shapes drawn as SVG paths on a 45×45 grid, so they stay crisp at any
 * board size and need no image requests (which the artifact sandbox blocks).
 */
const SHAPES: Record<PieceType, string> = {
  p: 'M22.5 10.5a4.2 4.2 0 0 0-2.55 7.54c-2.35 1.18-3.95 3.6-3.95 6.4 0 1.98.8 3.78 2.1 5.08-3.6 1.5-6.1 5.9-6.1 11.1h21.9c0-5.2-2.5-9.6-6.1-11.1a7.13 7.13 0 0 0 2.1-5.08c0-2.8-1.6-5.22-3.95-6.4A4.2 4.2 0 0 0 22.5 10.5z',
  r: 'M11.5 39.5h22v-3.4h-22zM13.6 36.1l1-15.3h16.8l1 15.3zM10.6 20.8h23.8v-5.4h-4.1v2.4h-3.9v-2.4h-4.8v2.4h-3.9v-2.4h-7.1z',
  n: 'M22 10.5c9.2 1 15.1 8.2 14.6 29H15.2c0-9 10-7 8-21zM24 18.3c-.4 3-6.3 7.4-8.8 9-3 2-2.8 4.3-5 4-1-1 1.4-3.1 0-3-1 0 .2 1.2-1 2-1 0-4-1-4-6 0-2 6-12 6-12s1.9-1.9 2-3.5c-.7-1-.5-2-.5-3 1-1 3 2.5 3 2.5h2s.8-2 2.5-3c1 0 1 3 1 3z',
  b: 'M22.5 7.6a2.6 2.6 0 1 1 0 5.2 2.6 2.6 0 0 1 0-5.2zM22.5 12.6c-4.9 2.8-7.7 7.7-7.7 12.1 0 3.2 1.4 5.4 3 6.7h9.4c1.6-1.3 3-3.5 3-6.7 0-4.4-2.8-9.3-7.7-12.1zM12.7 33.5h19.6c1.1 0 1.8 1 1.8 2.1s-.7 2.1-1.8 2.1H12.7c-1.1 0-1.8-1-1.8-2.1s.7-2.1 1.8-2.1z',
  q: 'M8.2 14.6a2.3 2.3 0 1 1 0-4.6 2.3 2.3 0 0 1 0 4.6zM15.3 11.8a2.3 2.3 0 1 1 0-4.6 2.3 2.3 0 0 1 0 4.6zM22.5 10.6a2.4 2.4 0 1 1 0-4.8 2.4 2.4 0 0 1 0 4.8zM29.7 11.8a2.3 2.3 0 1 1 0-4.6 2.3 2.3 0 0 1 0 4.6zM36.8 14.6a2.3 2.3 0 1 1 0-4.6 2.3 2.3 0 0 1 0 4.6zM9.4 16.2l3.6 14.4h19l3.6-14.4-5.4 7.2-2.9-10.8-3.6 10.8-1.2-9.6-1.2 9.6-3.6-10.8-2.9 10.8zM12.5 32.2h20v3.6h-20zM11.2 37.1h22.6v2.6H11.2z',
  k: 'M22.5 13.5c-3.1 0-5.4 2.1-5.4 4.8 0 1.7.8 3 1.9 4-2.9-1.4-6.6-.7-8.4 2-1.9 2.9-.7 6.5 1.6 8.5l10.3 8.4 10.3-8.4c2.3-2 3.5-5.6 1.6-8.5-1.8-2.7-5.5-3.4-8.4-2 1.1-1 1.9-2.3 1.9-4 0-2.7-2.3-4.8-5.4-4.8z',
};

/** The king's cross is stroked rather than filled, so it needs its own pass. */
const KING_CROSS = 'M22.5 6.2v7M19.2 9.3h6.6';

export interface PieceProps {
  type: PieceType;
  color: Color;
  size?: number | string;
}

export function Piece({ type, color, size = '100%' }: PieceProps) {
  const white = color === 'w';
  const fill = white ? '#f6f8fb' : '#20262f';
  const stroke = white ? '#2b3441' : '#05080c';
  return (
    <svg
      viewBox="0 0 45 45"
      width={size}
      height={size}
      aria-hidden
      style={{ display: 'block', filter: 'drop-shadow(0 1px 1.5px rgba(0,0,0,0.42))' }}
    >
      <g
        fill={fill}
        stroke={stroke}
        strokeWidth={1.5}
        strokeLinejoin="round"
        strokeLinecap="round"
      >
        <path d={SHAPES[type]} />
        {type === 'k' && <path d={KING_CROSS} strokeWidth={2.2} fill="none" />}
        {type === 'b' && (
          <path d="M22.5 19v7M19.4 22.3h6.2" strokeWidth={1.4} fill="none" />
        )}
        {type === 'n' && white && (
          <circle cx="14.3" cy="20.2" r="1.1" fill={stroke} stroke="none" />
        )}
        {type === 'n' && !white && (
          <circle cx="14.3" cy="20.2" r="1.1" fill="#8d97a5" stroke="none" />
        )}
      </g>
    </svg>
  );
}

export const PIECE_NAMES: Record<PieceType, string> = {
  p: 'Pawn',
  n: 'Knight',
  b: 'Bishop',
  r: 'Rook',
  q: 'Queen',
  k: 'King',
};
