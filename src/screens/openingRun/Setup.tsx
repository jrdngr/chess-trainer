import { useMemo, useState } from 'react';
import {
  AppBar,
  ChoiceRow,
  Icons,
  Section,
  Segmented,
  Sheet,
  Toggle,
} from '../../components/ui';
import { sansToMoveText } from '../../chess/core';
import {
  clockLabel,
  CLOCK_MODES,
  HINT_BUDGETS,
  other,
  playableRepertoires,
  type ColorChoice,
  type OpeningRunOptions,
} from '../../model/openingRun';
import { formatGameCount, type CatalogueEntry } from '../../model/reference';
import { referenceIndex } from '../../model/referenceIndex';
import { displayName } from '../../model/repertoire';
import type { Repertoire } from '../../model/types';
import { repertoireList, useStore } from '../../store/useStore';
import { Record } from './Record';

const COLORS: { value: ColorChoice; label: string }[] = [
  { value: 'w', label: 'White' },
  { value: 'b', label: 'Black' },
  { value: 'random', label: 'Random' },
];

/**
 * The screen that decides a run. Start sits at the top, above the options, so
 * the common case — same rules as last time — is one tap. Everything past the
 * first two sections is off by default; the plain mode is a line from your
 * repertoire, no clock, no help. Choices are remembered between runs.
 */
export function Setup({
  onStart,
  onExit,
}: {
  onStart: (options: OpeningRunOptions) => void;
  onExit: () => void;
}) {
  const state = useStore();
  const setOpeningRunPrefs = useStore((s) => s.setOpeningRunPrefs);
  const setSettings = useStore((s) => s.setSettings);
  const reps = repertoireList(state);
  const prefs = state.settings.openingRun;
  const favorites = state.settings.favoriteOpenings;
  const record = state.openingRun;
  const catalogue = referenceIndex().catalogue;
  const [browsing, setBrowsing] = useState(false);

  const fromRepertoire = prefs.kind === 'repertoire';
  const fromOpening = prefs.kind === 'opening';

  const pool = playableRepertoires(reps, prefs.color, { reverse: prefs.reverse });
  // A side the colour no longer allows quietly falls back to "either".
  const chosenId = pool.some((r) => r.id === prefs.repertoireId) ? prefs.repertoireId : '';
  const starred = favorites
    .map((id) => catalogue.find((entry) => entry.id === id))
    .filter((entry): entry is CatalogueEntry => !!entry);
  const chosenOpening = catalogue.find((entry) => entry.id === prefs.openingId) ?? null;
  // A pick that was never starred still belongs on this screen, and first, so
  // what the run will actually play is never hidden behind the full list.
  const openingRows =
    chosenOpening && !favorites.includes(chosenOpening.id) ? [chosenOpening, ...starred] : starred;
  const blocked = (fromRepertoire && pool.length === 0) || (fromOpening && !chosenOpening);

  const toggleFavorite = (id: string) => {
    setSettings({
      favoriteOpenings: favorites.includes(id)
        ? favorites.filter((f) => f !== id)
        : [...favorites, id],
    });
  };

  const pickOpening = (entry: CatalogueEntry) => {
    setOpeningRunPrefs({ openingId: entry.id, kind: 'opening' });
    setBrowsing(false);
  };

  /** Picking a side settles which colour you are on, so the colour follows it. */
  const chooseRepertoire = (rep: Repertoire | null) => {
    if (!rep) {
      setOpeningRunPrefs({ repertoireId: '' });
      return;
    }
    setOpeningRunPrefs({ repertoireId: rep.id, color: prefs.reverse ? other(rep.color) : rep.color });
  };

  return (
    <>
      <AppBar title="Run" onClose={onExit} />

      <div className="screen no-nav">
        <button
          className="btn primary block xl"
          disabled={blocked}
          onClick={() => onStart({ ...prefs, repertoireId: chosenId })}
        >
          {!blocked
            ? 'Start'
            : fromOpening
              ? 'Pick an opening first'
              : prefs.reverse
                ? 'Nothing to play against'
                : 'No lines for that colour'}
        </button>

        <Section title="Play as" />
        <Segmented value={prefs.color} options={COLORS} onChange={(color) => setOpeningRunPrefs({ color })} />

        <Section title="Lines" />
        <div className="list">
          <ChoiceRow
            title="My repertoire"
            meta={
              pool.length > 0
                ? pool.map((r) => displayName(r.name)).join(', ')
                : prefs.reverse
                  ? 'Nothing prepared against that side'
                  : 'Nothing prepared for that side'
            }
            selected={fromRepertoire}
            onSelect={() => setOpeningRunPrefs({ kind: 'repertoire' })}
          />
          <ChoiceRow
            title="One opening"
            meta={
              chosenOpening
                ? chosenOpening.name
                : starred.length > 0
                  ? `${starred.length} favourite${starred.length === 1 ? '' : 's'} — pick one below`
                  : 'Pick an opening and play it out'
            }
            selected={fromOpening}
            onSelect={() => setOpeningRunPrefs({ kind: 'opening' })}
          />
          <ChoiceRow
            title="The book"
            meta="Every named line the app knows"
            selected={prefs.kind === 'book'}
            onSelect={() => setOpeningRunPrefs({ kind: 'book' })}
          />
        </div>

        {fromOpening && (
          <>
            <Section
              title="Your openings"
              aside={starred.length > 0 ? 'star to keep, tap to pick' : undefined}
            />
            {openingRows.length === 0 ? (
              <div className="card small muted">
                No favourites yet. Open the full list and star the openings you want to
                practise — they will show up here.
              </div>
            ) : (
              <div className="list">
                {openingRows.map((entry) => (
                  <OpeningRow
                    key={entry.id}
                    entry={entry}
                    selected={prefs.openingId === entry.id}
                    starred={favorites.includes(entry.id)}
                    onPick={() => pickOpening(entry)}
                    onStar={() => toggleFavorite(entry.id)}
                  />
                ))}
              </div>
            )}
            <button className="btn sm block mt-8" onClick={() => setBrowsing(true)}>
              <Icons.book size={16} />
              The whole book
            </button>
          </>
        )}

        {fromRepertoire && pool.length > 1 && (
          <>
            <Section title="Which side" />
            <div className="list">
              <ChoiceRow
                title="Either"
                meta="Drawn across everything that fits"
                selected={chosenId === ''}
                onSelect={() => chooseRepertoire(null)}
              />
              {pool.map((rep) => (
                <ChoiceRow
                  key={rep.id}
                  title={rep.color === 'w' ? 'As White' : 'As Black'}
                  leading={<span className={`side ${prefs.reverse ? other(rep.color) : rep.color}`} />}
                  selected={chosenId === rep.id}
                  onSelect={() => chooseRepertoire(rep)}
                />
              ))}
            </div>
          </>
        )}

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
          {fromRepertoire && (
            <>
              <Toggle
                label="Target weak spots"
                hint="Draw lines you get wrong or have let lapse more often"
                on={prefs.weakFirst}
                onToggle={() => setOpeningRunPrefs({ weakFirst: !prefs.weakFirst })}
              />
              <Toggle
                label="Play the other side"
                hint="Sit on the side your repertoire prepares against"
                on={prefs.reverse}
                onToggle={() => setOpeningRunPrefs({ reverse: !prefs.reverse, repertoireId: '' })}
              />
            </>
          )}
          <Toggle
            label="Extended mode"
            hint="When the prep runs out, keep going while the engine calls your moves sound"
            on={prefs.extended}
            onToggle={() => setOpeningRunPrefs({ extended: !prefs.extended })}
          />
          <Toggle
            label="Per-opening records"
            hint="Keep a separate best for each opening and side"
            on={prefs.perLine}
            onToggle={() => setOpeningRunPrefs({ perLine: !prefs.perLine })}
          />
        </div>

        {record.runs > 0 && <Record record={record} perLine={prefs.perLine} />}
      </div>

      <OpeningPicker
        open={browsing}
        onClose={() => setBrowsing(false)}
        catalogue={catalogue}
        favorites={favorites}
        selected={prefs.openingId}
        onPick={pickOpening}
        onToggleFavorite={toggleFavorite}
      />
    </>
  );
}

