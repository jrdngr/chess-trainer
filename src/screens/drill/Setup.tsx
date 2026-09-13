import { AppBar, Section, Segmented, Stepper, Toggle } from '../../components/ui';
import { SelectionBar } from '../../components/Selection';
import { DRAW_LABELS, type DrillDraw, type DrillPrefs } from '../../model/modes';
import { clockLabel, CLOCK_MODES } from '../../model/openingRun';
import { itemsInRegion, regionOf, repertoiresIn } from '../../model/selection';
import { openingTree } from '../../model/openingTree';
import { referenceIndex } from '../../model/referenceIndex';
import { itemsFor, repertoireList, useStore } from '../../store/useStore';

const DRAWS = (['due', 'new', 'cram'] as const).map((value) => ({
  value,
  label: DRAW_LABELS[value],
}));

/**
 * What a drill session will consist of, decided before it starts.
 *
 * Start sits at the top: the common case is the same practice as last time,
 * which should be one tap. The side and the opening come from the selection
 * above it; what follows changes how the positions are asked.
 */
export function Setup({
  onStart,
  onExit,
}: {
  onStart: (prefs: DrillPrefs) => void;
  onExit: () => void;
}) {
  const state = useStore();
  const setModePrefs = useStore((s) => s.setModePrefs);
  const prefs = state.settings.drill;
  const selection = state.settings.selection;
  const tree = openingTree(referenceIndex());
  const node = regionOf(tree, selection);
  const inScope = repertoiresIn(repertoireList(state), selection.color);
  const items = itemsInRegion(tree, node, inScope.flatMap(itemsFor));

  const set = (patch: Partial<DrillPrefs>) => setModePrefs('drill', patch);

  return (
    <>
      <AppBar title="Drill" onClose={onExit} />

      <div className="screen no-nav">
        <SelectionBar />

        <button
          className="btn primary block xl"
          disabled={items.length === 0}
          onClick={() => onStart(prefs)}
        >
          {items.length === 0 ? 'Nothing prepared here' : 'Start'}
        </button>
        <div className="note center">
          {items.length === 1 ? '1 position' : `${items.length} positions`} in{' '}
          {node.depth === 0 ? 'your repertoire' : node.name}
        </div>

        <Section title="Draw from" />
        <Segmented
          value={prefs.draw}
          options={DRAWS}
          onChange={(draw) => set({ draw: draw as DrillDraw })}
        />

        <Section title="Clock" />
        <Segmented
          value={prefs.clock}
          options={CLOCK_MODES.map((mode) => ({ value: mode, label: clockLabel(mode) }))}
          onChange={(clock) => set({ clock })}
        />

        <Section title="How it asks" />
        <div className="list">
          <Stepper
            label="New per session"
            value={prefs.newPerSession}
            min={0}
            max={40}
            step={2}
            onChange={(newPerSession) => set({ newPerSession })}
          />
          <Toggle
            label="Follow the line"
            hint="Keep going after a correct move instead of stopping at one answer"
            on={prefs.followLine}
            onToggle={() => set({ followLine: !prefs.followLine })}
          />
          <Toggle
            label="Weakest first"
            hint="Ask what you keep getting wrong before what is merely due"
            on={prefs.weakFirst}
            onToggle={() => set({ weakFirst: !prefs.weakFirst })}
          />
          <Toggle
            label="Explain mistakes"
            hint="Offer the engine's refutation after a wrong move"
            on={prefs.explain}
            onToggle={() => set({ explain: !prefs.explain })}
          />
        </div>
      </div>
    </>
  );
}
