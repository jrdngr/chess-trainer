import { ANY_FAVORITE } from '../model/anyFavorite';
import { nodeById, openingTree } from '../model/openingTree';
import { referenceIndex } from '../model/referenceIndex';
import { NEW_LABEL, nodeStats, rankOf, UNRATED, type Rank } from '../model/scoring';
import { Icons } from './ui';
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
 * from the left in the colour held, glowing like the end screen's. At the top of the
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
 * A tier as a small bar, for tiles: the end screen's bar in miniature, filled
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

/** The fill's color: below the first rung it climbs in the first rung's color. */
export function fillColor(rating: number): string {
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
export function paintFor(rating: number): string {
  const rank = rankOf(rating);
  const own = fillColor(rating);
  const next = rank.held && rank.next ? rank.next.color : null;
  if (!next) return own;
  const mid = (BLEND_FROM + 1) / 2;
  return `linear-gradient(90deg, ${own} ${BLEND_FROM * 100}%, ${mixHex(own, next, BLEND_MID)} ${mid * 100}%, ${mixHex(own, next, BLEND_MAX)} 100%)`;
}

/**
 * The rating of the opening you have selected, for Home.
 *
 * Any opening shows its tier, its rating, and how far it is from the next
 * tier, and opens its stats. One that is not a favorite
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
        centre={<span className="total">{stats.rated === 0 ? NEW_LABEL : ratingText(stats.rating)}</span>}
      />
    </button>
  );
}
