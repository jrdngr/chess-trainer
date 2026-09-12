import { useMemo } from 'react';
import { AppBar, ChoiceRow, Icons, Section, Segmented, Toggle } from '../../components/ui';
import {
  GAME_THRESHOLDS,
  gamesLabel,
  kindDescription,
  type RepairPrefs,
} from '../../model/modes';
import { buildRepairs, openingMismatch } from '../../model/repair';
import { measureCoverage } from '../../model/gameAnalysis';
import { displayName } from '../../model/repertoire';
import { repertoireList, useStore } from '../../store/useStore';

const KINDS: { value: RepairPrefs['kinds']; label: string }[] = [
  { value: 'both', label: 'Both' },
  { value: 'offprep', label: 'Off prep' },
  { value: 'unprepared', label: 'Unprepared' },
];

/** Where the evidence comes from, said in the bar. */
function subtitle(games: number, mistakes: number): string {
  const parts: string[] = [];
  if (games) parts.push(`${games} games`);
  if (mistakes) parts.push(`${mistakes} ${mistakes === 1 ? 'slip' : 'slips'} in the app`);
  return parts.join(' · ');
}

const SORTS: { value: RepairPrefs['sort']; label: string }[] = [
  { value: 'common', label: 'Most often' },
  { value: 'costly', label: 'Most costly' },
];

/**
 * What to repair, decided before you start.
 *
 * With no games imported there is nothing to decide, so the screen says so
 * plainly and offers the one action that helps.
 */
