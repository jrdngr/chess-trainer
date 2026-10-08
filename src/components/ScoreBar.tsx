import { useEffect, useRef, useState } from 'react';
import { ANY_FAVORITE } from '../model/anyFavorite';
import { nodeById, openingTree } from '../model/openingTree';
import { referenceIndex } from '../model/referenceIndex';
import { NEW_LABEL, nodeStats, rankOf, UNRATED, type Rank } from '../model/scoring';
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
 * The rank bar, the same everywhere it appears: the rung held named on the
 * left, the rung being worked toward named on the right, and the bar filling
 * from the left in the colour held, glowing like the header's. At the top of the
 * ladder there is nothing left to work toward, so the right-hand end is the
 * rung held and the bar is full.
 */
export function RankBar({ rank, centre }: { rank: Rank; centre?: React.ReactNode }) {
  const held = rank.held ?? UNRATED;
  const next = rank.next ?? held;
  // Below-the-ladder grey is the colour of the empty track, so below the first rung
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
        <span className="track">
          <span
            className="fill"
            style={{
              width: `${rank.progress * 100}%`,
              background: fill,
              ['--glow' as string]: fill,
              ['--tip' as string]: tipColor(rank.rating),
            }}
          />
        </span>
      </div>
    </div>
  );
}

/** How long the fill takes to grow or shrink to where the rating now stands. */
const GROW_MS = 700;
/** Filling up to the rung before a promotion, and the flash on crossing it. */
const TOP_MS = 320;
const FLASH_MS = 760;

/** What the header draws, which lags the rating while a tier change plays out. */
interface EdgeView {
  /** The rating the label names. */
  rating: number;
  /** How full the bar is, 0..1. */
  width: number;
  color: string;
  /** How long the width takes to get where it is going; 0 snaps. */
  speed: number;
  /** A tier crossed: the bar flashes in this color. */
  flash: string | null;
  /** The stretch an answer just added or took away, glowing. */
  stretch: { key: number; from: number; to: number; gain: boolean } | null;
  /** What the answer was worth, by the rating. */
  pop: { key: number; delta: number } | null;
}

/** The fill's color: below the first rung it climbs in the first rung's color. */
function fillColor(rating: number): string {
  const rank = rankOf(rating);
  return (rank.held ?? rank.next ?? UNRATED).color;
}

/** The fill's leading tip: the tier it is filling toward, or the top tier's own at the top. */
function tipColor(rating: number): string {
  const rank = rankOf(rating);
  return (rank.next ?? rank.held ?? UNRATED).color;
}

function restingView(rating: number): EdgeView {
  return {
    rating,
    width: rankOf(rating).progress,
    color: fillColor(rating),
    speed: 0,
    flash: null,
    stretch: null,
    pop: null,
  };
}

/**
 * The rating of the opening a Survival round is played in, built into the
 * round's header: a label for the subtitle and a bar for the header's bottom
 * edge.
 *
 * The bar stays up all round. Each answer grows or shrinks it, with the
 * stretch it moved glowing and what it was worth popping by the rating.
 * Crossing a rung up fills the bar, flashes it in the new tier's color,
 * clears it and grows it from the left with what is left over, so a
 * promotion never reads as a loss; crossing one down flashes the lower tier's
 * color full and shrinks to where the rating landed.
 *
 * Until the run's line reaches the opening its rating cannot move, so the
 * bar is dimmed. Any opening has no rating and gets nothing.
 */
