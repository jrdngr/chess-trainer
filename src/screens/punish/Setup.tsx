import { AppBar, ChoiceRow, Section, Segmented, Toggle } from '../../components/ui';
import {
  depthLabel,
  gainLabel,
  GAIN_STEPS,
  PUNISH_DEPTHS,
  PUNISH_SECONDS,
  type PunishPrefs,
} from '../../model/modes';
import { displayName } from '../../model/repertoire';
import { repertoireList, useStore } from '../../store/useStore';

/** What kind of trap you want to be shown, before you are shown one. */
export function Setup({
  onStart,
  onExit,
}: {
  onStart: (prefs: PunishPrefs) => void;
  onExit: () => void;
}) {
  const state = useStore();
  const setModePrefs = useStore((s) => s.setModePrefs);
  const prefs = state.settings.punish;
  const record = state.punish;
  const reps = repertoireList(state);

  const set = (patch: Partial<PunishPrefs>) => setModePrefs('punish', patch);

  return (
    <>
      <AppBar
        title="Punish"
        subtitle="They leave the book. Take what they dropped."
        onClose={onExit}
      />

      <div className="screen no-nav">
        <button
          className="btn primary block xl"
          disabled={reps.length === 0}
          onClick={() => onStart(prefs)}
        >
          {reps.length === 0 ? 'Add a repertoire first' : 'Set a trap'}
        </button>
        <div className="note center">
          Every trap comes from a position your own lines actually reach.
        </div>

        <Section title="Worth taking" />
        <Segmented
          value={String(prefs.minGain)}
          options={GAIN_STEPS.map((gain) => ({ value: String(gain), label: gainLabel(gain) }))}
          onChange={(gain) => set({ minGain: Number(gain) })}
        />
        <div className="note">
          {prefs.minGain >= 5
            ? 'Only outright disasters. Rare, and unmistakable when they come.'
            : prefs.minGain >= 3
              ? 'A whole piece or better, so the punishment is never a subtle exchange.'
              : 'Anything from a clean pawn upward. The most traps, and the closest ones to real games.'}
        </div>

        <Section title="How deep" />
        <Segmented
          value={String(prefs.maxPly)}
          options={PUNISH_DEPTHS.map((ply) => ({ value: String(ply), label: depthLabel(ply) }))}
          onChange={(ply) => set({ maxPly: Number(ply) })}
        />
        <div className="note">
          Traps are drawn from the first {depthLabel(prefs.maxPly).toLowerCase()} of your lines.
          {prefs.maxPly <= 8
            ? ' Early mistakes only — the ones you will meet again next week.'
            : prefs.maxPly >= 24
              ? ' Deep positions included, which are rarer and less likely to repeat.'
              : ''}
        </div>

        {reps.length > 1 && (
          <>
            <Section title="From" />
            <div className="list">
              <ChoiceRow
                title="Any of mine"
                meta="Drawn across every repertoire"
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
          </>
        )}

        <Section title="Difficulty" />
        <div className="list">
          <Toggle
            label="Say what they played"
            hint="Off means finding the mistake is part of the puzzle"
            on={prefs.announce}
            onToggle={() => set({ announce: !prefs.announce })}
          />
          <Toggle
            label="Name the opening"
            hint="Off keeps you from placing the position before you look at it"
            on={prefs.nameOpening}
            onToggle={() => set({ nameOpening: !prefs.nameOpening })}
          />
          <Toggle
            label={`${PUNISH_SECONDS}-second clock`}
            hint="Running out counts as a miss"
            on={prefs.timed}
            onToggle={() => set({ timed: !prefs.timed })}
          />
        </div>
        <div className="note">
          {prefs.timed
            ? 'A trap you have to think about for half a minute is one you would miss over the board anyway.'
            : 'No clock. Take as long as the position needs.'}
        </div>

        {record.seen > 0 && (
          <>
            <Section
              title="Record"
              aside={`${Math.round((record.solved / record.seen) * 100)}% sprung`}
            />
            <div className="stat-grid">
              <div className="stat">
                <div className="n">{record.solved}</div>
                <div className="l">sprung</div>
              </div>
              <div className="stat">
                <div className="n">{record.seen}</div>
                <div className="l">seen</div>
              </div>
              <div className="stat">
                <div className="n">{record.best}</div>
                <div className="l">best streak</div>
              </div>
            </div>
          </>
        )}
      </div>
    </>
  );
}
