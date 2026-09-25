import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { walkSan, piecesFromFen, START_FEN, type Color } from '../chess/core';
import type { ColorChoice } from '../model/openingRun';
import { nodeById, openingTree, type OpeningNode, type OpeningTree } from '../model/openingTree';
import {
  entryForNode,
  entryTrail,
  groupOf,
  PICKER_SORTS,
  pickerCatalog,
  sideForPick,
  sortEntries,
  type FirstMove,
  type PickerCatalog,
  type PickerEntry,
  type PickerFamily,
  type PickerGroup,
  type PickerSort,
} from '../model/picker';
import { formatGameCount } from '../model/reference';
import { referenceIndex } from '../model/referenceIndex';
import { rankOf } from '../model/scoring';
import { colorLabel } from '../model/selection';
import { useStore } from '../store/useStore';
import { Piece } from './Pieces';
import { ChoiceRow, IconButton, Icons, Segmented, Sheet } from './ui';

/** A side as a small square: white, black, or split diagonally for random. */
export function ColorSquare({ choice, size = 18 }: { choice: ColorChoice; size?: number }) {
  return (
    <span
      className={`color-square ${choice}`}
      style={{ width: size, height: size }}
      aria-label={colorLabel(choice)}
    />
  );
}

function catalogNow(): { tree: OpeningTree; catalog: PickerCatalog } {
  const tree = openingTree(referenceIndex());
  return { tree, catalog: pickerCatalog(tree) };
}

/**
 * A name without the word every opening has: "Najdorf" for "Najdorf
 * Variation", "King's Indian" for "King's Indian Defence". For trails, where
 * several names share a line and the suffixes are noise.
 */
export function shortLabel(label: string): string {
  return label.replace(/ (Defence|Variation|Opening|Game)$/, '') || label;
}

/** Where a node sits, as short names from its family down. */
export function selectionTrail(openingId: string): string[] {
  const { tree, catalog } = catalogNow();
  const node = nodeById(tree, openingId);
  if (node.depth === 0) return ['Any opening'];
  const entry = entryForNode(catalog, node);
  return entry ? entryTrail(entry).map((e) => shortLabel(e.label)) : [node.name];
}

/** "White · Sicilian › Najdorf" — the selection as a subtitle. */
export function selectionText(color: ColorChoice, openingId: string): string {
  return `${colorLabel(color)} · ${selectionTrail(openingId).join(' › ')}`;
}

/**
 * The global selection, at the top of the screens where it can be changed.
 *
 * The square opens the side picker; the trail opens the opening picker, and
 * reads the way the picker's own breadcrumbs do.
 */
export function SelectionBar() {
  const selection = useStore((s) => s.settings.selection);
  const openStats = useStore((s) => s.openStats);
  const [picking, setPicking] = useState<'color' | 'opening' | null>(null);
  const trail = selectionTrail(selection.opening);

  return (
    <>
      <div className="selection-bar">
        <button className="pick color" onClick={() => setPicking('color')} aria-label="Colour">
          <ColorSquare choice={selection.color} size={22} />
        </button>
        <button className="pick opening" onClick={() => setPicking('opening')}>
          <span className="grow sel-trail">
            {trail.map((label, i) => (
              <span key={i} className={i === trail.length - 1 ? 'here' : ''}>
                {i > 0 && <span className="sep">{'›'}</span>}
                {label}
              </span>
            ))}
          </span>
          <Icons.down size={16} />
        </button>
      </div>
      <ColorPicker open={picking === 'color'} onClose={() => setPicking(null)} />
      <OpeningPicker
        open={picking === 'opening'}
        onClose={() => setPicking(null)}
        onStats={(id) => {
          setPicking(null);
          openStats(id);
        }}
      />
    </>
  );
}

const CHOICES: ColorChoice[] = ['w', 'b', 'random'];

export function ColorPicker({ open, onClose }: { open: boolean; onClose: () => void }) {
  const selection = useStore((s) => s.settings.selection);
  const setSelection = useStore((s) => s.setSelection);
  return (
    <Sheet open={open} onClose={onClose} title="Play as" from="top">
      <div className="list">
        {CHOICES.map((choice) => (
          <ChoiceRow
            key={choice}
            title={colorLabel(choice)}
            meta={choice === 'random' ? 'A coin flip each game' : undefined}
            leading={<ColorSquare choice={choice} size={22} />}
            selected={selection.color === choice}
            onSelect={() => {
              setSelection({ color: choice });
              onClose();
            }}
          />
        ))}
      </div>
    </Sheet>
  );
}

