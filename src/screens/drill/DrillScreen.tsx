import { useMemo, useState } from 'react';
import { DrillSession } from './DrillSession';
import { Setup } from './Setup';
import type { DrillPrefs } from '../../model/modes';
import { itemsInRegion, regionOf, repertoiresIn } from '../../model/selection';
import { openingTree } from '../../model/openingTree';
import { referenceIndex } from '../../model/referenceIndex';
import { itemsFor, repertoireList, useStore } from '../../store/useStore';

export interface DrillScreenProps {
  onExit: () => void;
}

/** Setup, then the session it describes — the shape every mode takes. */
export function DrillScreen({ onExit }: DrillScreenProps) {
  const state = useStore();
  const reps = repertoireList(state);
  const selection = state.settings.selection;
  const tree = openingTree(referenceIndex());
  const region = regionOf(tree, selection);
  const color = selection.color;
  const [running, setRunning] = useState<DrillPrefs | null>(null);

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
      onExit={() => setRunning(null)}
    />
  );
}
