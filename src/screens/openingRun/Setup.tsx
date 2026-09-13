import { AppBar, Section, Segmented, Toggle } from '../../components/ui';
import { SelectionBar } from '../../components/Selection';
import {
  clockLabel,
  CLOCK_MODES,
  HINT_BUDGETS,
  NEW_MOVE_BUDGETS,
  steerLabel,
  STEERS,
  type OpeningRunOptions,
} from '../../model/openingRun';
import { useStore } from '../../store/useStore';
import { Record } from './Record';

/**
 * The screen that decides a run. Start sits at the top, above the options, so
 * the common case — same rules as last time — is one tap. The side and the
 * opening are the global selection above it; everything here is off by
 * default, and the plain run is a popular line in your opening, nothing
 * added, no clock, no help. Autopilot sets the same two levers — what the
 * opponent steers toward, and how many moves a run may add — for itself.
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

        <Section title="Steer toward" />
        <Segmented
          value={prefs.steer}
          options={STEERS.map((steer) => ({ value: steer, label: steerLabel(steer) }))}
          onChange={(steer) => setOpeningRunPrefs({ steer })}
        />
        <div className="note">
          {prefs.steer === 'weak'
            ? 'Lines through positions you get wrong, have let lapse, or lost in your own games.'
            : prefs.steer === 'gaps'
              ? 'The opponent walks you to a reply you have no answer to.'
              : 'Your lines, as often as you would actually meet them.'}
        </div>

        <Section title="New moves" />
        <Segmented
          value={String(prefs.newMoves)}
          options={NEW_MOVE_BUDGETS.map((n) => ({ value: String(n), label: String(n) }))}
          onChange={(n) => setOpeningRunPrefs({ newMoves: Number(n) })}
        />
        <div className="note">
          {prefs.newMoves === 0
            ? 'None: a run is complete where your prep ends.'
            : `Where your prep ends, the book is offered and the move you choose becomes prep, up to ${prefs.newMoves} time${prefs.newMoves === 1 ? '' : 's'}.`}
        </div>

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
