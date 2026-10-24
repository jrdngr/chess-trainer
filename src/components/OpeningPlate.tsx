import type { Color } from '../chess/core';
import type { PrepSpan } from '../model/autopilot';
import { MiniBoard } from './Selection';

/** The most segments the track is cut into; a longer prep is shown to scale. */
const MAX_SEGMENTS = 16;

/**
 * How far into your prep a run is, as a row of segments: lit up to where it
 * stands, the one it is on bright. Past the prep, the plies played in the
 * book follow in their own color. Nothing when there is nothing to measure.
 */
export function PrepSegments({ span, className }: { span: PrepSpan | null; className?: string }) {
  const book = span?.book ?? 0;
  if (!span || span.total + book <= 0) return null;
  const all = span.total + book;
  const count = Math.min(all, MAX_SEGMENTS);
  const prepCount = book ? Math.round((span.total / all) * count) : count;
  const lit = book ? prepCount : Math.round((Math.min(span.played, span.total) / span.total) * count);
  const label = book
    ? `${span.total} prep moves and ${book} in the book`
    : span.played === 0
      ? 'From the first move'
      : `${Math.min(span.played, span.total)} of ${span.total} prep moves in`;
  return (
    <span className={`prep-segs${className ? ` ${className}` : ''}`} role="img" aria-label={label}>
      {Array.from({ length: count }, (_, i) => {
        const state =
          i >= prepCount ? (i === count - 1 ? 'book here' : 'book') : i < lit ? 'past' : i === lit ? 'here' : '';
        // A segment holding any ply past where the prep leaves the book is drawn outlined.
        const ext = i < prepCount && span.ext !== undefined && ((i + 1) * span.total) / prepCount > span.ext;
        return <i key={i} className={`${state}${ext ? ' ext' : ''}`.trim() || undefined} />;
      })}
    </span>
  );
}

/** The side you play, as a small square. */
export function SideSquare({ color }: { color: Color }) {
  return <span className={`side-square ${color}`} aria-label={color === 'w' ? 'White' : 'Black'} />;
}

/** An opening's position behind its name, the move that reached it lit. */
export function PlateBoard({ sans, color, size }: { sans: string[]; color: Color; size: number }) {
  return (
    <span className="plate-board" aria-hidden>
      <MiniBoard sans={sans} orientation={color} size={size} lastMove />
    </span>
  );
}

/**
 * Autopilot's round as its intro announces it: the opening's position faded
 * in behind its name, and along the bottom edge how far into your prep the
 * run starts.
 */
export function IntroPlate({ name, sans, color, span }: { name: string; sans: string[]; color: Color; span: PrepSpan | null }) {
  return (
    <div className="intro-plate">
      <PlateBoard sans={sans} color={color} size={300} />
      <span className="ip-name">
        <SideSquare color={color} />
        <span className={`ip-text${name.length > 20 ? ' long' : ''}`}>{name}</span>
      </span>
      <PrepSegments span={span} className="edge" />
    </div>
  );
}
