import { useEffect, useRef, useState } from 'react';
import { rankOf } from '../model/scoring';
import { deltaText, fillColor, paintFor, ratingText } from './ScoreBar';
import { haptic } from './ui';
import { useStore } from '../store/useStore';

/** The rating a round moved, as the end screen tells it: where it stood and where it stands. */
export interface RatingMoment {
  id: string;
  name: string;
  before: number;
  after: number;
}

/** Before the bar starts to move, so the card is seen first. */
const LEAD_MS = 700;
/** A gain or a drop within a tier. */
const GROW_MS = 900;
/** Filling up to the rung before a promotion, the flash on crossing it, and the regrowth. */
const TOP_MS = 650;
const FLASH_MS = 760;
const REGROW_MS = 700;
/** How long the settled card stays over the board before it moves down. */
const HOLD_MS = 1100;

/** Sparks off the bar's end on a promotion: angle, distance, and how long each flies. */
const SPARKS = Array.from({ length: 16 }, (_, i) => ({
  a: `${Math.round(i * 22.5 + (i % 2 ? 9 : -5))}deg`,
  d: `${40 + ((i * 17) % 38)}px`,
  t: `${(0.55 + ((i * 7) % 5) / 10).toFixed(2)}s`,
}));

interface View {
  /** The rating the tier names and the paint follow. */
  rating: number;
  /** The number shown, counting toward the new rating. */
  shown: number;
  /** How full the bar is, 0..1. */
  width: number;
  /** How long the width takes to get where it is going; 0 snaps. */
  speed: number;
  /** A tier crossed: the bar flashes in this color. */
  flash: string | null;
  /** The stretch a change within a tier added or took away, glowing. */
  stretch: { from: number; to: number; gain: boolean } | null;
  /** The change has started: the delta shows. */
  moved: boolean;
  /** A tier was gained: the card rings, sparks fly, the new tier stamps in. */
  promoted: boolean;
}

function restingAt(rating: number): View {
  return {
    rating,
    shown: rating,
    width: rankOf(rating).progress,
    speed: 0,
    flash: null,
    stretch: null,
    moved: false,
    promoted: false,
  };
}

/**
 * A round's rating change, played on its bar: a gain grows the bar with the
 * stretch it added glowing; a promotion fills it to the end, flashes it in the
 * new tier's color, throws sparks and regrows it from the left with what is
 * left over; a drop flashes red and shrinks. The number counts along. Calls
 * `onDone` once it has settled and been seen.
 */
function usePlayback(moment: RatingMoment, onDone: () => void): View {
  const haptics = useStore((s) => s.settings.hapticFeedback);
  const [view, setView] = useState(() => restingAt(moment.before));
  const done = useRef(onDone);
  done.current = onDone;

  useEffect(() => {
    const { before, after } = moment;
    const timers: number[] = [];
    let frame = 0;
    const at = (ms: number, step: () => void) => timers.push(window.setTimeout(step, ms));
    const count = (start: number, ms: number, from: number, to: number) =>
      at(start, () => {
        const t0 = performance.now();
        const tick = () => {
          const t = Math.min(1, (performance.now() - t0) / ms);
          setView((v) => ({ ...v, shown: from + (to - from) * (1 - Math.pow(1 - t, 3)) }));
          if (t < 1) frame = requestAnimationFrame(tick);
        };
        tick();
      });
    const was = rankOf(before);
    const now = rankOf(after);
    const settle = { rating: after, width: now.progress, speed: REGROW_MS };
    let end: number;
    if (now.reached === was.reached) {
      at(LEAD_MS, () =>
        setView((v) => ({
          ...v,
          width: now.progress,
          speed: GROW_MS,
          moved: true,
          stretch: { from: was.progress, to: now.progress, gain: after > before },
        })),
      );
      count(LEAD_MS, GROW_MS, before, after);
      end = LEAD_MS + GROW_MS + 300;
    } else if (now.reached > was.reached) {
      const color = fillColor(after);
      at(LEAD_MS, () => setView((v) => ({ ...v, width: 1, speed: TOP_MS, moved: true })));
      count(LEAD_MS, TOP_MS, before, now.floor);
      at(LEAD_MS + TOP_MS, () => {
        if (haptics) haptic([20, 40, 20, 40, 60]);
        setView((v) => ({ ...v, rating: after, flash: color, promoted: true, speed: 0 }));
      });
      at(LEAD_MS + TOP_MS + FLASH_MS, () => setView((v) => ({ ...v, width: 0, flash: null, speed: 0 })));
      at(LEAD_MS + TOP_MS + FLASH_MS + 40, () => setView((v) => ({ ...v, ...settle })));
      count(LEAD_MS + TOP_MS + FLASH_MS + 40, REGROW_MS, now.floor, after);
      end = LEAD_MS + TOP_MS + FLASH_MS + 40 + REGROW_MS + 500;
    } else {
      // No tier is red, so the flash can only read as a drop.
      at(LEAD_MS, () => {
        if (haptics) haptic([60, 50, 60]);
        setView((v) => ({ ...v, width: 1, speed: 0, flash: 'var(--bad)', moved: true }));
      });
      count(LEAD_MS, FLASH_MS + REGROW_MS, before, after);
      at(LEAD_MS + FLASH_MS, () => setView((v) => ({ ...v, ...settle, flash: null })));
      end = LEAD_MS + FLASH_MS + REGROW_MS + 300;
    }
    at(end + HOLD_MS, () => done.current());
    return () => {
      timers.forEach((t) => window.clearTimeout(t));
      cancelAnimationFrame(frame);
    };
    // One playback per card: the moment does not change under it.
  }, []);

  return view;
}

