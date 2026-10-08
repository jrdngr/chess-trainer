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
          <span className="fill" style={{ width: `${rank.progress * 100}%`, ['--glow' as string]: fill }}>
            <span className="paint" style={{ background: paintFor(rank.rating) }} />
          </span>
        </span>
      </div>
    </div>
  );
}

/**
 * A tier as a small bar, for tiles: the header's bar in miniature, filled
 * toward the next tier with the same paint, and the tier's name sitting on it.
 * Never the number.
 */
export function TierBar({ rating, rated }: { rating: number; rated: number }) {
  const rank = rankOf(rating, rated);
  const color = fillColor(rating);
  return (
    <span className="tier-bar">
      {rated > 0 && (
        <span className="fill" style={{ width: `${rank.progress * 100}%`, ['--glow' as string]: color }}>
          <span className="paint" style={{ background: paintFor(rating) }} />
        </span>
      )}
      <span className="tier-name">{rated === 0 ? NEW_LABEL : rank.heldLabel}</span>
    </span>
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

/**
 * Where along the track the next tier's color starts to come in, how much of
 * it the three-quarter mark holds (subtle), and how much the end holds.
 */
const BLEND_FROM = 0.5;
const BLEND_MID = 0.2;
const BLEND_MAX = 0.9;

/** Two hex colors mixed, `amount` of the way from `a` to `b`. */
function mixHex(a: string, b: string, amount: number): string {
  const channels = (hex: string) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
  const [x, y] = [channels(a), channels(b)];
  return `#${x.map((c, i) => Math.round(c + (y[i] - c) * amount).toString(16).padStart(2, '0')).join('')}`;
}

/**
 * The fill's paint, laid along the whole track so it does not stretch as the
 * fill grows: the tier's color, leaning toward the next tier's from halfway,
 * subtle at first and growing stronger to the end, never all the way there.
 */
function paintFor(rating: number): string {
  const rank = rankOf(rating);
  const own = fillColor(rating);
  const next = rank.held && rank.next ? rank.next.color : null;
  if (!next) return own;
  const mid = (BLEND_FROM + 1) / 2;
  return `linear-gradient(90deg, ${own} ${BLEND_FROM * 100}%, ${mixHex(own, next, BLEND_MID)} ${mid * 100}%, ${mixHex(own, next, BLEND_MAX)} 100%)`;
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
 * promotion never reads as a loss; crossing one down flashes red full and
 * shrinks to where the rating landed.
 *
 * Until the run's line reaches the opening its rating cannot move, so the
 * bar is dimmed and names the move it is waiting for: "Rated from 3.Bb5". Any opening has no rating and gets nothing. The rating's
 * number is never shown here: the tier and the bar are what you play for.
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
      // Down: flash red full, then shrink to where the rating landed. No tier
      // is red, so it can only read as a drop.
      setView({ ...settle, width: 1, speed: 0, flash: 'var(--bad)', stretch: null, pop });
      later(FLASH_MS, () => setView((v) => ({ ...v, ...settle })));
    }
  }, [openingId, rating, haptics]);

  useEffect(() => () => timers.current.forEach((t) => window.clearTimeout(t)), []);

  const node = openingId === '' ? null : nodeById(openingTree(referenceIndex()), openingId);
  if (!node || node.depth === 0) return null;

  const rank = rankOf(view.rating, rated);
  const label = (
    <span className={`header-rating${reached ? '' : ' dim'}`}>
      <span className="sep">·</span>
      <span className="tier" style={{ color: rank.held?.color }}>
        {rated === 0 ? NEW_LABEL : rank.heldLabel}
      </span>
      {view.pop && (
        <span key={view.pop.key} className={`header-pop num${view.pop.delta < 0 ? ' down' : ''}`}>
          {deltaText(view.pop.delta)}
        </span>
      )}
    </span>
  );
  const edge = (
    <div className={`header-edge${reached ? '' : ' dim'}`}>
      {!reached && <span className="wait">Rated from {definingMove(node.sans)}</span>}
      <span
        className="fill"
        style={{
          width: `${view.width * 100}%`,
          ['--glow' as string]: view.color,
          transition: view.speed ? `width ${view.speed}ms cubic-bezier(0.22, 1, 0.36, 1)` : 'none',
        }}
      >
        <span className="paint" style={{ background: paintFor(view.rating) }} />
      </span>
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

/** The move that makes an opening what it is, numbered: "3.Bb5", "2...c5". */
function definingMove(sans: string[]): string {
  const ply = sans.length;
  const number = Math.ceil(ply / 2);
  return `${number}${ply % 2 === 1 ? '.' : '...'}${sans[ply - 1] ?? ''}`;
}

/**
 * The rating of the opening you have selected, for Home.
 *
 * Any opening shows its tier and how far it is from the next tier, never
 * the rating's number, and opens its stats. One that is not a favorite
 * carries an outline star by its name: a label, never a button, so nothing
 * here can favorite it by accident. Any opening and Any favorite show nothing.
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
        // The tier says where it stands; the number is not shown here.
        centre={stats.rated === 0 ? <span className="total">{NEW_LABEL}</span> : null}
      />
    </button>
  );
}
