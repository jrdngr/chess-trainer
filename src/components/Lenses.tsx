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
}): { bar: ReactNode; marks: LensMarks | null; legend: ReactNode } {
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

  return { bar, marks, legend: active ? <LensLegend kind={active} /> : null };
}

type Swatch =
  | { kind: 'tint'; rgb: string }
  | { kind: 'tag'; tone: 'good' | 'bad' }
  | { kind: 'dot' }
  | { kind: 'ring'; color: string }
  | { kind: 'star'; color: string }
  | { kind: 'arrow'; color: string; faint?: boolean }
  | { kind: 'pip'; color: string }
  | { kind: 'zone' }
  | { kind: 'empty' }
  | { kind: 'line' }
  | { kind: 'shield'; color: string };

const BLUE = 'rgb(59, 130, 246)';
const RED = 'rgb(239, 68, 68)';
const ORANGE = 'rgb(249, 115, 22)';
const GREEN = 'rgb(34, 197, 94)';
const AMBER = 'rgb(245, 158, 11)';

/** What each mark of a lens means, in the space under the board while it is held. */
const LEGENDS: Record<LensKind, { swatch: Swatch; label: string }[]> = {
  pawns: [
    { swatch: { kind: 'tag', tone: 'bad' }, label: 'Weak pawn' },
    { swatch: { kind: 'tag', tone: 'good' }, label: 'Passed pawn' },
    { swatch: { kind: 'dot' }, label: 'Hole' },
    { swatch: { kind: 'arrow', color: BLUE }, label: 'Your best break' },
    { swatch: { kind: 'arrow', color: RED }, label: 'Their best break' },
  ],
  pieces: [
    { swatch: { kind: 'tint', rgb: '34, 197, 94' }, label: 'Active' },
    { swatch: { kind: 'tint', rgb: '245, 158, 11' }, label: 'Passive' },
    { swatch: { kind: 'tint', rgb: '239, 68, 68' }, label: 'Doing nothing' },
    { swatch: { kind: 'ring', color: RED }, label: 'Worst piece' },
    { swatch: { kind: 'star', color: 'rgb(96, 165, 250)' }, label: 'Your outpost' },
    { swatch: { kind: 'star', color: 'rgb(248, 113, 113)' }, label: 'Their outpost' },
    { swatch: { kind: 'arrow', color: 'rgba(96, 165, 250, 0.55)', faint: true }, label: 'Knight route' },
  ],
  space: [
    { swatch: { kind: 'tint', rgb: '59, 130, 246' }, label: 'Yours' },
    { swatch: { kind: 'tint', rgb: '239, 68, 68' }, label: 'Theirs' },
    { swatch: { kind: 'tint', rgb: '168, 85, 247' }, label: 'Contested' },
    { swatch: { kind: 'tint', rgb: '125, 105, 250' }, label: 'Contested, yours wins it' },
    { swatch: { kind: 'tint', rgb: '205, 80, 190' }, label: 'Contested, theirs wins it' },
  ],
  kings: [
    { swatch: { kind: 'zone' }, label: 'King zone' },
    { swatch: { kind: 'pip', color: 'rgb(248, 113, 113)' }, label: 'Attacker' },
    { swatch: { kind: 'pip', color: 'rgb(96, 165, 250)' }, label: 'Defender' },
    { swatch: { kind: 'empty' }, label: 'Missing shield pawn' },
    { swatch: { kind: 'line' }, label: 'Open line to the king' },
    { swatch: { kind: 'shield', color: GREEN }, label: 'Safe' },
    { swatch: { kind: 'shield', color: AMBER }, label: 'Exposed' },
    { swatch: { kind: 'shield', color: RED }, label: 'Under attack' },
  ],
  threats: [
    { swatch: { kind: 'ring', color: RED }, label: 'Hanging' },
    { swatch: { kind: 'ring', color: ORANGE }, label: 'Hit by a cheaper piece' },
    { swatch: { kind: 'arrow', color: RED }, label: 'New threat from their last move' },
  ],
};

function SwatchIcon({ swatch }: { swatch: Swatch }) {
  switch (swatch.kind) {
    case 'tint':
      return <i className="sw sw-tint" style={{ background: `rgba(${swatch.rgb}, 0.6)` }} />;
    case 'tag':
      return <i className={`sw sw-tag ${swatch.tone}`} />;
    case 'dot':
      return <i className="sw sw-dot" />;
    case 'ring':
      return <i className="sw sw-ring" style={{ color: swatch.color }} />;
    case 'star':
      return (
        <i className="sw sw-star" style={{ color: swatch.color }}>
          ★
        </i>
      );
    case 'pip':
      return <i className="sw sw-pip" style={{ background: swatch.color }} />;
    case 'zone':
      return <i className="sw sw-zone" />;
    case 'empty':
      return <i className="sw sw-empty" />;
    case 'line':
      return (
        <svg className="sw" viewBox="0 0 20 20" aria-hidden>
          <line x1="2" y1="10" x2="18" y2="10" stroke="rgba(239, 68, 68, 0.8)" strokeWidth="2" strokeDasharray="4 3" />
        </svg>
      );
    case 'arrow':
      return (
        <svg className="sw" viewBox="0 0 20 20" aria-hidden>
          <line x1="2" y1="10" x2="13" y2="10" stroke={swatch.color} strokeWidth={swatch.faint ? 2 : 3} strokeLinecap="round" />
          <path d="M12 5 L19 10 L12 15 z" fill={swatch.color} />
        </svg>
      );
    case 'shield':
      return (
        <svg className="sw" viewBox="0 0 24 24" aria-hidden>
          <path d="M12 2 4 5v6c0 5 3.4 9.4 8 11 4.6-1.6 8-6 8-11V5l-8-3z" fill={swatch.color} />
        </svg>
      );
  }
}

/** The key to a lens: one row per kind of mark it draws. */
export function LensLegend({ kind }: { kind: LensKind }) {
  return (
    <div className="lens-legend">
      {LEGENDS[kind].map(({ swatch, label }) => (
        <div key={label} className="lens-legend-row">
          <SwatchIcon swatch={swatch} />
          <span>{label}</span>
        </div>
      ))}
    </div>
  );
}