export function useHeaderRating(
  openingId: string,
  reached: boolean,
): { label: React.ReactNode; edge: React.ReactNode } | null {
  // Two numbers, not the stats object: an opening never played has none, and a
  // fresh empty one every render would never settle.
  const rating = useStore((s) => nodeStats(s.score, openingId).rating);
  const rated = useStore((s) => nodeStats(s.score, openingId).rated);
  const haptics = useStore((s) => s.settings.hapticFeedback);
  const [view, setView] = useState(() => restingView(rating));
  const shown = useRef({ id: openingId, rating });
  const seq = useRef(0);
  const timers = useRef<number[]>([]);

  useEffect(() => {
    const later = (ms: number, step: () => void) => timers.current.push(window.setTimeout(step, ms));
    const from = shown.current;
    const to = rating;
    if (from.id === openingId && from.rating === to) return;
    shown.current = { id: openingId, rating: to };
    timers.current.forEach((t) => window.clearTimeout(t));
    timers.current = [];
    // A new round's opening: no story to tell, just where it stands.
    if (from.id !== openingId) {
      setView(restingView(to));
      return;
    }
    const was = rankOf(from.rating);
    const now = rankOf(to);
    const key = (seq.current += 1);
    const pop = Math.round(to - from.rating) !== 0 ? { key, delta: to - from.rating } : null;
    const settle = { rating: to, width: now.progress, color: fillColor(to), speed: GROW_MS, flash: null };

    if (now.reached === was.reached) {
      setView({ ...settle, pop, stretch: { key, from: was.progress, to: now.progress, gain: to > from.rating } });
      return;
    }
    if (haptics) haptic(now.reached > was.reached ? [20, 40, 20, 40, 60] : [60, 50, 60]);
    if (now.reached > was.reached) {
      // Up: fill to the rung, flash the new tier, clear, and grow from the left.
      const color = fillColor(to);
      setView((v) => ({ ...v, width: 1, speed: TOP_MS, stretch: null, pop }));
      later(TOP_MS, () => setView((v) => ({ ...v, rating: to, color, flash: color, speed: 0 })));
      later(TOP_MS + FLASH_MS, () => setView((v) => ({ ...v, width: 0, flash: null, speed: 0 })));
      later(TOP_MS + FLASH_MS + 40, () => setView((v) => ({ ...v, ...settle })));
    } else {
      // Down: flash the lower tier full, then shrink to where the rating landed.
      const color = fillColor(to);
      setView({ ...settle, width: 1, speed: 0, flash: color, stretch: null, pop });
      later(FLASH_MS, () => setView((v) => ({ ...v, ...settle })));
    }
  }, [openingId, rating, haptics]);

  useEffect(() => () => timers.current.forEach((t) => window.clearTimeout(t)), []);

  if (openingId === '' || nodeById(openingTree(referenceIndex()), openingId).depth === 0) return null;

  const rank = rankOf(view.rating, rated);
  const label = (
    <span className={`header-rating${reached ? '' : ' dim'}`}>
      <span className="sep">·</span>
      <span className="tier" style={{ color: rank.held?.color }}>
        {rated === 0 ? NEW_LABEL : rank.heldLabel}
      </span>
      {rated > 0 && <span className="num">{ratingText(view.rating)}</span>}
      {view.pop && (
        <span key={view.pop.key} className={`header-pop num${view.pop.delta < 0 ? ' down' : ''}`}>
          {deltaText(view.pop.delta)}
        </span>
      )}
    </span>
  );
  const edge = (
    <div className={`header-edge${reached ? '' : ' dim'}`} aria-hidden>
      <span
        className="fill"
        style={{
          width: `${view.width * 100}%`,
          background: view.color,
          ['--glow' as string]: view.color,
          ['--tip' as string]: tipColor(view.rating),
          transition: view.speed ? `width ${view.speed}ms cubic-bezier(0.22, 1, 0.36, 1)` : 'none',
        }}
      />
      {view.stretch && view.stretch.from !== view.stretch.to && (
        <span
          key={view.stretch.key}
          className={`stretch${view.stretch.gain ? '' : ' loss'}`}
          style={{
            left: `${Math.min(view.stretch.from, view.stretch.to) * 100}%`,
            width: `${Math.abs(view.stretch.to - view.stretch.from) * 100}%`,
          }}
        />
      )}
      {view.flash && <span className="flash" style={{ ['--glow' as string]: view.flash, background: view.flash }} />}
    </div>
  );
  return { label, edge };
}

/**
 * The rating of the opening you have selected, for Home.
 *
 * Any opening shows its tier, its rating and how far it is from the next
 * tier, and opens its stats. One that is not a favorite carries an outline
 * star by its name: a label, never a button, so nothing here can favorite it
 * by accident. Any opening and Any favorite show nothing.
 */
export function ScoreStrip() {
  const selection = useStore((s) => s.settings.selection);
  const starredIds = useStore((s) => s.settings.favoriteOpenings);
  const score = useStore((s) => s.score);
  const openStats = useStore((s) => s.openStats);
  const tree = openingTree(referenceIndex());

  // Any opening and Any favorite have no one opening to report on.
  if (selection.opening === '' || selection.opening === ANY_FAVORITE) return null;

  const node = nodeById(tree, selection.opening);
  const favorite = starredIds.includes(node.id);
  const stats = nodeStats(score, node.id);
  const rank = rankOf(stats.rating, stats.rated);
  return (
    <button className="score-strip" onClick={() => openStats(node.id)} aria-label={`${node.name} rating`}>
      <span className="who truncate">
        {!favorite && (
          <span className="not-fav" aria-label="Not a favorite">
            <Icons.star size={11} />
          </span>
        )}
        {node.name}
      </span>
      <RankBar
        rank={rank}
        centre={
          <span className="total num">
            {stats.rated === 0 ? NEW_LABEL : ratingText(stats.rating)}
          </span>
        }
      />
    </button>
  );
}
