import { useMemo } from 'react';
import { AppBar, ChoiceRow, Section, Segmented, Toggle } from '../../components/ui';
import { findGaps } from '../../model/gaps';
import {
  GAP_DEPTHS,
  SHARE_STEPS,
  shareLabel,
  type GapPrefs,
  type GapSort,
} from '../../model/modes';
import { referenceIndex } from '../../model/referenceIndex';
import { displayName } from '../../model/repertoire';
import { repertoireList, useStore } from '../../store/useStore';

const SORTS: { value: GapSort; label: string }[] = [
  { value: 'shallow', label: 'Shallowest' },
  { value: 'popular', label: 'Most played' },
];

/** Which holes you want listed, before the list. */
export function Setup({
  onStart,
  onExit,
}: {
  onStart: (prefs: GapPrefs) => void;
  onExit: () => void;
}) {
  const state = useStore();
  const setModePrefs = useStore((s) => s.setModePrefs);
  const prefs = state.settings.gap;
  const reps = repertoireList(state);
  const index = referenceIndex();

  const set = (patch: Partial<GapPrefs>) => setModePrefs('gap', patch);

  const count = useMemo(
    () =>
      reps
        .filter((rep) => !prefs.repertoireId || rep.id === prefs.repertoireId)
        .reduce(
          (sum, rep) =>
            sum + findGaps(rep, index, { minShare: prefs.minShare, maxPly: prefs.maxPly }).length,
          0,
        ),
    [reps, index, prefs.repertoireId, prefs.minShare, prefs.maxPly],
  );

  return (
    <>
      <AppBar title="Gap" subtitle="Replies you have no answer to." onClose={onExit} />

      <div className="screen no-nav">
        <button className="btn primary block xl" onClick={() => onStart(prefs)}>
          Start
        </button>
        <div className="note center">
          {count === 0
            ? 'Nothing unanswered at these settings.'
            : `${count} ${count === 1 ? 'gap' : 'gaps'} — a reply the database plays that your prep reaches and then stops short of.`}
        </div>

        <Section title="How often played" />
        <Segmented
          value={String(prefs.minShare)}
          options={SHARE_STEPS.map((share) => ({
            value: String(share),
            label: shareLabel(share),
          }))}
          onChange={(share) => set({ minShare: Number(share) })}
        />
        <div className="note">
          {prefs.minShare >= 3
            ? 'Mainlines only. The replies you are most likely to actually face.'
            : prefs.minShare >= 1
              ? 'Everything with a real following, sidelines included.'
              : 'Every reply anyone has played here. Thorough, and a long list.'}
        </div>

        <Section title="How deep" />
        <Segmented
          value={String(prefs.maxPly)}
          options={GAP_DEPTHS.map((ply) => ({
            value: String(ply),
            label: `${Math.ceil(ply / 2)} moves`,
          }))}
          onChange={(ply) => set({ maxPly: Number(ply) })}
        />
        <div className="note">
          Past {Math.ceil(prefs.maxPly / 2)} moves, a line running out is play rather than a hole in
          the prep.
        </div>

        <Section title="Order" />
        <Segmented value={prefs.sort} options={SORTS} onChange={(sort) => set({ sort })} />
        <div className="note">
          {prefs.sort === 'popular'
            ? 'The most played replies first, however deep they sit.'
            : 'Nearest the start first — fixing those covers the most games.'}
        </div>

        {reps.length > 1 && (
          <>
            <Section title="Repertoire" />
            <div className="list">
              <ChoiceRow
                title="All of them"
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

        <Section title="Fixing" />
        <div className="list">
          <Toggle
            label="One-tap fix"
            hint="Add the book's most played answer without asking"
            on={prefs.quickFix}
            onToggle={() => set({ quickFix: !prefs.quickFix })}
          />
        </div>
        <div className="note">
          {prefs.quickFix
            ? 'Fast, and the majority move is usually the right first answer. You can change it later in Repertoire.'
            : 'Each gap opens the position with the book’s candidates to choose between.'}
        </div>
      </div>
    </>
  );
}