/**
 * The opening picker, over the whole screen.
 *
 * Families first, as a grid under their first move; a family opens on its
 * branches, grouped where the family is big; a branch opens on its lines. A
 * sticky header carries the trail back up, the position, and the one button
 * that trains whatever you are looking at.
 */
export function OpeningPicker({
  open,
  onClose,
  onStats,
}: {
  open: boolean;
  onClose: () => void;
  /** Open a stats page for a node, when the picker is used from somewhere that has one. */
  onStats?: (id: string) => void;
}) {
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onClose]);
  if (!open) return null;
  return (
    <div className="op-screen" role="dialog" aria-label="Opening">
      <OpeningList onChose={onClose} onClose={onClose} onStats={onStats} />
    </div>
  );
}

/* ── places ─────────────────────────────────────────────────────────────── */

type Place =
  | { kind: 'root' }
  | { kind: 'family'; family: string }
  | { kind: 'group'; group: string }
  | { kind: 'entry'; key: string };

const ROOT: Place = { kind: 'root' };

function placeOf(entry: PickerEntry): Place {
  return entry.level === 0 ? { kind: 'family', family: entry.key } : { kind: 'entry', key: entry.key };
}

/** The page a leaf is listed on. */
function pageOf(catalog: PickerCatalog, entry: PickerEntry): Place {
  if (entry.children.length) return placeOf(entry);
  if (!entry.parent) return ROOT;
  if (entry.level === 1) {
    const family = catalog.familyByName.get(entry.family);
    const group = family && groupOf(family, entry);
    if (group) return { kind: 'group', group: group.id };
  }
  return placeOf(entry.parent);
}

function samePlace(a: Place, b: Place): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
}

interface Crumb {
  label: string;
  side?: Color;
  place: Place;
}

/** "1.e4 c5 2.Nf3" without playing the moves: the book always starts from the start. */
function moveText(sans: string[]): string {
  return sans.map((san, i) => (i % 2 === 0 ? `${i / 2 + 1}.${san}` : san)).join(' ');
}

/* ── the picker ─────────────────────────────────────────────────────────── */

/**
 * The picker's contents, without the screen around it.
 *
 * `multi` is the same picker used to say which openings are yours: picking
 * stars instead of selecting, nothing closes, and the side is left alone.
 * Onboarding is the one place that wants it.
 */
