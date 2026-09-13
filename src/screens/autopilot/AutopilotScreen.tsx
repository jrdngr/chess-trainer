import { useState } from 'react';
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

  const gameOver = (summary: GameSummary) => {
    setOver(summary);
    // Decided now, while the reveal is still up, so the bar can say what it is.
    setNext(recommendNow(useStore.getState()));
  };

  const advance = () => {
    if (!next) return;
    setPick(next);
    setNext(null);
    setOver(null);
    setRound((n) => n + 1);
  };

  const plan: GamePlan = { color: pick.color, steer: pick.opening.id };
  const props = { auto: true, plan, onGameOver: gameOver, onExit, key: round };

  return (
    <>
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

