import { useMemo, useState } from 'react';
import { DrillSession } from './DrillSession';
import { Setup } from './Setup';
import type { DrillPrefs } from '../../model/modes';
import { itemsInRegion, regionOf, repertoiresIn } from '../../model/selection';
import { nodeById, openingTree } from '../../model/openingTree';
import type { GamePlan, GameSummary } from '../../model/autopilot';
import { referenceIndex } from '../../model/referenceIndex';
import { itemsFor, repertoireList, useStore } from '../../store/useStore';

export interface DrillScreenProps {
  /** Skip setup and drill on the saved options — started automatically. */
  auto?: boolean;
  /** What Autopilot decided: the side, and the opening to drill. */
  plan?: GamePlan;
  /** Answers per game, for an automatic session. */
  limit?: number;
  onGameOver?: (summary: GameSummary) => void;
  onExit: () => void;
}

/** Setup, then the session it describes — the shape every mode now takes. */
export function DrillScreen({ auto, plan, limit, onGameOver, onExit }: DrillScreenProps) {
  const state = useStore();
  const reps = repertoireList(state);
  const selection = state.settings.selection;
  const tree = openingTree(referenceIndex());
  const region = plan ? nodeById(tree, plan.steer) : regionOf(tree, selection);
  const color = plan?.color ?? selection.color;
  const [running, setRunning] = useState<DrillPrefs | null>(() =>
    auto ? { ...state.settings.drill, ...(plan ? { clock: 'move10' as const } : {}) } : null,
  );

  const items = useMemo(() => {
    if (!running) return [];
    return itemsInRegion(tree, region, repertoiresIn(reps, color).flatMap(itemsFor));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [running, reps, color, region]);

  if (!running) return <Setup onStart={setRunning} onExit={onExit} />;

  return (
    <DrillSession
      items={items}
      mode={running.draw}
      title="Drill"
      prefs={running}
      openingId={region.id}
      limit={limit}
      onGameOver={onGameOver}
      // A session nobody set up has no setup screen to fall back to, so leaving
      // it goes where it came from.
      onExit={() => (auto ? onExit() : setRunning(null))}
    />
  );
}