export function OpeningList({
  multi = false,
  onChose,
  onClose,
  onStats,
}: {
  multi?: boolean;
  /** Called after the selection is set, in single mode. */
  onChose?: () => void;
  onClose?: () => void;
  onStats?: (id: string) => void;
}) {
  const selection = useStore((s) => s.settings.selection);
  const starred = useStore((s) => s.settings.favoriteOpenings);
  const sort = useStore((s) => s.settings.pickerSort);
  const score = useStore((s) => s.score);
  const setSelection = useStore((s) => s.setSelection);
  const setSettings = useStore((s) => s.setSettings);
  const toggleStar = useStore((s) => s.toggleStar);
  const { tree, catalog } = catalogNow();

  const groups = useMemo(() => {
    const out = new Map<string, { group: PickerGroup; family: PickerFamily }>();
    for (const family of catalog.families) for (const group of family.groups ?? []) out.set(group.id, { group, family });
    return out;
  }, [catalog]);

  /** Open where the selection is, so it is on screen. */
  const [wanted, setPlace] = useState<Place>(() => {
    if (multi) return ROOT;
    const node = nodeById(tree, selection.opening);
    const entry = node.depth > 0 ? entryForNode(catalog, node) : null;
    return entry ? pageOf(catalog, entry) : ROOT;
  });
  const [query, setQuery] = useState('');
  const [searching, setSearching] = useState(false);
  const [open, setOpen] = useState<Set<string>>(new Set());
  const [fullTrail, setFullTrail] = useState(false);
  const crumbRow = useRef<HTMLDivElement>(null);

  // A book rebuild can take a name away; a place that no longer exists is the root.
  const place: Place =
    (wanted.kind === 'family' && !catalog.familyByName.has(wanted.family)) ||
    (wanted.kind === 'entry' && !catalog.byKey.has(wanted.key)) ||
    (wanted.kind === 'group' && !groups.has(wanted.group))
      ? ROOT
      : wanted;

  const go = (next: Place) => {
    setPlace(next);
    setQuery('');
    setSearching(false);
    setFullTrail(false);
  };

  const stars = new Set(starred);
  const sorted = (entries: PickerEntry[]) => sortEntries(entries, sort, starred);

  const pick = (node: OpeningNode, side: Color | null) => {
    if (multi) {
      toggleStar(node.id);
      return;
    }
    setSelection(side ? { opening: node.id, color: side } : { opening: node.id });
    onChose?.();
  };
  const pickEntry = (entry: PickerEntry) => pick(entry.node, entry.side);

  /* where we are */
  const familyOf = (name: string) => catalog.familyByName.get(name)!;
  const here = (() => {
    switch (place.kind) {
      case 'root':
        return null;
      case 'family':
        return familyOf(place.family).entry;
      case 'group':
        return null;
      case 'entry':
        return catalog.byKey.get(place.key) ?? null;
    }
  })();
  const groupHere = place.kind === 'group' ? groups.get(place.group) ?? null : null;

  const crumbs: Crumb[] = (() => {
    const out: Crumb[] = [{ label: 'Openings', place: ROOT }];
    const trailOf = (entry: PickerEntry) => {
      const chain = entryTrail(entry);
      const family = familyOf(chain[0].family);
      out.push({ label: shortLabel(chain[0].label), side: chain[0].side, place: placeOf(chain[0]) });
      if (chain[1]) {
        const group = groupOf(family, chain[1]);
        if (group) out.push({ label: group.label, place: { kind: 'group', group: group.id } });
      }
      for (const link of chain.slice(1)) out.push({ label: shortLabel(link.label), side: link.side, place: placeOf(link) });
    };
    if (here) trailOf(here);
    if (groupHere) {
      const family = groupHere.family.entry;
      out.push({ label: shortLabel(family.label), side: family.side, place: placeOf(family) });
      out.push({ label: groupHere.group.label, place });
    }
    return out;
  })();

  // The crumb you are on is the one that matters: keep the trail scrolled to it.
  const placeId = JSON.stringify(place);
  useEffect(() => {
    const el = crumbRow.current;
    if (el) el.scrollLeft = el.scrollWidth;
  }, [placeId, fullTrail]);

  /* the header */
  const head = (() => {
    if (groupHere) {
      const node = groupHere.group.node;
      return {
        title: groupHere.group.label,
        moves: node ? moveText(node.sans) : `${groupHere.group.entries.length} branches of the ${groupHere.family.entry.label}`,
        sans: node?.sans ?? groupHere.family.entry.node.sans,
        node,
        side: node ? sideForPick(catalog, node) : groupHere.family.entry.side,
        sharpness: groupHere.group.sharpness,
        difficulty: null as number | null,
      };
    }
    if (here) {
      return {
        title: here.label,
        moves: moveText(here.node.sans),
        sans: here.node.sans,
        node: here.exact ? here.node : null,
        side: here.side as Color | null,
        sharpness: here.sharpness as number | null,
        difficulty: here.difficulty as number | null,
      };
    }
    return {
      title: 'Openings',
      moves: 'Every line the book knows',
      sans: [] as string[],
      node: multi ? null : tree.root,
      side: null as Color | null,
      sharpness: null as number | null,
      difficulty: null as number | null,
    };
  })();
  const orientation: Color = head.side ?? (selection.color === 'b' ? 'b' : 'w');
  const chosen = (node: OpeningNode) => (multi ? stars.has(node.id) : selection.opening === node.id);

  const shownCrumbs =
    crumbs.length > 3 && !fullTrail
      ? [crumbs[0], null, ...crumbs.slice(-2)]
      : crumbs;

  /* rows */
  const row = (entry: PickerEntry, opts: { meta?: ReactNode; tapPicks?: boolean } = {}) => {
    const deeper = entry.children.length > 0;
    const stats = score.nodes[entry.node.id];
    const rank = entry.exact && stars.has(entry.node.id) && stats && stats.rated > 0 ? rankOf(stats.rating) : null;
    const onTap = () => (deeper && !opts.tapPicks ? go(placeOf(entry)) : pickEntry(entry));
    return (
      <div className={`list-row op-row${entry.exact && chosen(entry.node) ? ' selected' : ''}`} key={entry.key}>
        {entry.exact ? (
          <button
            className="icon-btn plain"
            aria-label={`${stars.has(entry.node.id) ? 'Unstar' : 'Star'} ${entry.label}`}
            onClick={() => toggleStar(entry.node.id)}
          >
            <Icons.star size={18} filled={stars.has(entry.node.id)} />
          </button>
        ) : (
          <span className="op-star-gap" />
        )}
        <button className="grow row op-main" onClick={onTap}>
          <span className="grow" style={{ minWidth: 0 }}>
            <div className="title truncate">
              <SideDot side={entry.side} />
              {entry.label}
            </div>
            <div className="meta truncate">{opts.meta ?? moveText(entry.node.sans)}</div>
          </span>
          <span className="op-scores">
            <Meter kind="sharp" value={entry.sharpness} />
            <Meter kind="theory" value={entry.difficulty} />
          </span>
          {rank?.held && (
            <span className="op-rank" style={{ color: rank.held.color }}>
              {rank.held.name}
            </span>
          )}
          {entry.exact && chosen(entry.node) && <Icons.check size={18} />}
        </button>
        {deeper && !opts.tapPicks ? (
          <span className="op-chev">
            <Icons.chevron size={16} />
          </span>
        ) : deeper ? (
          <button className="icon-btn plain" aria-label={`Open ${entry.label}`} onClick={() => go(placeOf(entry))}>
            <Icons.chevron size={16} />
          </button>
        ) : null}
      </div>
    );
  };

  const trailMeta = (entry: PickerEntry) =>
    entryTrail(entry)
      .slice(0, -1)
      .map((e) => shortLabel(e.label))
      .join(' › ') || moveText(entry.node.sans);

  /* bodies */
  const body = (() => {
    const needle = query.trim().toLowerCase();
    if (searching && needle) {
      const found = [...catalog.byKey.values()]
        .filter(
          (entry) =>
            entry.key.toLowerCase().includes(needle) ||
            (entry.node.eco ?? '').toLowerCase().startsWith(needle) ||
            entry.node.id.toLowerCase().includes(needle),
        )
        .sort(
          (a, b) =>
            Number(stars.has(b.node.id)) - Number(stars.has(a.node.id)) || b.games - a.games || a.level - b.level,
        )
        .slice(0, 40);
      return (
        <>
          <SectionHead title="Matches" aside={found.length} />
          {found.length === 0 ? (
            <div className="card small muted">Nothing matches that.</div>
          ) : (
            <div className="list">{found.map((entry) => row(entry, { meta: trailMeta(entry) }))}</div>
          )}
        </>
      );
    }

    if (place.kind === 'root') {
      const mine = starred
        .map((id) => tree.byId.get(id))
        .filter((node): node is OpeningNode => Boolean(node) && node!.depth > 0)
        .map((node) => entryForNode(catalog, node))
        .filter((entry): entry is PickerEntry => entry !== null);
      const sections: { id: FirstMove; title: string }[] = [
        { id: 'e4', title: '1.e4' },
        { id: 'd4', title: '1.d4' },
        { id: 'flank', title: 'Flank openings' },
      ];
      return (
        <>
          {mine.length > 0 && (
            <>
              <SectionHead title={multi ? 'Picked' : 'Your openings'} aside={mine.length} />
              <div className="list">{sorted(mine).map((entry) => row(entry, { meta: trailMeta(entry), tapPicks: !multi }))}</div>
            </>
          )}
          {sections.map((section) => {
            const families = sorted(
              catalog.families.filter((family) => family.firstMove === section.id).map((family) => family.entry),
            );
            const expanded = open.has(section.id);
            const shown = expanded ? families : families.slice(0, 10);
            return (
              <div key={section.id}>
                <SectionHead title={section.title} aside={`${families.length} families`} />
                <div className="op-grid">
                  {shown.map((entry) => (
                    <FamilyCard
                      key={entry.key}
                      entry={entry}
                      starred={stars.has(entry.node.id)}
                      chosen={entry.exact && chosen(entry.node)}
                      onOpen={() => (entry.children.length ? go(placeOf(entry)) : pickEntry(entry))}
                    />
                  ))}
                </div>
                {families.length > shown.length && (
                  <button className="op-more" onClick={() => setOpen(new Set([...open, section.id]))}>
                    Show all {families.length}
                  </button>
                )}
              </div>
            );
          })}
        </>
      );
    }

    if (groupHere) {
      const { group } = groupHere;
      return (
        <>
          <SectionHead title="Branches" aside={group.entries.length} />
          <div className="list">
            {sorted(group.entries).map((entry) =>
              row(entry, { meta: viaMeta(group, entry) }),
            )}
          </div>
        </>
      );
    }

    const entry = here!;
    const family = entry.level === 0 ? familyOf(entry.key) : null;
    if (family?.groups) {
      return (
        <>
          {family.groups.map((group) => {
            const list = sorted(group.entries);
            const shown = list.slice(0, 6);
            return (
              <div key={group.id}>
                <button className="op-group-head" onClick={() => go({ kind: 'group', group: group.id })}>
                  <span className="grow">{group.label}</span>
                  <Meter kind="sharp" value={group.sharpness} />
                  <span className="faint tiny">{group.entries.length}</span>
                  <Icons.chevron size={14} />
                </button>
                <div className="list">{shown.map((e) => row(e, { meta: viaMeta(group, e) }))}</div>
                {list.length > shown.length && (
                  <button className="op-more" onClick={() => go({ kind: 'group', group: group.id })}>
                    Show all {list.length} in {group.label}
                  </button>
                )}
              </div>
            );
          })}
        </>
      );
    }

    return (
      <>
        <SectionHead title={entry.level === 0 ? 'Branches' : 'Lines'} aside={entry.children.length || undefined} />
        {entry.children.length === 0 ? (
          <div className="card small muted">The book names nothing deeper.</div>
        ) : (
          <div className="list">{sorted(entry.children).map((child) => row(child))}</div>
        )}
      </>
    );
  })();

  return (
    <div className="op">
      <header className="op-head">
        <div className="op-trail">
          {place.kind !== 'root' && (
            <IconButton label="Back" onClick={() => go(crumbs[crumbs.length - 2]?.place ?? ROOT)}>
              <Icons.back size={18} />
            </IconButton>
          )}
          <div className="op-crumbs" ref={crumbRow}>
            {shownCrumbs.map((crumb, i) =>
              crumb === null ? (
                <span key="gap" className="op-crumb-wrap gap">
                  <span className="sep">{'›'}</span>
                  <button className="op-chip" onClick={() => setFullTrail(true)} aria-label="Show the whole trail">
                    {'…'}
                  </button>
                </span>
              ) : (
                <span key={i} className="op-crumb-wrap">
                  {i > 0 && <span className="sep">{'›'}</span>}
                  <button
                    className={`op-chip${samePlace(crumb.place, place) ? ' here' : ''}`}
                    onClick={() => go(crumb.place)}
                  >
                    {crumb.side && <SideDot side={crumb.side} />}
                    {crumb.label}
                  </button>
                </span>
              ),
            )}
          </div>
          <IconButton label="Search" onClick={() => setSearching(!searching)}>
            <Icons.search size={18} />
          </IconButton>
          {onClose && (
            <IconButton label="Close" onClick={onClose}>
              <Icons.close size={18} />
            </IconButton>
          )}
        </div>

        {searching ? (
          <input
            className="field op-search"
            autoFocus
            placeholder="Search by name, ECO or moves"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        ) : (
          <div className="op-hero">
            <MiniBoard sans={head.sans} orientation={orientation} />
            <div className="op-hero-text">
              <h2 className="op-title">{head.title}</h2>
              <div className="op-moves">{head.moves}</div>
              {(head.sharpness !== null || head.difficulty !== null) && (
                <div className="op-hero-scores">
                  {head.sharpness !== null && <Meter kind="sharp" value={head.sharpness} labelled />}
                  {head.difficulty !== null && <Meter kind="theory" value={head.difficulty} labelled />}
                </div>
              )}
              <div className="op-actions">
                {head.node ? (
                  multi ? (
                    <button className={`btn sm${stars.has(head.node.id) ? ' accent' : ''}`} onClick={() => toggleStar(head.node!.id)}>
                      <Icons.star size={16} filled={stars.has(head.node.id)} />
                      {stars.has(head.node.id) ? 'Picked' : 'Pick this'}
                    </button>
                  ) : (
                    <button
                      className={`btn sm${chosen(head.node) ? '' : ' accent'}`}
                      onClick={() => pick(head.node!, head.side)}
                    >
                      {chosen(head.node) ? <Icons.check size={16} /> : <Icons.play size={16} />}
                      {chosen(head.node) ? 'Selected' : head.node.depth === 0 ? 'Train any opening' : 'Train this'}
                    </button>
                  )
                ) : (
                  <span className="faint tiny">Pick a line below</span>
                )}
                {!multi && head.node && head.node.depth > 0 && (
                  <button
                    className="icon-btn plain"
                    aria-label={`${stars.has(head.node.id) ? 'Unstar' : 'Star'} ${head.title}`}
                    onClick={() => toggleStar(head.node!.id)}
                  >
                    <Icons.star size={18} filled={stars.has(head.node.id)} />
                  </button>
                )}
                {onStats && head.node && head.node.depth > 0 && (
                  <button className="icon-btn plain" aria-label={`Stats for ${head.title}`} onClick={() => onStats(head.node!.id)}>
                    <Icons.chart size={18} />
                  </button>
                )}
              </div>
            </div>
          </div>
        )}

        {!multi && !searching && (
          <div className="op-side">
            <span className="faint tiny">You play</span>
            <Segmented
              value={selection.color}
              options={CHOICES.map((choice) => ({
                value: choice,
                label: (
                  <span className="op-side-opt">
                    <ColorSquare choice={choice} size={12} />
                    {colorLabel(choice)}
                  </span>
                ),
              }))}
              onChange={(color) => setSelection({ color })}
            />
          </div>
        )}

        <div className="op-sort">
          <Segmented<PickerSort>
            value={sort}
            options={PICKER_SORTS}
            onChange={(pickerSort) => setSettings({ pickerSort })}
          />
        </div>
      </header>

      <div className="op-body">
        {body}
        <div className="spacer" />
      </div>
    </div>
  );
}

