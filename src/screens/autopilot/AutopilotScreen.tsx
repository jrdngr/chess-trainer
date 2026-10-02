import { useMemo, useState } from 'react';
import { AppBar, Icons } from '../../components/ui';
import { SelectionBar, selectionText } from '../../components/Selection';
import { ROUND_SIZE, survivalPlanFor } from '../../model/autopilot';
import { nodeById, openingTree } from '../../model/openingTree';
import { referenceIndex } from '../../model/referenceIndex';
import { itemsInRegion, repertoiresIn, type Selection } from '../../model/selection';
import type { TidyFind } from '../../model/tidy';
import { itemsFor, repertoireList, useStore } from '../../store/useStore';
import { afterRound, nextRound, NO_HISTORY, withSelection, type AutoHistory, type AutoRound } from '../../store/recommendation';
import { DrillSession } from '../drill/DrillSession';
import { LineDrill } from '../drill/LineDrill';
import { GrowthScreen } from '../growth/GrowthScreen';
import { SurvivalScreen } from '../survival/SurvivalScreen';

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
  const [round, setRound] = useState<AutoRound | null>(() =>
    nextRound(withSelection(useStore.getState(), scope), NO_HISTORY),
  );
  /** Bumped per round so each mounts fresh. */
  const [count, setCount] = useState(1);

  /**
   * The next round, picked when it starts rather than when the last one
   * ended: what the round just played changed — a line finished clean, a
   * card graded, a move grown — is in the store by then.
   */
  const advance = () => {
    if (!round) return;
    const state = withSelection(useStore.getState(), scope);
    const played = afterRound(history, round, state.settings.selection);
    setHistory(played);
    setRound(nextRound(state, played));
    setCount((n) => n + 1);
  };

  if (!round) return <NothingToDrill onExit={onExit} onGrow={onGrow} />;

  switch (round.mode) {
    case 'survival':
      return (
        <SurvivalScreen
          key={count}
          plan={survivalPlanFor(round.pick)}
          scope={scope}
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
          color={round.color}
          openingId={round.openingId}
          count={ROUND_SIZE.drillLines}
          lean="weak"
          only={new Set(round.only)}
          prefs={useStore.getState().settings.drill}
          onExit={onExit}
          onNext={advance}
        />
      );
    case 'drillPositions':
      return <PositionsRound key={count} round={round} onExit={onExit} onNext={advance} />;
    case 'growth':
      return (
        <GrowthScreen
          key={count}
          onExit={onExit}
          onAnalyze={onAnalyze}
          launch={{
            row: round.launch.row,
            hole: round.launch.hole,
            region: round.launch.opening.id,
            backLabel: 'Next round',
            onBack: advance,
            pointBack: 'cap',
            widened: round.launch.widened,
            next: advance,
          }}
        />
      );
  }
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
    return itemsInRegion(tree, nodeById(tree, round.openingId), reps.flatMap(itemsFor));
  });
  const prefs = useMemo(() => ({ ...state.settings.drill, draw: 'due' as const }), [state.settings.drill]);
  return (
    <DrillSession
      items={items}
      mode="due"
      title="Drill"
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
