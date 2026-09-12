import { useMemo, useState } from 'react';
import { DrillSession } from './DrillSession';
import { Setup } from './Setup';
import type { DrillPrefs } from '../../model/modes';
import { displayName } from '../../model/repertoire';
import { itemsFor, repertoireList, useStore } from '../../store/useStore';

export interface DrillScreenProps {
  onExit: () => void;
}

/** Setup, then the session it describes — the shape every mode now takes. */
export function DrillScreen({ onExit }: DrillScreenProps) {
  const state = useStore();
  const [running, setRunning] = useState<DrillPrefs | null>(null);
  const reps = repertoireList(state);

  const items = useMemo(() => {
    if (!running) return [];
    return reps
      .filter(
        (rep) =>
          (running.repertoireId === '' || rep.id === running.repertoireId) &&
          (running.side === 'both' || rep.color === running.side),
      )
      .flatMap(itemsFor);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [running, reps]);

  if (!running) return <Setup onStart={setRunning} onExit={onExit} />;

  // The bar says what is being drilled, so a narrowed session is never a
  // mystery once you are three positions into it.
  const chosen = reps.find((rep) => rep.id === running.repertoireId);
  const side = running.side === 'w' ? 'White' : running.side === 'b' ? 'Black' : null;
  const title = chosen ? displayName(chosen.name) : side ? `Drill · ${side}` : 'Drill';

  return (
    <DrillSession
      items={items}
      mode={running.draw}
      title={title}
      prefs={running}
      onExit={() => setRunning(null)}
    />
  );
}