function viaMeta(group: PickerGroup, entry: PickerEntry): string {
  const via = group.alsoVia.get(entry.key);
  return via ? `also via ${via.join(', ')}` : moveText(entry.node.sans);
}

function SectionHead({ title, aside }: { title: ReactNode; aside?: ReactNode }) {
  return (
    <div className="section">
      <span>{title}</span>
      {aside !== undefined && <span className="faint tiny">{aside}</span>}
    </div>
  );
}

function SideDot({ side }: { side: Color }) {
  return <i className={`op-dot ${side}`} aria-label={side === 'w' ? 'White' : 'Black'} />;
}

/**
 * Five pips: a flame for sharpness, pages for how much theory. The same two
 * scores on every row, so a list can be read down a column.
 */
function Meter({ kind, value, labelled = false }: { kind: 'sharp' | 'theory'; value: number; labelled?: boolean }) {
  const name = kind === 'sharp' ? 'Sharpness' : 'Theory';
  return (
    <span className={`op-meter ${kind}`} aria-label={`${name} ${value} of 5`} title={`${name} ${value} of 5`}>
      {kind === 'sharp' ? <Icons.flame size={12} filled /> : <Icons.pages size={12} filled />}
      <span className="pips">
        {[1, 2, 3, 4, 5].map((n) => (
          <i key={n} className={n <= value ? 'on' : ''} />
        ))}
      </span>
      {labelled && <span className="op-meter-label">{name}</span>}
    </span>
  );
}