/** The card itself, drawn from a view: still, or mid-playback. */
function Card({ moment, view, className = '' }: { moment: RatingMoment; view: View; className?: string }) {
  const rank = rankOf(view.rating);
  const color = fillColor(view.rating);
  const delta = Math.round(moment.after - moment.before);
  return (
    <div className={`rating-card ${view.promoted ? 'promoted ' : ''}${className}`} style={{ ['--tier' as string]: color }}>
      <div className="top">
        <span className="name">{moment.name}</span>
        {view.moved && <span className={`delta num ${delta < 0 ? 'bad' : 'good'}`}>{deltaText(delta)}</span>}
        <span className="value num">{ratingText(view.shown)}</span>
      </div>
      <div className="names">
        <span key={rank.heldLabel} className={`held${view.promoted ? ' pop' : ''}`} style={{ color }}>
          {rank.heldLabel}
        </span>
        <span>{rank.nextLabel ?? ''}</span>
      </div>
      <div className="track">
        <span
          className="fill"
          style={{
            width: `${view.width * 100}%`,
            ['--glow' as string]: color,
            transition: view.speed ? `width ${view.speed}ms cubic-bezier(0.22, 1, 0.36, 1)` : 'none',
          }}
        >
          <span className="paint" style={{ background: paintFor(view.rating) }} />
        </span>
        {view.stretch && view.stretch.from !== view.stretch.to && (
          <span
            className={`stretch${view.stretch.gain ? '' : ' loss'}`}
            style={{
              left: `${Math.min(view.stretch.from, view.stretch.to) * 100}%`,
              width: `${Math.abs(view.stretch.to - view.stretch.from) * 100}%`,
            }}
          />
        )}
        {view.flash && <span className="flash" style={{ ['--glow' as string]: view.flash, background: view.flash }} />}
        {view.promoted && (
          <span className="burst">
            {SPARKS.map((s, i) => (
              <i key={i} style={{ ['--a' as string]: s.a, ['--d' as string]: s.d, ['--t' as string]: s.t }} />
            ))}
          </span>
        )}
      </div>
    </div>
  );
}

/**
 * The rating change playing over the board as the end screen opens. A
 * promotion also stamps the new tier's name over the board. Tapping it skips
 * to the end; either way `onDone` sends it down to its place on the screen.
 */
export function RatingOverBoard({
  moment,
  leaving,
  onDone,
}: {
  moment: RatingMoment;
  /** Fading out on its way down. */
  leaving: boolean;
  onDone: () => void;
}) {
  const view = usePlayback(moment, onDone);
  const color = fillColor(view.rating);
  return (
    <button
      className={`rating-over${leaving ? ' leaving' : ''}`}
      style={{ ['--tier' as string]: color }}
      onClick={onDone}
      aria-label="Skip"
    >
      {view.promoted && (
        <>
          <span className="rays" />
          <span className="stamp">{rankOf(view.rating).heldLabel}</span>
        </>
      )}
      <Card moment={moment} view={view} />
    </button>
  );
}

/** The rating change at rest, where it stays on the end screen. */
export function RatingCard({ moment, arriving }: { moment: RatingMoment; arriving: boolean }) {
  const view = { ...restingAt(moment.after), moved: true };
  return <Card moment={moment} view={view} className={arriving ? 'arriving' : ''} />;
}
