import { useRef, useState } from 'react';
import { nodeById, openingTree } from '../model/openingTree';
import { referenceIndex } from '../model/referenceIndex';
import { rankOf, UNRATED, type RatingMove } from '../model/scoring';
import { deltaText, ratingText } from './ScoreBar';

/** One opening's rating, as a round left it. */
export interface RatingChange {
  id: string;
  name: string;
  /** Points gained or lost across the whole round. */
  delta: number;
  /** Where the rating stands now. */
  after: number;
}

/**
 * The ratings a round has moved so far: where each stood when the round first
 * touched it, and where it stands now. A ref as well as state, because the end
 * of a round reads it in the same tick an answer writes it.
 */
export function useRatingTracker() {
  const seen = useRef(new Map<string, { before: number; after: number }>());
  const [moved, setMoved] = useState<RatingChange[]>([]);
  const changes = (): RatingChange[] => {
    const tree = openingTree(referenceIndex());
    return [...seen.current]
      .map(([id, rating]) => ({
        id,
        name: nodeById(tree, id).name,
        delta: rating.after - rating.before,
        after: rating.after,
      }))
      .filter((change) => Math.round(change.delta) !== 0);
  };
  const track = (moves: RatingMove[]) => {
    for (const move of moves) {
      const rating = seen.current.get(move.id);
      if (rating) rating.after = move.after;
      else seen.current.set(move.id, { before: move.before, after: move.after });
    }
    setMoved(changes());
  };
  const reset = () => {
    seen.current = new Map();
    setMoved([]);
  };
  return { moved, track, reset };
}

/**
 * What a round did to your ratings, one line per starred opening it was
 * played inside. Nothing at all when the round touched none of them — which
 * is the usual case until something on the line is starred.
 */
export function Ratings({ moved }: { moved: RatingChange[] }) {
  if (moved.length === 0) return null;
  return (
    <div className="list ratings">
      {moved.map((change) => {
        const rank = rankOf(change.after);
        const color = (rank.held ?? UNRATED).color;
        return (
          <div className="list-row" key={change.id}>
            <span className="side" style={{ background: color }} />
            <span className="grow" style={{ minWidth: 0 }}>
              <div className="title truncate">{change.name}</div>
              <div className="meta truncate">{rank.heldLabel}</div>
            </span>
            <span className={`val num ${change.delta < 0 ? 'bad' : 'good'}`}>{deltaText(change.delta)}</span>
            <span className="val num muted">{ratingText(change.after)}</span>
          </div>
        );
      })}
    </div>
  );
}
