import { useState } from 'react';
import { AppBar, Icons } from '../../components/ui';
import { SelectionBar, selectionText } from '../../components/Selection';
import { planFor } from '../../model/autopilot';
import { isSteered, type Focus, type Recommendation } from '../../model/recommend';
import { useStore } from '../../store/useStore';
import { recommendNow } from '../../store/recommendation';
import { OpeningRunScreen } from '../openingRun/OpeningRunScreen';

/**
 * Autopilot.
 *
 * Every round is a Run of what you already have. The engine picks the
 * opening, the colour and what the opponent steers toward, and the Run
 * plays it. When a round ends, its reveal offers the next one right under the
 * board: no Home in between, no setup screens, one tap per round. The rating
 * moves at the top of the screen as it is earned, so nothing sums it up again.
 * The settings are the engine's business and nothing on screen names them. A
 * session never ends on its own. Stop is the close button in the app bar,
 * and stopping goes Home.
 *
 * Autopilot never adds to the repertoire. With nothing prepared inside the
 * selection there is nothing to drill, and it says so and points at Growth.
 */
export function AutopilotScreen({ onExit, onGrow }: { onExit: () => void; onGrow: () => void }) {
  /** The focuses of this session's rounds so far, oldest first: the engine's brake. */
  const [recent, setRecent] = useState<Focus[]>([]);
  /** For each of those rounds, whether it was steered into an opening: the engine spaces them. */
  const [steered, setSteered] = useState<boolean[]>([]);
  const [pick, setPick] = useState<Recommendation | null>(() => recommendNow(useStore.getState(), [], []));
  /** Bumped per round so the Run mounts fresh. */
  const [round, setRound] = useState(1);

  /**
   * A round is remembered at its first ending, for the brake and the spacing.
   * The reveal is worth reading, so starting the next waits on a tap.
   */
  const roundOver = () => {
    if (!pick) return;
    const state = useStore.getState();
    setRecent((played) => [...played, pick.focus]);
    setSteered((steers) => [...steers, isSteered(pick, state.settings.selection)]);
  };

  /**
   * The next round, picked when it starts rather than when the last one
   * ended: a line kept at the reveal, or grown from its offer, is in the
   * repertoire by then, and a line never run is what a Test asks for first.
   * With nothing left to pick, this lands on the way to Growth.
   */
  const advance = () => {
    setPick(recommendNow(useStore.getState(), recent, steered));
    setRound((n) => n + 1);
  };

  if (!pick) return <NothingToDrill onExit={onExit} onGrow={onGrow} />;

  return (
    <OpeningRunScreen
      key={round}
      auto
      plan={planFor(pick)}
      onRoundOver={roundOver}
      onNext={advance}
      onExit={onExit}
    />
  );
}

/** Nothing prepared inside the selection: the way to a round is through Growth. */
function NothingToDrill({ onExit, onGrow }: { onExit: () => void; onGrow: () => void }) {
  const selection = useStore((s) => s.settings.selection);
  return (
    <>
      <AppBar title="Autopilot" subtitle={selectionText(selection.color, selection.opening)} onClose={onExit} />
      <div className="screen no-nav">
        <SelectionBar />
        <div className="empty">
          <div className="t">Nothing to drill yet</div>
          <div className="h">
            Autopilot runs the lines you have, and there are none here. Build one in Growth, keep
            one at the end of a Run, or save the opening from a game in Play.
          </div>
        </div>
        <button className="btn primary block xl" onClick={onGrow}>
          Open Growth
          <Icons.next size={18} />
        </button>
      </div>
    </>
  );
}
