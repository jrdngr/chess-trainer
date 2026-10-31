import { useEffect, useMemo, useState } from 'react';
import { AppBar, Icons } from '../../components/ui';
import { SelectionBar, selectionText } from '../../components/Selection';
import { autopilotModes } from '../../model/autopilotPrefs';
import { startKind, survivalPlanFor } from '../../model/autopilot';
import type { Selection } from '../../model/selection';
import type { TidyFind } from '../../model/tidy';
import { useStore } from '../../store/useStore';
import { afterRound, NO_HISTORY, pickRound, playedRound, type AutoHistory, type PickedRound } from '../../store/recommendation';
import { SurvivalScreen } from '../survival/SurvivalScreen';
import { ModePrefsProvider } from '../modePrefs';

/**
 * Autopilot.
 *
 * Every round is a Survival run, set up by Autopilot — the opening, the side,
 * where it starts (see `autopilot.ts`) — and played on Autopilot's own
 * options. Its end screen offers Next round right under the board, and a run
 * that reached the end of your prep offers to grow the line there, one batch
 * of Growth before the next round: no Home in between, no setup screens, one
 * tap per round. A session never ends on its own. Stop is the close button in
 * the app bar, and stopping goes Home.
 *
 * With nothing prepared inside the selection there is nothing to practice,
 * and it says so and points at Growth.
 */
export function AutopilotScreen({
  onExit,
  onGrow,
  onAnalyze,
  onTidy,
  scope,
}: {
  onExit: () => void;
  /** Leave for the Analysis tab on a round's line, seen from your side. */
  onAnalyze: (sans: string[], side: 'w' | 'b') => void;
  /** Leave for Tidy, open on a move off your prep that was closer to your lines. */
  onTidy?: (find: TidyFind) => void;
  onGrow: () => void;
  /**
   * One opening to hold the session to, in place of the saved selection: what
   * Growth sends you to practice. Nothing is saved, so the next Autopilot is
   * back on your own selection.
   */
  scope?: Selection;
}) {
  const [history, setHistory] = useState<AutoHistory>(NO_HISTORY);
  /**
   * The round, and the selection it plays in: the scope, or the saved one
   * with "Any favorite" resolved per round — see `pickRound`.
   */
  const [picked, setPicked] = useState<PickedRound>(() => pickRound(useStore.getState(), NO_HISTORY, scope));
  const { round, within } = picked;
  /**
   * Once a round is under way the next lands on another favorite, even if
   * this session stops here.
   */
  useEffect(() => {
    if (!scope) playedRound(picked.within);
    // Where it started counts toward where the next ones start, across sessions.
    if (picked.round) useStore.getState().noteStart(startKind(picked.round));
  }, [scope, picked]);
  /** Autopilot's own options, and the fixed ones every round plays on; never a mode's setup. */
  const autopilotPrefs = useStore((s) => s.settings.autopilot);
  const modes = useMemo(() => autopilotModes(autopilotPrefs), [autopilotPrefs]);
  /** Bumped per round so each mounts fresh. */
  const [count, setCount] = useState(1);

  /**
   * The next round, picked when it starts rather than when the last one
   * ended: what the round just played changed — a line finished clean, a
   * card graded, a move grown — is in the store by then.
   */
  const advance = () => {
    if (!round) return;
    const played = afterRound(history, round, within);
    setHistory(played);
    setPicked(pickRound(useStore.getState(), played, scope));
    setCount((n) => n + 1);
  };

  if (!round) return <NothingToDrill onExit={onExit} onGrow={onGrow} />;

  return (
    <ModePrefsProvider value={modes}>
      <SurvivalScreen
        key={count}
        plan={survivalPlanFor(round.pick, round.at)}
        scope={within}
        onNext={advance}
        onExit={onExit}
        onAnalyze={onAnalyze}
        onTidy={onTidy}
      />
    </ModePrefsProvider>
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
          <div className="t">Nothing to practice yet</div>
          <div className="h">Build a line in Growth.</div>
        </div>
        <button className="btn primary block xl" onClick={onGrow}>
          Open Growth
          <Icons.next size={18} />
        </button>
      </div>
    </>
  );
}
