import { useMemo, useState, type PointerEvent } from 'react';
import { niceTicks } from '../model/stats';

/**
 * Charts, drawn inline as SVG so nothing is fetched at runtime.
 *
 * One series, one hue, thin marks, recessive grid. A line chart carries a
 * crosshair the reader drags along it, since a value on every point would
 * be noise and a value on none would leave the middle of the chart mute.
 */
export interface Point {
  at: number;
  value: number;
}

const W = 320;
const PAD = { top: 10, right: 12, bottom: 22, left: 34 };

function dateLabel(at: number, span: number): string {
  const date = new Date(at);
  if (span <= 14) return date.toLocaleDateString(undefined, { weekday: 'narrow' });
  return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

export function LineChart({
  points,
  color,
  height = 150,
  formatValue = (v) => String(Math.round(v)),
  max,
  percent,
}: {
  points: Point[];
  color: string;
  height?: number;
  formatValue?: (value: number) => string;
  /** Fix the top of the scale; otherwise the data decides. */
  max?: number;
  /** Ticks as percentages. */
  percent?: boolean;
}) {
  const [hover, setHover] = useState<number | null>(null);
  const plotW = W - PAD.left - PAD.right;
  const plotH = height - PAD.top - PAD.bottom;

  const scale = useMemo(() => {
    const top = max ?? Math.max(1, ...points.map((p) => p.value));
    const ticks = max !== undefined ? [0, top / 2, top] : niceTicks(top);
    const ceiling = ticks[ticks.length - 1] || 1;
    const first = points[0]?.at ?? 0;
    const last = points[points.length - 1]?.at ?? first + 1;
    const span = Math.max(1, last - first);
    return {
      x: (at: number) => PAD.left + ((at - first) / span) * plotW,
      y: (value: number) => PAD.top + plotH - (value / ceiling) * plotH,
      ticks,
      days: Math.round(span / 86_400_000) + 1,
    };
  }, [points, max, plotW, plotH]);

  if (points.length === 0) {
    return <div className="chart-empty">Nothing yet</div>;
  }

  const path = points.map((p, i) => `${i === 0 ? 'M' : 'L'}${scale.x(p.at).toFixed(1)},${scale.y(p.value).toFixed(1)}`).join(' ');
  const area = `${path} L${scale.x(points[points.length - 1].at).toFixed(1)},${(PAD.top + plotH).toFixed(1)} L${scale.x(points[0].at).toFixed(1)},${(PAD.top + plotH).toFixed(1)} Z`;
  const last = points[points.length - 1];
  const at = hover === null ? null : points[hover];

  const onPointer = (e: PointerEvent<SVGSVGElement>) => {
    const box = e.currentTarget.getBoundingClientRect();
    const x = ((e.clientX - box.left) / box.width) * W;
    let best = 0;
    let dist = Infinity;
    points.forEach((p, i) => {
      const d = Math.abs(scale.x(p.at) - x);
      if (d < dist) {
        dist = d;
        best = i;
      }
    });
    setHover(best);
  };

  const label = (value: number) => (percent ? `${Math.round(value * 100)}%` : formatValue(value));

  return (
    <div className="chart">
      <svg
        viewBox={`0 0 ${W} ${height}`}
        className="chart-svg"
        onPointerMove={onPointer}
        onPointerDown={onPointer}
        onPointerLeave={() => setHover(null)}
      >
        {scale.ticks.map((tick) => (
          <g key={tick}>
            <line x1={PAD.left} x2={W - PAD.right} y1={scale.y(tick)} y2={scale.y(tick)} className="grid" />
            <text x={PAD.left - 6} y={scale.y(tick) + 3.5} className="tick" textAnchor="end">
              {label(tick)}
            </text>
          </g>
        ))}
        <text x={PAD.left} y={height - 6} className="tick">
          {dateLabel(points[0].at, scale.days)}
        </text>
        <text x={W - PAD.right} y={height - 6} className="tick" textAnchor="end">
          {dateLabel(last.at, scale.days)}
        </text>
        <path d={area} fill={color} opacity={0.1} />
        <path d={path} fill="none" stroke={color} strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" />
        <circle cx={scale.x(last.at)} cy={scale.y(last.value)} r={4} fill={color} className="marker" />
        {at && (
          <g>
            <line x1={scale.x(at.at)} x2={scale.x(at.at)} y1={PAD.top} y2={PAD.top + plotH} className="crosshair" />
            <circle cx={scale.x(at.at)} cy={scale.y(at.value)} r={5} fill={color} className="marker" />
          </g>
        )}
      </svg>
      <div className="chart-readout">
        {at ? (
          <>
            <span className="muted">{new Date(at.at).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })}</span>
            <b className="num">{label(at.value)}</b>
          </>
        ) : (
          <>
            <span className="muted">Now</span>
            <b className="num">{label(last.value)}</b>
          </>
        )}
      </div>
    </div>
  );
}

/** Horizontal bars for a few named things, one hue, value at the tip. */
export function BarList({
  rows,
  color,
  formatValue = (v) => String(v),
}: {
  rows: { label: string; value: number; highlight?: boolean }[];
  color: string;
  formatValue?: (value: number) => string;
}) {
  const max = Math.max(1, ...rows.map((row) => row.value));
  return (
    <div className="bar-list">
      {rows.map((row) => (
        <div className={`bar-row${row.highlight ? ' highlight' : ''}`} key={row.label}>
          <span className="lbl truncate">{row.label}</span>
          <span className="track">
            <i style={{ width: `${(row.value / max) * 100}%`, background: color }} />
          </span>
          <span className="val num">{formatValue(row.value)}</span>
        </div>
      ))}
    </div>
  );
}
