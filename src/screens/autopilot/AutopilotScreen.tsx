import { useState } from 'react';
import { AppBar, Icons } from '../../components/ui';
import { SelectionBar, selectionText } from '../../components/Selection';
import { planFor, type RatingChange, type RoundSummary } from '../../model/autopilot';
import { isSteered, type Focus, type Recommendation } from '../../model/recommend';
import { useStore } from '../../store/useStore';
import { recommendNow } from '../../store/recommendation';
import { OpeningRunScreen } from '../openingRun/OpeningRunScreen';
import { deltaText } from '../../components/ScoreBar';

/**
 * Autopilot.
 *
 * Every round is a Run of what you already have. The engine picks the
 * opening, the colour and what the opponent steers toward, and the Run
 * plays it. When a round ends, a bar over its reveal shows what it did to
 * the rating and offers the next one: no Home in between, no setup screens,
 * one tap per round. The settings are the engine's business and nothing on screen
 * names them. A session never ends on its own. Stop is the close button in
 * the app bar, and stopping opens Stats.
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
  const [over, setOver] = useState<RoundSummary | null>(null);
  const [next, setNext] = useState<Recommendation | null>(null);

  /** A round ends on its reveal, which is worth reading, so the next waits on a tap. */
  const roundOver = (summary: RoundSummary) => {
    if (!pick) return;
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

  if (!pick) return <NothingToDrill onExit={onExit} onGrow={onGrow} />;

  return (
    <>
      <OpeningRunScreen key={round} auto plan={planFor(pick)} onRoundOver={roundOver} onExit={onExit} />
      {over && next && <NextBar moved={over.moved} perfect={over.perfect} onNext={advance} />}
    </>
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

/**
 * What the round did to your rating, and one button: the next round. The
 * opening shown is the most specific one the round moved, since that is what
 * the round was about. A round can move nothing — it answered no prepared
 * position, or none of the openings it went through is starred — and then the
 * bar says so rather than naming a number that did not change.
 */
function NextBar({ moved, perfect, onNext }: { moved: RatingChange[]; perfect: boolean; onNext: () => void }) {
  const narrowest = moved.length ? moved[moved.length - 1] : null;
  return (
    <div className={`next-bar${perfect ? ' perfect' : ''}${narrowest && narrowest.delta < 0 ? ' lost' : ''}`}>
      <div className="earned">
        <span className="pts num">{narrowest ? deltaText(narrowest.delta) : '—'}</span>
        <span className="lbl truncate">{narrowest ? narrowest.name : 'No rating change'}</span>
      </div>
      <button className="go" onClick={onNext}>
        <span className="what grow">Next Round</span>
        <Icons.next size={20} />
      </button>
    </div>
  );
}
