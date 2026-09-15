import { useState } from 'react';
import { Icons } from '../../components/ui';
import { planFor, type RoundSummary } from '../../model/autopilot';
import { isSteered, type Focus, type Recommendation } from '../../model/recommend';
import { useStore } from '../../store/useStore';
import { recommendNow } from '../../store/recommendation';
import { OpeningRunScreen } from '../openingRun/OpeningRunScreen';

/**
 * Autopilot.
 *
 * Every round is a Run. The engine picks the opening, the colour and the
 * settings — what the opponent steers toward, whether the run may add to
 * the repertoire — and the Run plays it. When a round ends, a bar over its
 * reveal shows what it earned and offers the next one: no Home in between,
 * no setup screens, one tap per round. The settings are the engine's
 * business and nothing on screen names them. A session never ends on its
 * own. Stop is the close button in the app bar, and stopping opens Stats.
 */
export function AutopilotScreen({ onExit }: { onExit: () => void }) {
  /** The focuses of this session's rounds so far, oldest first: the engine's brake. */
  const [recent, setRecent] = useState<Focus[]>([]);
  /** For each of those rounds, whether it was steered into an opening: the engine spaces them. */
  const [steered, setSteered] = useState<boolean[]>([]);
  const [pick, setPick] = useState<Recommendation>(() => recommendNow(useStore.getState(), [], []));
  /** Bumped per round so the Run mounts fresh. */
  const [round, setRound] = useState(1);
  const [over, setOver] = useState<RoundSummary | null>(null);
  const [next, setNext] = useState<Recommendation | null>(null);

  /** A round ends on its reveal, which is worth reading, so the next waits on a tap. */
  const roundOver = (summary: RoundSummary) => {
    const state = useStore.getState();
    const played = [...recent, pick.focus];
    const steers = [...steered, isSteered(pick, state.settings.selection)];
    setRecent(played);
    setSteered(steers);
    setOver(summary);
    setNext(recommendNow(state, played, steers));
  };

  const advance = () => {
    if (!next) return;
    setPick(next);
    setNext(null);
    setOver(null);
    setRound((n) => n + 1);
  };

  return (
    <>
      <OpeningRunScreen key={round} auto plan={planFor(pick)} onRoundOver={roundOver} onExit={onExit} />
      {over && next && <NextBar earned={over.score} perfect={over.perfect} onNext={advance} />}
    </>
  );
}

/** What the round earned, and one button: the next round. */
function NextBar({ earned, perfect, onNext }: { earned: number; perfect: boolean; onNext: () => void }) {
  return (
    <div className={`next-bar${perfect ? ' perfect' : ''}`}>
      <div className="earned">
        <span className="pts num">+{earned}</span>
        <span className="lbl">{perfect ? 'Perfect round' : 'this round'}</span>
      </div>
      <button className="go" onClick={onNext}>
        <span className="what grow">Next Round</span>
        <Icons.next size={20} />
      </button>
    </div>
  );
}
