import { AppBar, Section, Segmented, Toggle } from '../../components/ui';
import { SelectionBar } from '../../components/Selection';
import { LEVELS, OPENING_PLIES, type PlayPrefs } from '../../model/modes';
import { useStore } from '../../store/useStore';

/** What kind of game, and what to keep from it. */
export function Setup({
  onStart,
  onExit,
}: {
  onStart: (prefs: PlayPrefs) => void;
  onExit: () => void;
}) {
  const prefs = useStore((s) => s.settings.play);
  const setModePrefs = useStore((s) => s.setModePrefs);

  const set = (patch: Partial<PlayPrefs>) => setModePrefs('play', patch);

  return (
    <>
      <AppBar title="Play" onClose={onExit} />

      <div className="screen no-nav">
        <SelectionBar />

        <button className="btn primary block xl" onClick={() => onStart(prefs)}>
          Start
        </button>

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
