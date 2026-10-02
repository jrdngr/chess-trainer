import { useMemo, useState } from 'react';
import { DrillSession } from './DrillSession';
import { LineDrill } from './LineDrill';
import { drillableLines } from '../../model/lineDrill';
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

  /** A line has one side: with either selected, one is picked per visit, among the sides you have lines for. */
  const lineColor = useMemo(() => {
    if (!running || running.form !== 'lines') return null;
    if (color !== 'random') return color;
    const sides = repertoiresIn(reps, color)
      .filter((rep) => drillableLines(rep, tree, region).length > 0)
      .map((rep) => rep.color);
    return sides[Math.floor(Math.random() * sides.length)] ?? 'w';
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [running]);

  if (!running) return <Setup onStart={setRunning} onExit={onExit} />;

  if (lineColor) {
    return (
      <LineDrill
        color={lineColor}
        openingId={region.id}
        lean={running.weakFirst ? 'weak' : 'popular'}
        prefs={running}
        onExit={onExit}
      />
    );
  }

  return (
    <DrillSession
      items={items}
      mode={running.draw}
      title="Drill"
      prefs={running}
      openingId={region.id}
      onExit={onExit}
    />
  );
}
