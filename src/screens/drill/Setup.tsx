import { AppBar, Section, Segmented, Stepper, Toggle } from '../../components/ui';
import {
  DRAW_LABELS,
  drawDescription,
  type DrillDraw,
  type DrillPrefs,
} from '../../model/modes';
import { countDue } from '../../model/srs';
import type { Color } from '../../chess/core';
import type { Card } from '../../model/types';
import { itemsFor, repertoireList, useStore } from '../../store/useStore';

const SIDES: { value: Color | 'both'; label: string }[] = [
  { value: 'both', label: 'Both' },
  { value: 'w', label: 'White' },
  { value: 'b', label: 'Black' },
];

const DRAWS = (['due', 'new', 'cram'] as const).map((value) => ({
  value,
  label: DRAW_LABELS[value],
}));

/**
 * What a drill session will consist of, decided before it starts.
 *
 * Start sits at the top: the common case is the same practice as last time,
 * which should be one tap. What follows narrows the material, then changes how
 * it is asked.
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
  const reps = repertoireList(state);

  const set = (patch: Partial<DrillPrefs>) => setModePrefs('drill', patch);

  const inScope = reps.filter((rep) => prefs.side === 'both' || rep.color === prefs.side);
  const items = inScope.flatMap(itemsFor);
  const ready = readyCount(items.map((i) => state.cards[i.cardId]), items.length, prefs);

  return (
    <>
      <AppBar title="Drill" subtitle="Answer until you want to stop." onClose={onExit} />

      <div className="screen no-nav">
        <button
          className="btn primary block xl"
          disabled={items.length === 0}
          onClick={() => onStart(prefs)}
        >
          {items.length === 0 ? 'Nothing in scope' : 'Start'}
        </button>
        <div className="note center">
          {items.length === 0
            ? 'Widen the scope below, or prepare an opening for that side.'
            : ready === 0
              ? `Nothing due. ${items.length} positions to practise anyway.`
              : `${ready} ${ready === 1 ? 'position' : 'positions'} ready of ${items.length}.`}
        </div>

        <Section title="Draw from" />
        <Segmented
          value={prefs.draw}
          options={DRAWS}
          onChange={(draw) => set({ draw: draw as DrillDraw })}
        />
        <div className="note">{drawDescription(prefs.draw)}</div>

        <Section title="Side" />
        <Segmented value={prefs.side} options={SIDES} onChange={(side) => set({ side })} />
        <div className="note">
          {prefs.side === 'both'
            ? 'Everything you have prepared, whichever side you are on.'
            : `Only the lines you play as ${prefs.side === 'w' ? 'White' : 'Black'}.`}
        </div>

        {reps.length > 0 && (
          <>
            <Section title="What you have" />
            <div className="list">
              {reps.map((rep) => (
                <div className="list-row kv" key={rep.id}>
                  <span className={`side ${rep.color}`} />
                  <span className="k grow">{rep.color === 'w' ? 'As White' : 'As Black'}</span>
                  <span className="v num">{itemsFor(rep).length}</span>
                </div>
              ))}
            </div>
          </>
        )}

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
        <div className="note">
          {prefs.weakFirst
            ? 'Positions you have lapsed on come first. Harder, and the fastest way to stop losing the same line twice.'
            : 'The schedule decides the order — most overdue first.'}
        </div>
      </div>
    </>
  );
}

/** How much of the scope a session would actually have to ask about now. */
function readyCount(cards: (Card | undefined)[], total: number, prefs: DrillPrefs): number {
  const known = cards.filter((card): card is Card => !!card);
  if (prefs.draw === 'cram') return total;
  const unseen = total - known.length;
  if (prefs.draw === 'new') return Math.min(unseen, prefs.newPerSession);
  return countDue(known).due + Math.min(unseen, prefs.newPerSession);
}
