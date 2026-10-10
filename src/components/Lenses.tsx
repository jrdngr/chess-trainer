import { useEffect, useMemo, useState, type ReactNode } from 'react';
import type { Color } from '../chess/core';
import { usePawnBreaks } from '../engine/pawnBreaks';
import { LENSES, lensMarks, type LensKind, type LensMarks } from '../model/boardHints';

/**
 * The lens bar under a board: Pawns, Pieces, Space, Kings, Threats. Hold a
 * lens to see it over the position; let go and the board is clean again.
 *
 * Returns the bar to render and the marks to hand the board. The Pawns lens
 * asks its own engine for each side's best pawn break, drawn as an arrow once
 * it arrives.
 */
export function useLens({
  fen,
  me,
  prevFen,
  enabled = true,
}: {
  fen: string;
  /** The side you play: blue is yours, red is theirs. */
  me: Color;
  /** The position before the last move, for what it newly threatens. */
  prevFen?: string | null;
  enabled?: boolean;
}): { bar: ReactNode; marks: LensMarks | null } {
  const [held, setHeld] = useState<LensKind | null>(null);

  // A finger lifted anywhere lets go of the lens, wherever it ended up.
  useEffect(() => {
    if (!held) return;
    const release = () => setHeld(null);
    window.addEventListener('pointerup', release);
    window.addEventListener('pointercancel', release);
    window.addEventListener('blur', release);
    return () => {
      window.removeEventListener('pointerup', release);
      window.removeEventListener('pointercancel', release);
      window.removeEventListener('blur', release);
    };
  }, [held]);

  useEffect(() => {
    if (!enabled) setHeld(null);
  }, [enabled]);

  const active = enabled ? held : null;
  const breaks = usePawnBreaks(fen, active === 'pawns');
  const marks = useMemo(() => {
    if (!active) return null;
    const base = lensMarks(active, fen, me, prevFen);
    if (active !== 'pawns' || !breaks) return base;
    const arrows: NonNullable<LensMarks['arrows']> = [];
    for (const color of ['w', 'b'] as Color[]) {
      const move = breaks[color];
      if (move) arrows.push({ ...move, tone: color === me ? 'mine' : 'theirs' });
    }
    return { ...base, arrows };
  }, [active, fen, me, prevFen, breaks]);

  const bar = (
    <div className="lens-bar" onContextMenu={(e) => e.preventDefault()}>
      {LENSES.map(({ kind, label }) => (
        <button
          key={kind}
          className={active === kind ? 'on' : undefined}
          disabled={!enabled}
          onPointerDown={(e) => {
            e.preventDefault();
            setHeld(kind);
          }}
          onKeyDown={(e) => {
            if (e.key === ' ' || e.key === 'Enter') setHeld(kind);
          }}
          onKeyUp={() => setHeld(null)}
        >
          {label}
        </button>
      ))}
    </div>
  );

  return { bar, marks };
}
