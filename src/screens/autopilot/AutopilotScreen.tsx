import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { AppBar, Icons } from '../../components/ui';
import { SelectionBar, selectionText } from '../../components/Selection';
import { AUTO_DRILL, autopilotModes } from '../../model/autopilotPrefs';
import { ROUND_SIZE, roundLabel, survivalPlanFor } from '../../model/autopilot';
import { nodeById, openingTree } from '../../model/openingTree';
import { referenceIndex } from '../../model/referenceIndex';
import { itemsInRegion, repertoiresIn, type Selection } from '../../model/selection';
import type { TidyFind } from '../../model/tidy';
import { itemsFor, repertoireList, useStore } from '../../store/useStore';
import { weakestFirst } from '../../model/session';
import { afterRound, NO_HISTORY, pickRound, playedRound, tookTest, type AutoHistory, type AutoRound, type PickedRound } from '../../store/recommendation';
import { DrillSession } from '../drill/DrillSession';
import { LineDrill } from '../drill/LineDrill';
import { LINE_BUDGET, MAX_LINES } from '../../model/lineDrill';
import { GrowthScreen } from '../growth/GrowthScreen';
import { SurvivalScreen } from '../survival/SurvivalScreen';
import { ModePrefsProvider } from '../modePrefs';

/**
 * Autopilot.
 *
 * Every round is a sitting of one mode — a Survival run, a few positions or
 * lines of Drill, a batch of Growth — chosen by what the work inside the
 * selection asks for, with Survival the default (see `autopilot.ts`). Each
 * round is the mode's own screen, set up by Autopilot and played on your own
 * saved options, and its end screen offers Next round right under the board:
 * no Home in between, no setup screens, one tap per round. A session never
 * ends on its own. Stop is the close button in the app bar, and stopping goes
 * Home.
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
   * with "Any favorite" resolved per round. Under Mode Testing, also the case
   * it plays — see `pickRound`.
   */
  const [picked, setPicked] = useState<PickedRound>(() => pickRound(useStore.getState(), NO_HISTORY, scope));
  const { round, within } = picked;
  /**
   * Once a round is under way the next lands on another favorite, and Mode
   * Testing's cycle moves on, even if this session stops here.
   */
  useEffect(() => {
    if (!scope) playedRound(picked.within);
    if (picked.test) tookTest(picked.test);
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

  const current = round;
  const screen = ((): ReactNode => {
    switch (current.mode) {
      case 'survival':
        return (
          <SurvivalScreen
            key={count}
            plan={survivalPlanFor(current.pick)}
            roundName={roundLabel('survival', current.pick.start)}
            scope={within}
            onNext={advance}
            onExit={onExit}
            onAnalyze={onAnalyze}
            onTidy={onTidy}
          />
        );
      case 'drillLines':
        return (
          <LineDrill
            key={count}
            color={current.color}
            openingId={current.openingId}
            count={MAX_LINES}
            budget={LINE_BUDGET}
            lean="weak"
            only={new Set(current.only)}
            prefs={AUTO_DRILL}
            onExit={onExit}
            onNext={advance}
          />
        );
      case 'drillPositions':
        return <PositionsRound key={count} round={current} onExit={onExit} onNext={advance} />;
      case 'growth':
        return (
          <GrowthScreen
            key={count}
            onExit={onExit}
            onAnalyze={onAnalyze}
            launch={{
              row: current.launch.row,
              hole: current.launch.hole,
              region: current.launch.opening.id,
              backLabel: 'Next round',
              onBack: advance,
              pointBack: 'cap',
              widened: current.launch.widened,
              next: advance,
            }}
          />
        );
    }
  })();

  return (
    <ModePrefsProvider value={modes}>
      {screen}
    </ModePrefsProvider>
  );
}

/** Drill's positions, the scheduled ones first, for a round's worth of answers. */
function PositionsRound({
  round,
  onExit,
  onNext,
}: {
  round: Extract<AutoRound, { mode: 'drillPositions' }>;
  onExit: () => void;
  onNext: () => void;
}) {
  const state = useStore.getState();
  const [items] = useState(() => {
    const tree = openingTree(referenceIndex());
    const reps = repertoiresIn(repertoireList(state), round.color);
    const all = itemsInRegion(tree, nodeById(tree, round.openingId), reps.flatMap(itemsFor));
    // Nothing due or new, but your prep is missing in Survival: the positions you answer worst.
    return round.weak ? weakestFirst(all, state.cards).slice(0, ROUND_SIZE.drillPositions * 2) : all;
  });
  const prefs = useMemo(() => ({ ...AUTO_DRILL, weakFirst: round.weak }), [round.weak]);
  return (
    <DrillSession
      items={items}
      mode={round.weak ? 'cram' : 'due'}
      title="Drill positions"
      prefs={prefs}
      openingId={round.openingId}
      limit={ROUND_SIZE.drillPositions}
      onExit={onExit}
      onNext={onNext}
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