function FamilyCard({
  entry,
  starred,
  chosen,
  onOpen,
}: {
  entry: PickerEntry;
  starred: boolean;
  chosen: boolean;
  onOpen: () => void;
}) {
  return (
    <button className={`op-card${chosen ? ' selected' : ''}`} onClick={onOpen}>
      <div className="op-card-top">
        <SideDot side={entry.side} />
        {starred && <Icons.star size={13} filled />}
        <span className="grow" />
        <span className="faint tiny">{formatGameCount(entry.games)}</span>
      </div>
      <div className="op-card-name">{shortLabel(entry.label)}</div>
      <div className="op-card-scores">
        <Meter kind="sharp" value={entry.sharpness} />
        <Meter kind="theory" value={entry.difficulty} />
      </div>
    </button>
  );
}

/** A still board of the position a move order reaches, for the picker's header. */
export function MiniBoard({ sans, orientation, size = 96 }: { sans: string[]; orientation: Color; size?: number }) {
  const key = sans.join(' ');
  const pieces = useMemo(() => {
    const { fens } = walkSan(key ? key.split(' ') : []);
    return piecesFromFen(fens[fens.length - 1] ?? START_FEN);
  }, [key]);
  const at = new Map(pieces.map((p) => [p.square, p]));
  const files = 'abcdefgh';
  const squares = [];
  for (let r = 0; r < 8; r++) {
    for (let f = 0; f < 8; f++) {
      const file = orientation === 'w' ? f : 7 - f;
      const rank = orientation === 'w' ? 7 - r : r;
      const square = `${files[file]}${rank + 1}`;
      const piece = at.get(square as never);
      squares.push(
        <div key={square} className={(file + rank) % 2 === 0 ? 'd' : 'l'}>
          {piece && <Piece type={piece.type} color={piece.color} />}
        </div>,
      );
    }
  }
  return (
    <div className="op-board" style={{ width: size, height: size }} aria-hidden>
      {squares}
    </div>
  );
}
