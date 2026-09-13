import { useEffect, useState } from 'react';
import { Icons } from '../../components/ui';
import { ColorSquare } from '../../components/Selection';
import { GAME_SIZE, type GamePlan, type GameSummary } from '../../model/autopilot';
import { MODE_NAMES, type Recommendation } from '../../model/recommend';
import { useStore } from '../../store/useStore';
import { recommendNow } from '../../store/recommendation';
import { DrillScreen } from '../drill/DrillScreen';
import { GrowthScreen } from '../growth/GrowthScreen';
import { OpeningRunScreen } from '../openingRun/OpeningRunScreen';
import { RepairScreen } from '../repair/RepairScreen';

/**
 * Autopilot.
 *
 * The engine picks a game, the mode plays it, and when it is over a bar
 * offers the next one by name: no Home in between, no setup screens, one
 * tap per game. A session never ends on its own. Stop is the close button
 * in the app bar, and stopping opens Stats.
 */
export function AutopilotScreen({ onExit, onImport }: { onExit: () => void; onImport: () => void }) {
  const [pick, setPick] = useState<Recommendation>(() => recommendNow(useStore.getState()));
  /** Bumped per game so the mode screen mounts fresh. */
  const [round, setRound] = useState(1);
  const [over, setOver] = useState<GameSummary | null>(null);
  const [next, setNext] = useState<Recommendation | null>(null);

  const startNext = (upcoming: Recommendation) => {
    setPick(upcoming);
    setNext(null);
    setOver(null);
    setRound((n) => n + 1);
  };

  /**
   * A Run ends on its reveal, which is worth reading, so the next game waits
   * on a tap. Every other mode ends on a summary nobody needs — the score bar
   * has already said what it earned — so the next game simply starts. Growth
   * gets a beat, since its ending shows a move worth a glance.
   */
  const gameOver = (summary: GameSummary) => {
    const upcoming = recommendNow(useStore.getState());
    if (summary.mode === 'run') {
      setOver(summary);
      setNext(upcoming);
      return;
    }
    if (summary.mode === 'growth') window.setTimeout(() => startNext(upcoming), 900);
    else startNext(upcoming);
  };

  const advance = () => {
    if (next) startNext(next);
  };

  const plan: GamePlan = { color: pick.color, steer: pick.opening.id };
  const props = { auto: true, plan, onGameOver: gameOver, onExit, key: round };

  return (
    <>
      <ModeIntro key={round} name={MODE_NAMES[pick.mode]} />
      {pick.mode === 'run' && <OpeningRunScreen {...props} />}
      {pick.mode === 'drill' && <DrillScreen {...props} limit={GAME_SIZE.drill} />}
      {pick.mode === 'growth' && <GrowthScreen {...props} />}
      {pick.mode === 'repair' && (
        <RepairScreen {...props} limit={GAME_SIZE.repair} onImport={onImport} />
      )}
      {over && next && <NextBar earned={over.score} perfect={over.perfect} next={next} onNext={advance} />}
    </>
  );
}

/**
 * The mode's name, large over the board as a game begins, then carried up
 * into its place in the app bar. The real title is underneath the whole
 * time, so the name lands where it will stay.
 */
function ModeIntro({ name }: { name: string }) {
  const [shown, setShown] = useState(true);
  /** Where the app bar's title actually sits, measured once the screen is up. */
  const [land, setLand] = useState<{ x: number; y: number } | null>(null);
  useEffect(() => {
    // Measured just before the name sets off rather than on mount: the bar's
    // clock and chips arrive with the first move, and shift the title.
    const measure = window.setTimeout(() => {
      const title = document.querySelector('.appbar .appbar-title .line');
      if (!title) return;
      const box = title.getBoundingClientRect();
      setLand({ x: box.left + box.width / 2, y: box.top + box.height / 2 });
    }, 700);
    const timer = window.setTimeout(() => setShown(false), 1500);
    return () => {
      window.clearTimeout(measure);
      window.clearTimeout(timer);
    };
  }, []);
  if (!shown) return null;
  return (
    <div
      className="mode-intro"
      style={land ? { ['--land-x' as string]: `${land.x}px`, ['--land-y' as string]: `${land.y}px` } : undefined}
      aria-hidden
    >
      <span>{name}</span>
    </div>
  );
}

/** "Next: Drill", over the end of the last game. */
function NextBar({
  earned,
  perfect,
  next,
  onNext,
}: {
  earned: number;
  perfect: boolean;
  next: Recommendation;
  onNext: () => void;
}) {
  return (
    <div className={`next-bar${perfect ? ' perfect' : ''}`}>
      <div className="earned">
        <span className="pts num">+{earned}</span>
        <span className="lbl">{perfect ? 'Perfect game' : 'this game'}</span>
      </div>
      <button className="go" onClick={onNext}>
        <span className="grow" style={{ minWidth: 0 }}>
          <span className="kicker">Next</span>
          <span className="what truncate">{MODE_NAMES[next.mode]}</span>
        </span>
        <ColorSquare choice={next.color} size={18} />
        <Icons.next size={20} />
      </button>
    </div>
  );
}