/** One opening: tap to pick it, star to keep it on the setup screen. */
function OpeningRow({
  entry,
  selected,
  starred,
  onPick,
  onStar,
  showGames,
}: {
  entry: CatalogueEntry;
  selected: boolean;
  starred: boolean;
  onPick: () => void;
  onStar: () => void;
  showGames?: boolean;
}) {
  return (
    <div className="list-row">
      <button className="grow row" onClick={onPick}>
        <span className="grow">
          <div className="title truncate">{entry.name}</div>
          <div className="meta truncate">
            {entry.eco} · {sansToMoveText(entry.sans)}
            {showGames && entry.games > 0 ? ` · ${formatGameCount(entry.games)} games` : ''}
          </div>
        </span>
        {selected && <Icons.check size={18} />}
      </button>
      <button
        className="icon-btn plain"
        aria-label={`${starred ? 'Unstar' : 'Star'} ${entry.name}`}
        onClick={onStar}
      >
        <Icons.star size={18} filled={starred} />
      </button>
    </div>
  );
}

/**
 * The full catalogue, most played first, with favourites pulled to the top.
 * Searchable by name, ECO or moves.
 */
function OpeningPicker({
  open,
  onClose,
  catalogue,
  favorites,
  selected,
  onPick,
  onToggleFavorite,
}: {
  open: boolean;
  onClose: () => void;
  catalogue: CatalogueEntry[];
  favorites: string[];
  selected: string;
  onPick: (entry: CatalogueEntry) => void;
  onToggleFavorite: (id: string) => void;
}) {
  const [query, setQuery] = useState('');

  const rows = useMemo(() => {
    const needle = query.trim().toLowerCase();
    const matching = needle
      ? catalogue.filter(
          (entry) =>
            entry.name.toLowerCase().includes(needle) ||
            entry.eco.toLowerCase().startsWith(needle) ||
            entry.sans.join(' ').toLowerCase().includes(needle),
        )
      : catalogue;
    return {
      starred: matching.filter((entry) => favorites.includes(entry.id)),
      rest: matching.filter((entry) => !favorites.includes(entry.id)),
    };
  }, [catalogue, favorites, query]);

  const row = (entry: CatalogueEntry) => (
    <OpeningRow
      key={entry.id}
      entry={entry}
      selected={selected === entry.id}
      starred={favorites.includes(entry.id)}
      onPick={() => onPick(entry)}
      onStar={() => onToggleFavorite(entry.id)}
      showGames
    />
  );

  return (
    <Sheet open={open} onClose={onClose} title="All openings">
      <input
        className="field"
        placeholder="Search by name, ECO or moves"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
      />
      {rows.starred.length > 0 && (
        <>
          <Section title="Favourites" />
          <div className="list">{rows.starred.map(row)}</div>
        </>
      )}
      <Section
        title={rows.starred.length > 0 ? 'Everything else' : 'Most played first'}
        aside={rows.rest.length}
      />
      {rows.rest.length === 0 ? (
        <div className="card small muted">Nothing matches that.</div>
      ) : (
        <div className="list">{rows.rest.map(row)}</div>
      )}
    </Sheet>
  );
}
