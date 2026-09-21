import { useEffect, useRef, useState } from 'react';
import { nodeById, openingTree } from '../model/openingTree';
import { referenceIndex } from '../model/referenceIndex';
import { nodeStats, rankOf, UNRATED, type Rank } from '../model/scoring';
import { haptic, Icons } from './ui';
import { useStore } from '../store/useStore';

/** A rating as it is shown: whole numbers, never a decimal. */
export function ratingText(rating: number): string {
  return String(Math.round(rating));
}

/** A rating change as it is shown, with its sign. */
export function deltaText(delta: number): string {
  const rounded = Math.round(delta);
  return rounded >= 0 ? `+${rounded}` : String(rounded);
}

/**
 * The rank bar, the same everywhere it appears: the piece held on the left,
 * the piece being worked toward on the right, each a dot with its name above
 * it, and the bar between them filled in the colour held. At the top of the
 * ladder there is nothing left to work toward, so the right-hand end is the
 * piece held and the bar is full.
 */
export function RankBar({ rank, centre }: { rank: Rank; centre?: React.ReactNode }) {
  const held = rank.held ?? UNRATED;
  const next = rank.next ?? held;
  // Unrated grey is the colour of the empty track, so below the first piece
  // the bar fills in the colour it is climbing toward instead of vanishing.
  const fill = rank.held?.color ?? next.color;
  return (
    <div className="milestone">
      <div className="names">
        <span className="name">{rank.heldLabel}</span>
        <span className="centre">{centre}</span>
        <span className="name">{rank.nextLabel ?? ''}</span>
      </div>
      <div className="rail">
        <i className="dot" style={{ background: held.color, boxShadow: `0 0 8px ${held.color}` }} />
        <span className="track">
          <span className="fill" style={{ width: `${rank.progress * 100}%`, background: fill }} />
        </span>
        <i className="dot" style={{ background: next.color, boxShadow: `0 0 8px ${next.color}` }} />
      </div>
    </div>
  );
}

/** How long the bar stays after a rating moves; longer for a promotion. */
const SHOW_MS = 2600;
const TIER_MS = 4200;

/**
 * The rating, at the top of the screen, whenever one moves.
 *
 * It slides in naming the opening that moved, with what the answer was worth
 * and where the rating now stands, fills toward the next piece in that piece's
 * colour, and slides away. Crossing a piece — up or down — flashes the bar,
 * names the piece and buzzes: a promotion is worth celebrating, and a demotion
 * is worth knowing about, which is the point of a rating that can fall.
 */
export function ScoreBar() {
  const feed = useStore((s) => s.feed);
  const haptics = useStore((s) => s.settings.hapticFeedback);
  const openStats = useStore((s) => s.openStats);
  const [shown, setShown] = useState(false);
  const [flash, setFlash] = useState<1 | -1 | 0>(0);
  /** The bar draws the rating before the answer first, so the fill can animate. */
  const [display, setDisplay] = useState(feed.after);
  const timer = useRef<number | null>(null);
  const seen = useRef(feed.seq);

  useEffect(() => {
    if (feed.seq === seen.current) return;
    seen.current = feed.seq;
    setShown(true);
    setDisplay(feed.before);
    const raise = window.requestAnimationFrame(() => setDisplay(feed.after));
    setFlash(feed.promotion);
    if (feed.promotion !== 0 && haptics) {
      haptic(feed.promotion > 0 ? [20, 40, 20, 40, 60] : [60, 50, 60]);
    }
    if (timer.current) window.clearTimeout(timer.current);
    timer.current = window.setTimeout(
      () => {
        setShown(false);
        setFlash(0);
      },
      feed.promotion !== 0 ? TIER_MS : SHOW_MS,
    );
    return () => window.cancelAnimationFrame(raise);
  }, [feed, haptics]);

  const tree = openingTree(referenceIndex());
  const rank = rankOf(display);
  const delta = feed.after - feed.before;
  const name = feed.openingId ? nodeById(tree, feed.openingId).name : '';

  return (
    <div
      className={`score-bar${shown ? ' shown' : ''}${flash !== 0 ? ' celebrate' : ''}${flash < 0 ? ' demoted' : ''}`}
      style={{ ['--tier' as string]: (rank.held ?? UNRATED).color }}
      aria-live="polite"
      onClick={() => shown && feed.openingId && openStats(feed.openingId)}
    >
      <div className="who truncate">{name}</div>
      <RankBar
        rank={rank}
        centre={
          <>
            <span className={`gain num${delta < 0 ? ' down' : ''}`}>{deltaText(delta)}</span>
            <span className="total num">{ratingText(display)}</span>
          </>
        }
      />
    </div>
  );
}

/**
 * The rating of the opening you have selected, for Home.
 *
 * Only starred openings are rated, so this box has three things to say. A
 * starred opening shows its piece, its rating and how far it is from the next
 * piece. One you have selected but not starred explains itself in a line and
 * offers the star. With the whole tree selected there is no one opening to
 * report on, so it points at the list of the ones there are.
 */
export function ScoreStrip() {
  const selection = useStore((s) => s.settings.selection);
  const starredIds = useStore((s) => s.settings.favoriteOpenings);
  const score = useStore((s) => s.score);
  const toggleStar = useStore((s) => s.toggleStar);
  const openStats = useStore((s) => s.openStats);
  const tree = openingTree(referenceIndex());

  if (selection.opening === '') {
    return (
      <button className="score-strip empty" onClick={() => openStats('')} aria-label="Your ratings">
        <span className="grow">
          <span className="ttl">No opening selected</span>
          <span className="sub">Pick a starred opening above to see its rating.</span>
        </span>
        <Icons.chevron size={18} />
      </button>
    );
  }

  const node = nodeById(tree, selection.opening);

  if (!starredIds.includes(node.id)) {
    return (
      <button
        className="score-strip empty"
        onClick={() => toggleStar(node.id)}
        aria-label={`Star ${node.name}`}
      >
        <span className="grow">
          <span className="ttl truncate">{node.name}</span>
          <span className="sub">Not starred, so no rating. Star it to start one.</span>
        </span>
        <Icons.star size={20} />
      </button>
    );
  }

  const stats = nodeStats(score, node.id);
  const rank = rankOf(stats.rating);
  return (
    <button className="score-strip" onClick={() => openStats(node.id)} aria-label={`${node.name} rating`}>
      <span className="who truncate">{node.name}</span>
      <RankBar
        rank={rank}
        centre={
          <span className="total num">
            {stats.rated === 0 ? 'Unrated' : ratingText(stats.rating)}
          </span>
        }
      />
    </button>
  );
}
