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
  BLUNDER_LIMIT,
  clockDescription,
  clockLabel,
  CLOCK_MODES,
  HINT_BUDGETS,
  other,
  playableRepertoires,
  type ColorChoice,
  type PermadeathOptions,
  type PermadeathPrefs,
} from '../../model/permadeath';
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
 * The screen that decides a run. Everything past the first two sections is off
 * by default; the plain mode is a line from your repertoire, no clock, no help.
 * Choices are remembered between runs.
 */
export function Setup({
  onStart,
  onExit,
}: {
  onStart: (options: PermadeathOptions) => void;
  onExit: () => void;
}) {
  const state = useStore();
  const setPermadeath = useStore((s) => s.setPermadeath);
  const setSettings = useStore((s) => s.setSettings);
  const reps = repertoireList(state);
  const prefs = state.settings.permadeath;
  const favorites = state.settings.favoriteOpenings;
  const record = state.permadeath;
  const catalogue = referenceIndex().catalogue;
  const [browsing, setBrowsing] = useState(false);

  const fromRepertoire = prefs.kind === 'repertoire';
  const fromOpening = prefs.kind === 'opening';

  const pool = playableRepertoires(reps, prefs.color, { reverse: prefs.reverse });
  // A repertoire the colour no longer allows quietly falls back to "any".
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
    setPermadeath({ openingId: entry.id, kind: 'opening' });
    setBrowsing(false);
  };

  /** Picking a repertoire settles which side you are on, so the colour follows it. */
  const chooseRepertoire = (rep: Repertoire | null) => {
    if (!rep) {
      setPermadeath({ repertoireId: '' });
      return;
    }
    setPermadeath({ repertoireId: rep.id, color: prefs.reverse ? other(rep.color) : rep.color });
  };

  return (
    <>
      <AppBar title="Permadeath" subtitle="One secret line. One mistake." onClose={onExit} />

      <div className="screen no-nav with-footer">
        <Section title="Play as" />
        <Segmented value={prefs.color} options={COLORS} onChange={(color) => setPermadeath({ color })} />

        <Section title="Lines" />
        <div className="list">
          <ChoiceRow
            title="My repertoire"
            meta={
              pool.length > 0
                ? pool.map((r) => displayName(r.name)).join(', ')
                : prefs.reverse
                  ? 'Nothing prepared against that side'
                  : 'No repertoire for that colour'
            }
            selected={fromRepertoire}
            onSelect={() => setPermadeath({ kind: 'repertoire' })}
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
            onSelect={() => setPermadeath({ kind: 'opening' })}
          />
          <ChoiceRow
            title="Book"
            meta="Every line in the reference database"
            selected={prefs.kind === 'book'}
            onSelect={() => setPermadeath({ kind: 'book' })}
          />
        </div>
        <div className="note">{sourceNote(prefs, chosenOpening)}</div>

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
              All openings
            </button>
          </>
        )}

        {fromRepertoire && pool.length > 1 && (
          <>
            <Section title="Which repertoire" />
            <div className="list">
              <ChoiceRow
                title="Any of mine"
                meta="Drawn across every repertoire that fits"
                selected={chosenId === ''}
                onSelect={() => chooseRepertoire(null)}
              />
              {pool.map((rep) => (
                <ChoiceRow
                  key={rep.id}
                  title={displayName(rep.name)}
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
          onChange={(clock) => setPermadeath({ clock })}
        />
        <div className="note">{clockDescription(prefs.clock)}</div>

        <Section title="Hints" />
        <Segmented
          value={String(prefs.hints)}
          options={HINT_BUDGETS.map((n) => ({
            value: String(n),
            label: n === 0 ? 'None' : `${n} hint${n === 1 ? '' : 's'}`,
          }))}
          onChange={(n) => setPermadeath({ hints: Number(n) })}
        />
        <div className="note">
          {prefs.hints === 0
            ? 'No help. The position is the whole question.'
            : 'A hint shows the square the move starts from — never where it lands.'}
        </div>

        <Section title="Extras" />
        <div className="list">
          {fromRepertoire && (
            <>
              <Toggle
                label="Target weak spots"
                hint="Draw lines you get wrong or have let lapse more often"
                on={prefs.weakFirst}
                onToggle={() => setPermadeath({ weakFirst: !prefs.weakFirst })}
              />
              <Toggle
                label="Play the other side"
                hint="Sit on the side your repertoire prepares against"
                on={prefs.reverse}
                onToggle={() => setPermadeath({ reverse: !prefs.reverse, repertoireId: '' })}
              />
            </>
          )}
          <Toggle
            label="Extended mode"
            hint="When the prep runs out, keep going while the engine calls your moves sound"
            on={prefs.extended}
            onToggle={() => setPermadeath({ extended: !prefs.extended })}
          />
          <Toggle
            label="Per-opening records"
            hint="Keep a separate best for each opening and side"
            on={prefs.perLine}
            onToggle={() => setPermadeath({ perLine: !prefs.perLine })}
          />
        </div>
        {prefs.extended && (
          <div className="note">
            In extended mode the run does not stop when the prep does: the engine takes over, and
            you survive as long as your moves do not drop more than {(BLUNDER_LIMIT / 100).toFixed(2)}.
          </div>
        )}

        {record.runs > 0 && <Record record={record} perLine={prefs.perLine} />}
      </div>

      <div className="footer">
        <button
          className="btn primary block xl"
          disabled={blocked}
          onClick={() => onStart({ ...prefs, repertoireId: chosenId })}
        >
          {!blocked
            ? 'Start run'
            : fromOpening
              ? 'Pick an opening first'
              : prefs.reverse
                ? 'Nothing to play against'
                : 'No lines for that colour'}
        </button>
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

/** What the chosen source means for the run, in a sentence. */
function sourceNote(prefs: PermadeathPrefs, opening: CatalogueEntry | null): string {
  switch (prefs.kind) {
    case 'opening':
      return opening
        ? `The opponent walks you into the ${opening.name}. Its move order is the only thing that counts while you are still in it; after that the book takes over.`
        : 'Pick an opening to play out. Its move order is the only thing that counts while you are still in it; after that the book takes over.';
    case 'book':
      return 'Any move played in the reference database keeps you alive, so the book forgives more than your repertoire does. It is a curated sample, not every game ever played.';
    default:
      return prefs.reverse
        ? 'You play the side your repertoire answers. Staying alive means knowing what your opponent is meant to do — the run ends on any move you have not prepared for.'
        : 'A line is drawn from your repertoire. Any move you have prepared from a position counts — the run ends the moment you leave your own prep.';
  }
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
