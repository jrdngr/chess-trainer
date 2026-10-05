import { createContext, useContext, type ReactNode } from 'react';
import type { ModePrefs } from '../model/autopilotPrefs';
import { useStore } from '../store/useStore';

/**
 * Which options a mode's screen plays on. Opened on its own, a mode plays on
 * its saved setup; inside Autopilot, on Autopilot's — see `autopilotPrefs.ts`.
 * Screens read their options through `useModePrefs`, never off settings, so a
 * mode's setup cannot leak into an Autopilot round.
 */
const ModePrefsContext = createContext<ModePrefs | null>(null);

export function ModePrefsProvider({ value, children }: { value: ModePrefs; children: ReactNode }) {
  return <ModePrefsContext.Provider value={value}>{children}</ModePrefsContext.Provider>;
}

export function useModePrefs(): ModePrefs {
  const override = useContext(ModePrefsContext);
  const survival = useStore((s) => s.settings.survival);
  const drill = useStore((s) => s.settings.drill);
  const growth = useStore((s) => s.settings.growth);
  return override ?? { survival, drill, growth };
}
