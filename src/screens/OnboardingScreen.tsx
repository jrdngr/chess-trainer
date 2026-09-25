import { useMemo } from 'react';
import { AppBar } from '../components/ui';
import { ColorSquare, OpeningList } from '../components/Selection';
import { openingTree } from '../model/openingTree';
import { picksFrom } from '../model/onboarding';
import { referenceIndex } from '../model/referenceIndex';
import { useStore } from '../store/useStore';

/**
 * The first screen a new profile sees, and the only one it is asked anything on.
 *
 * Everything else in the app works on a repertoire, and a fresh install has
 * none — so the question is which openings are already yours. Picks are stars,
 * because that is what a star means everywhere else: the openings you mean to
 * play. Each one puts its own move order into the tree for the side that plays
 * it, and nothing more; Growth is where the lines get longer.
 *
 * Skipping is a real answer, not a failure. It leaves the profile exactly as it
 * was and is never asked again, short of a full reset.
 */
export function OnboardingScreen() {
  const starred = useStore((s) => s.settings.favoriteOpenings);
  const finishOnboarding = useStore((s) => s.finishOnboarding);
  const tree = openingTree(referenceIndex());

  // Read back through the tree rather than counted raw: a star the book no
  // longer knows is not an opening that can be added.
  const picks = useMemo(() => picksFrom(tree, starred), [tree, starred]);
  const white = picks.filter((pick) => pick.color === 'w').length;
  const black = picks.length - white;

  return (
    <>
      <AppBar title="Your openings" large />
      <div className="screen no-nav">
        <div className="note">
          Pick the openings you already play, at whatever depth you know them.
        </div>

        <div className="op-inline">
          <OpeningList multi />
        </div>
      </div>

      <div className="onboard-bar">
        {picks.length > 0 && (
          <div className="onboard-tally">
            {white > 0 && (
              <span className="side-count">
                <ColorSquare choice="w" size={14} /> {white}
              </span>
            )}
            {black > 0 && (
              <span className="side-count">
                <ColorSquare choice="b" size={14} /> {black}
              </span>
            )}
          </div>
        )}
        <button
          className={`btn block xl${picks.length ? ' primary' : ''}`}
          onClick={() => finishOnboarding(picks.map((pick) => pick.id))}
        >
          {/* Named while there is one, because a name is worth more than a
              count — truncated, because some of them are very long. */}
          <span className="truncate">
            {picks.length === 0
              ? 'Not yet — start empty'
              : picks.length === 1
                ? `Add ${picks[0].name}`
                : `Add ${picks.length} openings`}
          </span>
        </button>
      </div>
    </>
  );
}
