import { AppBar, ChoiceRow, Section, Segmented, Toggle } from '../../components/ui';
import { LEVELS, OPENING_PLIES, type PlayPrefs } from '../../model/modes';
import { displayName } from '../../model/repertoire';
import type { ColorChoice } from '../../model/openingRun';
import { repertoireList, useStore } from '../../store/useStore';

const COLORS: { value: ColorChoice; label: string }[] = [
  { value: 'w', label: 'White' },
  { value: 'b', label: 'Black' },
  { value: 'random', label: 'Random' },
];

/** What kind of game, and what to keep from it. */
export function Setup({
  onStart,
  onExit,
}: {
  onStart: (prefs: PlayPrefs) => void;
  onExit: () => void;
}) {
  const state = useStore();
  const setModePrefs = useStore((s) => s.setModePrefs);
  const prefs = state.settings.play;
  const reps = repertoireList(state);

  const set = (patch: Partial<PlayPrefs>) => setModePrefs('play', patch);
  const target = reps.find((rep) => rep.id === prefs.repertoireId) ?? null;

  return (
    <>
      <AppBar title="Play" subtitle="A game against the engine." onClose={onExit} />

      <div className="screen no-nav">
        <button className="btn primary block xl" onClick={() => onStart(prefs)}>
          Start
        </button>

        <Section title="Play as" />
        <Segmented value={prefs.color} options={COLORS} onChange={(color) => set({ color })} />

        <Section title="Strength" />
        <Segmented
          value={prefs.level}
          options={LEVELS.map((l) => ({ value: l.id, label: l.name }))}
          onChange={(id) => set({ level: id })}
        />

        <Section title="Keeping the opening" />
        <div className="list">
          <Toggle
            label="Save the opening"
            hint={`Write the first ${OPENING_PLIES / 2} moves into your repertoire when the game ends`}
            on={prefs.save}
            onToggle={() => set({ save: !prefs.save })}
          />
          <Toggle
            label="Warn me off book"
            hint="Say so the moment you leave your own prep, and remember it for Repair"
            on={prefs.warnOffBook}
            onToggle={() => set({ warnOffBook: !prefs.warnOffBook })}
          />
        </div>

        {reps.length > 0 && (
          <>
            <Section title="Save into" />
            <div className="list">
              <ChoiceRow
                title="Whichever fits"
                meta="Matches the colour you play, or starts a new one"
                selected={prefs.repertoireId === ''}
                onSelect={() => set({ repertoireId: '' })}
              />
              {reps.map((rep) => (
                <ChoiceRow
                  key={rep.id}
                  title={displayName(rep.name)}
                  leading={<span className={`side ${rep.color}`} />}
                  selected={prefs.repertoireId === rep.id}
                  onSelect={() => set({ repertoireId: rep.id })}
                />
              ))}
            </div>
            {target && prefs.color !== 'random' && target.color !== prefs.color && (
              <div className="note">
                That is your {target.color === 'w' ? 'White' : 'Black'} repertoire, so a game as the
                other side will start a new one instead.
              </div>
            )}
          </>
        )}

        <Section title="Help" />
        <div className="list">
          <Toggle
            label="Show the evaluation"
            hint="A bar above the board while you play"
            on={prefs.showEval}
            onToggle={() => set({ showEval: !prefs.showEval })}
          />
          <Toggle
            label="Take backs"
            hint="Undo your last move and the reply"
            on={prefs.takeBacks}
            onToggle={() => set({ takeBacks: !prefs.takeBacks })}
          />
        </div>
      </div>
    </>
  );
}
