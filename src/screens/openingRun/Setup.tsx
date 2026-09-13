import { AppBar, Section, Segmented, Toggle } from '../../components/ui';
import { SelectionBar } from '../../components/Selection';
import {
  clockLabel,
  CLOCK_MODES,
  HINT_BUDGETS,
  type OpeningRunOptions,
} from '../../model/openingRun';
import { useStore } from '../../store/useStore';
import { Record } from './Record';

/**
 * The screen that decides a run. Start sits at the top, above the options, so
 * the common case — same rules as last time — is one tap. The side and the
 * opening are the global selection above it; everything here is off by
 * default, and the plain run is a line in your opening, no clock, no help.
 */
export function Setup({
  onStart,
  onExit,
}: {
  onStart: (options: OpeningRunOptions) => void;
  onExit: () => void;
}) {
  const prefs = useStore((s) => s.settings.openingRun);
  const setOpeningRunPrefs = useStore((s) => s.setOpeningRunPrefs);
  const record = useStore((s) => s.openingRun);

  return (
    <>
      <AppBar title="Run" onClose={onExit} />

      <div className="screen no-nav">
        <SelectionBar />

        <button className="btn primary block xl" onClick={() => onStart(prefs)}>
          Start
        </button>

        <Section title="Clock" />
        <Segmented
          value={prefs.clock}
          options={CLOCK_MODES.map((mode) => ({ value: mode, label: clockLabel(mode) }))}
          onChange={(clock) => setOpeningRunPrefs({ clock })}
        />

        <Section title="Hints" />
        <Segmented
          value={String(prefs.hints)}
          options={HINT_BUDGETS.map((n) => ({
            value: String(n),
            label: n === 0 ? 'None' : `${n} hint${n === 1 ? '' : 's'}`,
          }))}
          onChange={(n) => setOpeningRunPrefs({ hints: Number(n) })}
        />

        <Section title="Extras" />
        <div className="list">
          <Toggle
            label="Target weak spots"
            hint="Draw lines you get wrong or have let lapse more often"
            on={prefs.weakFirst}
            onToggle={() => setOpeningRunPrefs({ weakFirst: !prefs.weakFirst })}
          />
          <Toggle
            label="Extended mode"
            hint="When the prep runs out, keep going while the engine calls your moves sound"
            on={prefs.extended}
            onToggle={() => setOpeningRunPrefs({ extended: !prefs.extended })}
          />
        </div>

        {record.runs > 0 && <Record record={record} />}
      </div>
    </>
  );
}
