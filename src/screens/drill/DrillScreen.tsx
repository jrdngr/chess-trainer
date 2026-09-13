import { useMemo, useState } from 'react';
import { DrillSession } from './DrillSession';
import { Setup } from './Setup';
import type { DrillPrefs } from '../../model/modes';
import { drillDraw } from '../../model/nextUp';
import { countDue } from '../../model/srs';
import { itemsFor, repertoireList, useStore } from '../../store/useStore';

export interface DrillScreenProps {
  /** Skip setup and drill on the saved options — Next Up started this. */
  auto?: boolean;
  onExit: () => void;
}

/** Setup, then the session it describes — the shape every mode now takes. */
export function DrillScreen({ auto, onExit }: DrillScreenProps) {
  const state = useStore();
  const reps = repertoireList(state);
  const [running, setRunning] = useState<DrillPrefs | null>(() =>
    auto ? autoPrefs(state) : null,
  );

  const items = useMemo(() => {
    if (!running) return [];
    return reps
      .filter((rep) => running.side === 'both' || rep.color === running.side)
      .flatMap(itemsFor);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [running, reps]);

  if (!running) return <Setup onStart={setRunning} onExit={onExit} />;

  // The bar says what is being drilled, so a narrowed session is never a
  // mystery once you are three positions into it.
  const side = running.side === 'w' ? 'White' : running.side === 'b' ? 'Black' : null;
  const title = side ? `Drill · ${side}` : 'Drill';

  return (
    <DrillSession
      items={items}
      mode={running.draw}
      title={title}
      prefs={running}
      // A session nobody set up has no setup screen to fall back to, so leaving
      // it goes where it came from.
      onExit={() => (auto ? onExit() : setRunning(null))}
    />
  );
}

/**
 * The saved options, with the draw corrected if it would find nothing. Next Up
 * only sends you here when something is waiting; this makes sure the session
 * actually contains it.
 */
function autoPrefs(state: ReturnType<typeof useStore.getState>): DrillPrefs {
  const prefs = state.settings.drill;
  const items = repertoireList(state)
    .filter((rep) => prefs.side === 'both' || rep.color === prefs.side)
    .flatMap(itemsFor);
  const cards = items.map((item) => state.cards[item.cardId]).filter(Boolean);
  return { ...prefs, draw: drillDraw(prefs.draw, countDue(cards).due, items.length - cards.length) };
}