export function Setup({
  onStart,
  onImport,
  onExit,
}: {
  onStart: (prefs: RepairPrefs) => void;
  onImport: () => void;
  onExit: () => void;
}) {
  const state = useStore();
  const setModePrefs = useStore((s) => s.setModePrefs);
  const prefs = state.settings.repair;
  const record = state.repair;
  const reps = repertoireList(state);
  const games = state.importedGames;

  const set = (patch: Partial<RepairPrefs>) => setModePrefs('repair', patch);

  const items = useMemo(
    () =>
      buildRepairs(games, reps, {
        repertoireId: prefs.repertoireId,
        kinds: prefs.kinds,
        minGames: prefs.minGames,
        lossesOnly: prefs.lossesOnly,
        sort: prefs.sort,
        mistakes: state.mistakes,
      }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [games, state.mistakes, reps, prefs],
  );

  /**
   * Repertoires whose first move your games mostly disagree with. Worth saying
   * once, because no amount of repairing fixes prep for an opening you don't
   * play.
   */
  const mismatches = useMemo(
    () =>
      reps
        .filter((rep) => !prefs.repertoireId || rep.id === prefs.repertoireId)
        .map((rep) => ({ rep, mismatch: openingMismatch(games, rep) }))
        .filter((m): m is { rep: (typeof reps)[number]; mismatch: NonNullable<ReturnType<typeof openingMismatch>> } => !!m.mismatch),
    [games, reps, prefs.repertoireId],
  );

  /** How much of your real play your prep actually covered. */
  const coverage = useMemo(() => {
    const totals = reps
      .filter((rep) => !prefs.repertoireId || rep.id === prefs.repertoireId)
      .map((rep) => measureCoverage(games, rep));
    return totals.reduce(
      (sum, c) => ({
        inPrep: sum.inPrep + c.inPrep,
        outOfPrep: sum.outOfPrep + c.outOfPrep,
        games: sum.games + c.games,
      }),
      { inPrep: 0, outOfPrep: 0, games: 0 },
    );
  }, [games, reps, prefs.repertoireId]);

  if (games.length === 0 && state.mistakes.length === 0) {
    return (
      <>
        <AppBar title="Repair" subtitle="Fix what your own games got wrong." onClose={onExit} />
        <div className="screen no-nav">
          <div className="empty">
            <div className="t">No games yet</div>
            <div className="h">
              Repair works from games you have actually played — it compares them against your
              repertoire and shows you the positions you got wrong. Import some and it will have
              something to work with.
            </div>
          </div>
          <button className="btn primary block xl" onClick={onImport}>
            <Icons.download size={18} />
            Import games
          </button>
          <div className="note center">
            Lichess, Chess.com, or a PGN pasted in. Nothing leaves your device except the request
            for your own games.
          </div>
        </div>
      </>
    );
  }

  return (
    <>
      <AppBar
        title="Repair"
        subtitle={subtitle(games.length, state.mistakes.length)}
        onClose={onExit}
        actions={
          <button className="icon-btn plain" aria-label="Import more games" onClick={onImport}>
            <Icons.download size={20} />
          </button>
        }
      />

      <div className="screen no-nav">
        <button
          className="btn primary block xl"
          disabled={items.length === 0}
          onClick={() => onStart(prefs)}
        >
          {items.length === 0 ? 'Nothing to repair' : 'Start'}
        </button>
        <div className="note center">
          {items.length === 0
            ? 'No position matches these settings. Loosen them, or import more games.'
            : `${items.length} ${items.length === 1 ? 'position' : 'positions'} from your games disagree with your repertoire.`}
        </div>

        {mismatches.map(({ rep, mismatch }) => (
          <div className="banner" style={{ marginTop: 12 }} key={rep.id}>
            <span className="ico"><Icons.warn size={20} /></span>
            <div className="grow">
              You don't play the {displayName(rep.name)}
              <div className="sub">
                {mismatch.games} of your games open {mismatch.played[0].san}, not{' '}
                {mismatch.expected.join(' or ')}. Repair skips that choice — change the repertoire
                if it's wrong.
              </div>
            </div>
          </div>
        ))}

        {coverage.games > 0 && (
          <>
            <Section
              title="Your prep against your games"
              aside={`${Math.round((coverage.inPrep / coverage.games) * 100)}% in book`}
            />
            <div className="card">
              <div className="bar-stack">
                <i
                  style={{
                    width: `${(coverage.inPrep / coverage.games) * 100}%`,
                    background: 'var(--good)',
                  }}
                />
                <i
                  style={{
                    width: `${(coverage.outOfPrep / coverage.games) * 100}%`,
                    background: 'var(--warn)',
                  }}
                />
              </div>
              <div className="pills mt-12">
                <span className="pill">
                  <i style={{ background: 'var(--good)' }} />
                  <b>{coverage.inPrep}</b> stayed in book
                </span>
                <span className="pill">
                  <i style={{ background: 'var(--warn)' }} />
                  <b>{coverage.outOfPrep}</b> left early
                </span>
              </div>
            </div>
          </>
        )}

        <Section title="What to fix" />
        <Segmented value={prefs.kinds} options={KINDS} onChange={(kinds) => set({ kinds })} />
        <div className="note">{kindDescription(prefs.kinds)}</div>

        <Section title="How often you reached it" />
        <Segmented
          value={String(prefs.minGames)}
          options={GAME_THRESHOLDS.map((n) => ({ value: String(n), label: gamesLabel(n) }))}
          onChange={(n) => set({ minGames: Number(n) })}
        />
        <div className="note">
          {prefs.minGames === 1
            ? 'Everything, including positions you have seen once. Thorough, and noisier.'
            : `Only positions ${prefs.minGames} or more of your games reached — the ones that keep happening.`}
        </div>

        <Section title="Order" />
        <Segmented value={prefs.sort} options={SORTS} onChange={(sort) => set({ sort })} />
        <div className="note">
          {prefs.sort === 'costly'
            ? 'Worst results first — the positions you actually lose from.'
            : 'Most frequent first, with forgotten prep ahead of unprepared positions.'}
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

        <Section title="Narrow it" />
        <div className="list">
          <Toggle
            label="Only games I lost"
            hint="The positions that actually cost you something"
            on={prefs.lossesOnly}
            onToggle={() => set({ lossesOnly: !prefs.lossesOnly })}
          />
        </div>

        {record.seen > 0 && (
          <>
            <Section title="Repaired so far" />
            <div className="stat-grid">
              <div className="stat">
                <div className="n">{record.relearned}</div>
                <div className="l">relearned</div>
              </div>
              <div className="stat">
                <div className="n">{record.added}</div>
                <div className="l">lines added</div>
              </div>
              <div className="stat">
                <div className="n">{record.seen}</div>
                <div className="l">seen</div>
              </div>
            </div>
          </>
        )}
      </div>
    </>
  );
}
