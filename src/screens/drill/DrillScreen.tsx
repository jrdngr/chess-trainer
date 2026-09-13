import { useMemo, useState } from 'react';
import { DrillSession } from './DrillSession';
import { Setup } from './Setup';
import type { DrillPrefs } from '../../model/modes';
import { itemsInRegion, regionOf, repertoiresIn } from '../../model/selection';
import { openingTree } from '../../model/openingTree';
import { referenceIndex } from '../../model/referenceIndex';
import { itemsFor, repertoireList, useStore } from '../../store/useStore';

export interface DrillScreenProps {
  /** Skip setup and drill on the saved options — started automatically. */
  auto?: boolean;
  /** Options the recommendation decided, which outrank the saved ones. */
  plan?: Partial<DrillPrefs>;
  onExit: () => void;
}

/** Setup, then the session it describes — the shape every mode now takes. */
export function DrillScreen({ auto, plan, onExit }: DrillScreenProps) {
  const state = useStore();
  const reps = repertoireList(state);
  const selection = state.settings.selection;
  const [running, setRunning] = useState<DrillPrefs | null>(() =>
    auto ? { ...state.settings.drill, ...plan } : null,
  );

  const items = useMemo(() => {
    if (!running) return [];
    const tree = openingTree(referenceIndex());
    return itemsInRegion(
      tree,
      regionOf(tree, selection),
      repertoiresIn(reps, selection.color).flatMap(itemsFor),
    );
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [running, reps, selection.color, selection.opening]);

  if (!running) return <Setup onStart={setRunning} onExit={onExit} />;

  return (
    <DrillSession
      items={items}
      mode={running.draw}
      title="Drill"
      prefs={running}
      // A session nobody set up has no setup screen to fall back to, so leaving
      // it goes where it came from.
      onExit={() => (auto ? onExit() : setRunning(null))}
    />
  );
}
