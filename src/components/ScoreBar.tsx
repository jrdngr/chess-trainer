import { useEffect, useRef, useState } from 'react';
import { milestoneOf } from '../model/scoring';
import { haptic } from './ui';
import { useStore } from '../store/useStore';

/** How long the bar stays after points land; longer for a milestone. */
const SHOW_MS = 2600;
const MILESTONE_MS = 4200;

/**
 * The score, at the top of the screen, whenever it moves.
 *
 * It slides in on every event with the points just earned, fills toward the
 * next milestone in that milestone's colour, and slides away. Crossing a
 * milestone fills the bar to the end, flashes it, names the colour, and buzzes
 * — then the bar starts again in the colour after that.
 */
export function ScoreBar() {
  const feed = useStore((s) => s.feed);
  const haptics = useStore((s) => s.settings.hapticFeedback);
  const openStats = useStore((s) => s.openStats);
  const [shown, setShown] = useState(false);
  const [celebrating, setCelebrating] = useState(false);
  /** The bar draws the state before the event first, so the fill can animate. */
  const [displayTotal, setDisplayTotal] = useState(feed.total);
  const timer = useRef<number | null>(null);
  const seen = useRef(feed.seq);

  useEffect(() => {
    if (feed.seq === seen.current) return;
    seen.current = feed.seq;
    setShown(true);
    // From the previous total to the new one, one frame later, so the
    // transition has somewhere to go.
    setDisplayTotal(feed.total - feed.points);
    const raise = window.requestAnimationFrame(() => setDisplayTotal(feed.total));
    if (feed.milestone) {
      setCelebrating(true);
      if (haptics) haptic([20, 40, 20, 40, 60]);
    }
    if (timer.current) window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => {
      setShown(false);
      setCelebrating(false);
    }, feed.milestone ? MILESTONE_MS : SHOW_MS);
    return () => window.cancelAnimationFrame(raise);
  }, [feed, haptics]);

  const milestone = milestoneOf(displayTotal);
  const reached = feed.milestone;
  const label = celebrating && reached ? `${reached.heldLabel}!` : milestone.nextLabel;
  const color = celebrating && reached ? reached.held?.color : milestone.next.color;

  return (
    <div
      className={`score-bar${shown ? ' shown' : ''}${celebrating ? ' celebrate' : ''}`}
      style={{ ['--tier' as string]: color }}
      aria-live="polite"
      onClick={() => shown && openStats('')}
    >
      <div className="head">
        <span className="tier">
          <i />
          {label}
        </span>
        <span className="gain num">{feed.points > 0 ? `+${feed.points}` : ''}</span>
        <span className="total num">{displayTotal}</span>
      </div>
      <div className="track">
        <div className="fill" style={{ width: `${milestone.progress * 100}%` }} />
      </div>
    </div>
  );
}

/**
 * The score as it stands, for Home: the colour being worked toward, the fill
 * to the next milestone, and the total. Tapping it opens Stats.
 */
export function ScoreStrip() {
  const total = useStore((s) => s.score.total);
  const openStats = useStore((s) => s.openStats);
  const milestone = milestoneOf(total);
  return (
    <button
      className="score-strip"
      style={{ ['--tier' as string]: milestone.next.color }}
      onClick={() => openStats('')}
      aria-label="Score and stats"
    >
      <span className="head">
        <span className="tier">
          <i />
          {milestone.heldLabel ? `${milestone.heldLabel} · toward ${milestone.nextLabel}` : `Toward ${milestone.nextLabel}`}
        </span>
        <span className="total num">{total}</span>
      </span>
      <span className="track">
        <span className="fill" style={{ width: `${milestone.progress * 100}%` }} />
      </span>
    </button>
  );
}
