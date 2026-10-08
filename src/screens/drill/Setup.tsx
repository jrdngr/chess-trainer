import { AppBar, Section, Segmented, Stepper, Toggle } from '../../components/ui';
import { SelectionBar } from '../../components/Selection';
import { DRAW_LABELS, FORM_LABELS, type DrillDraw, type DrillPrefs } from '../../model/modes';
import { drillableLines, dueLines } from '../../model/lineDrill';
import { clockLabel, CLOCK_MODES } from '../../model/openingRun';
import { itemsInRegion, repertoiresIn } from '../../model/selection';
import { acrossRegions, isAnyFavorite, regionsBySide } from '../../model/anyFavorite';
import { openingTree } from '../../model/openingTree';
import { referenceIndex } from '../../model/referenceIndex';
import { DAY, forecast, masteryBuckets, retention } from '../../model/srs';
import { itemsFor, repertoireList, useStore } from '../../store/useStore';

const FORMS = (['lines', 'positions'] as const).map((value) => ({ value, label: FORM_LABELS[value] }));

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
  const regions = regionsBySide(tree, selection, state.settings.favoriteOpenings);
  const inScope = repertoiresIn(repertoireList(state), selection.color);
  const items = acrossRegions(regions, inScope, (rep, node) => itemsInRegion(tree, node, itemsFor(rep)), (i) => i.cardId);
  const lineList = acrossRegions(regions, inScope, (rep, node) => drillableLines(rep, tree, node), (l) => `${l.repertoireId}:${l.tipId}`);
  const lines = lineList.length;
  const due = dueLines(lineList, state.lineCards).length;
  const lineMode = prefs.form === 'lines';
  const empty = lineMode ? lines === 0 : items.length === 0;

  // The schedule of the position cards in scope: what comes due this week, and
  // where each card stands.
  const now = Date.now();
  const cards = items.map((i) => state.cards[i.cardId]).filter(Boolean);
  const week = forecast(cards, 7, now);
  const weekTotal = week.reduce((a, b) => a + b, 0);
  const maxWeek = Math.max(1, ...week);
  const mastery = masteryBuckets(cards);
  const unseen = items.length - cards.length + mastery.unseen;
  const ret = retention(cards);

  const set = (patch: Partial<DrillPrefs>) => setModePrefs('drill', patch);

  return (
    <>
      <AppBar title="Drill" onClose={onExit} />

      <div className="screen no-nav">
        <SelectionBar />

        <button
          className="btn primary block xl"
          disabled={empty}
          onClick={() => onStart(prefs)}
        >
          {empty ? 'Nothing prepared here' : 'Start'}
        </button>
        <div className="note center">
          {lineMode
            ? lines === 1
              ? '1 line'
              : `${lines} lines`
            : items.length === 1
              ? '1 position'
              : `${items.length} positions`}{' '}
          in {isAnyFavorite(selection) ? 'your favorites' : regions[0].node.depth === 0 ? 'your repertoire' : regions[0].node.name}
          {lineMode && due > 0 ? ` · ${due} due` : ''}
        </div>

        <Section title="Drill" />
        <Segmented value={prefs.form} options={FORMS} onChange={(form) => set({ form })} />

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
          {!lineMode && (
            <Stepper
              label="New per session"
              value={prefs.newPerSession}
              min={0}
              max={40}
              step={2}
              onChange={(newPerSession) => set({ newPerSession })}
            />
          )}
          {!lineMode && (
            <Toggle
              label="Follow the line"
              hint="Keep going after a correct move instead of stopping at one answer"
              on={prefs.followLine}
              onToggle={() => set({ followLine: !prefs.followLine })}
            />
          )}
          <Toggle
            label="Weakest first"
            hint={
              lineMode
                ? 'Draw the lines you grade lowest rather than the ones strong players choose most'
                : 'Ask what you keep getting wrong before what is merely due'
            }
            on={prefs.weakFirst}
            onToggle={() => set({ weakFirst: !prefs.weakFirst })}
          />
          {lineMode && (
            <Toggle
              label="Batch similar lines"
              hint="Drill a few lines that share most of their moves, then move on to another group"
              on={prefs.batchSimilar}
              onToggle={() => set({ batchSimilar: !prefs.batchSimilar })}
            />
          )}
          <Toggle
            label="Explain mistakes"
            hint="Offer the engine's refutation after a wrong move"
            on={prefs.explain}
            onToggle={() => set({ explain: !prefs.explain })}
          />
        </div>

        <Section title="This week" aside={`${weekTotal} reviews`} />
        <div className="card">
          <div className="forecast">
            {week.map((count, i) => (
              <div className="day" key={i}>
                <div
                  className={`bar${i === 0 ? ' today' : ''}`}
                  style={{ height: `${Math.max(4, (count / maxWeek) * 100)}%` }}
                  title={`${count}`}
                />
                <div className="lbl">{i === 0 ? 'Now' : dayLabel(now + i * DAY)}</div>
              </div>
            ))}
          </div>
        </div>

        <Section
          title="Mastery"
          aside={ret === null ? `${items.length} positions` : `${Math.round(ret * 100)}% recall`}
        />
        <div className="card">
          <div className="bar-stack">
            <i style={{ width: `${pct(mastery.mature, items.length)}%`, background: 'var(--good)' }} />
            <i style={{ width: `${pct(mastery.young, items.length)}%`, background: '#7dd3fc' }} />
            <i style={{ width: `${pct(mastery.learning, items.length)}%`, background: 'var(--warn)' }} />
            <i style={{ width: `${pct(unseen, items.length)}%`, background: 'var(--surface-3)' }} />
          </div>
          <div className="pills mt-12">
            <span className="pill"><i style={{ background: 'var(--good)' }} /><b>{mastery.mature}</b> mature</span>
            <span className="pill"><i style={{ background: '#7dd3fc' }} /><b>{mastery.young}</b> young</span>
            <span className="pill"><i style={{ background: 'var(--warn)' }} /><b>{mastery.learning}</b> learning</span>
            <span className="pill"><i style={{ background: 'var(--surface-3)' }} /><b>{unseen}</b> unseen</span>
          </div>
        </div>
      </div>
    </>
  );
}

function pct(n: number, total: number) {
  return total ? (n / total) * 100 : 0;
}

function dayLabel(ts: number) {
  return new Date(ts).toLocaleDateString(undefined, { weekday: 'narrow' });
}
