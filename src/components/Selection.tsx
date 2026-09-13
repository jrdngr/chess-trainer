import { useMemo, useState } from 'react';
import { sansToMoveText } from '../chess/core';
import type { ColorChoice } from '../model/openingRun';
import {
  ancestorsOf,
  descendantsOf,
  nodeById,
  openingTree,
  orderedChildren,
  type OpeningNode,
  type OpeningTree,
} from '../model/openingTree';
import { formatGameCount } from '../model/reference';
import { referenceIndex } from '../model/referenceIndex';
import { colorLabel } from '../model/selection';
import { useStore } from '../store/useStore';
import { ChoiceRow, Icons, Section, Sheet } from './ui';

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

/**
 * The global selection, at the top of the screens where it can be changed.
 *
 * Two taps: the square opens the colour picker, the name opens the opening
 * tree. Screens that only report the selection use `selectionText` instead.
 */
export function SelectionBar() {
  const selection = useStore((s) => s.settings.selection);
  const openStats = useStore((s) => s.openStats);
  const [picking, setPicking] = useState<'color' | 'opening' | null>(null);
  const tree = openingTree(referenceIndex());
  const node = nodeById(tree, selection.opening);

  return (
    <>
      <div className="selection-bar">
        <button className="pick color" onClick={() => setPicking('color')} aria-label="Colour">
          <ColorSquare choice={selection.color} size={22} />
        </button>
        <button className="pick opening" onClick={() => setPicking('opening')}>
          <span className="grow truncate">{node.name}</span>
          {node.depth > 0 && <span className="eco">{node.eco ?? moveText(node)}</span>}
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

/** "White · Sicilian: Najdorf" — the selection as a subtitle. */
export function selectionText(color: ColorChoice, openingId: string): string {
  const node = nodeById(openingTree(referenceIndex()), openingId);
  return `${colorLabel(color)} · ${node.name}`;
}

function moveText(node: OpeningNode): string {
  return sansToMoveText(node.sans);
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
 * The opening tree as a picker.
 *
 * One level at a time, with a breadcrumb back up. At every level the row at
 * the top selects the level itself — "everything in the Sicilian" — and the
 * rows under it are its children, starred first and then most played. A row
 * with children opens them; a leaf selects itself. Any row can be starred.
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
  const selection = useStore((s) => s.settings.selection);
  const starred = useStore((s) => s.settings.favoriteOpenings);
  const setSelection = useStore((s) => s.setSelection);
  const toggleStar = useStore((s) => s.toggleStar);
  const tree = openingTree(referenceIndex());
  const selected = nodeById(tree, selection.opening);

  /** Open on the level the selection sits in. */
  const [at, setAt] = useState<string>(selected.parentId ?? '');
  const [query, setQuery] = useState('');
  const here = nodeById(tree, at);
  const trail = ancestorsOf(tree, here.id);

  // Starred openings have their own section above, so the levels themselves
  // stay in popularity order.
  const children = useMemo(() => orderedChildren(here, []), [here]);
  const matches = useMemo(() => search(tree, query, starred), [tree, query, starred]);
  /**
   * Everything starred anywhere under this level, so a starred variation is at
   * the top of the picker wherever it was starred from — not only at its own
   * level, three taps down.
   */
  const starredHere = useMemo(() => {
    const stars = new Set(starred);
    return descendantsOf(here)
      .filter((node) => stars.has(node.id))
      .sort((a, b) => a.depth - b.depth || b.games - a.games || a.name.localeCompare(b.name));
  }, [here, starred]);

  const choose = (node: OpeningNode) => {
    setSelection({ opening: node.id });
    setQuery('');
    onClose();
  };

  const row = (node: OpeningNode, showTrail: boolean) => (
    <OpeningRow
      key={node.id}
      node={node}
      trail={showTrail ? ancestorsOf(tree, node.id).slice(0, -1) : []}
      selected={selection.opening === node.id}
      starred={starred.includes(node.id)}
      onOpen={node.children.length && !showTrail ? () => setAt(node.id) : undefined}
      onPick={() => choose(node)}
      onStar={() => toggleStar(node.id)}
      onStats={onStats ? () => onStats(node.id) : undefined}
    />
  );

  return (
    <Sheet open={open} onClose={onClose} title="Opening" from="top">
      <input
        className="field"
        placeholder="Search by name, ECO or moves"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
      />

      {query.trim() ? (
        <>
          <Section title="Matches" aside={matches.length} />
          {matches.length === 0 ? (
            <div className="card small muted">Nothing matches that.</div>
          ) : (
            <div className="list">{matches.map((node) => row(node, true))}</div>
          )}
        </>
      ) : (
        <>
          <div className="crumbs">
            <button className={trail.length === 0 ? 'here' : ''} onClick={() => setAt('')}>
              Any
            </button>
            {trail.map((node, i) => (
              <span className="crumb" key={node.id}>
                <Icons.chevron size={12} />
                <button
                  className={i === trail.length - 1 ? 'here' : ''}
                  onClick={() => setAt(node.id)}
                >
                  {node.depth === 1 ? moveText(node) : node.name}
                </button>
              </span>
            ))}
          </div>

          {starredHere.length > 0 && (
            <>
              <Section title="Starred" aside={starredHere.length} />
              <div className="list">{starredHere.map((node) => row(node, true))}</div>
            </>
          )}

          <Section title={here.depth === 0 ? 'Everything' : 'This level'} />
          <div className="list">
            <ChoiceRow
              title={here.depth === 0 ? 'Any opening' : `All of ${here.name}`}
              meta={
                here.depth === 0
                  ? 'Every line the book knows'
                  : `${here.eco ? `${here.eco} · ` : ''}${moveText(here)}`
              }
              selected={selection.opening === here.id}
              onSelect={() => choose(here)}
            />
          </div>

          {children.length > 0 && (
            <>
              <Section
                title={here.depth === 0 ? 'First moves' : here.depth === 1 ? 'Openings' : 'Variations'}
                aside="most played first"
              />
              <div className="list">{children.map((node) => row(node, false))}</div>
            </>
          )}
        </>
      )}
      <div className="spacer" />
    </Sheet>
  );
}

function OpeningRow({
  node,
  trail,
  selected,
  starred,
  onOpen,
  onPick,
  onStar,
  onStats,
}: {
  node: OpeningNode;
  /** Where it sits, for a search result. */
  trail: OpeningNode[];
  selected: boolean;
  starred: boolean;
  onOpen?: () => void;
  onPick: () => void;
  onStar: () => void;
  onStats?: () => void;
}) {
  const meta = trail.length
    ? trail.map((n) => (n.depth === 1 ? moveText(n) : n.name)).join(' › ')
    : `${node.eco ? `${node.eco} · ` : ''}${moveText(node)}${node.games > 0 ? ` · ${formatGameCount(node.games)}` : ''}`;
  return (
    <div className={`list-row${selected ? ' selected' : ''}`}>
      <button
        className="icon-btn plain"
        aria-label={`${starred ? 'Unstar' : 'Star'} ${node.name}`}
        onClick={onStar}
      >
        <Icons.star size={18} filled={starred} />
      </button>
      <button className="grow row" style={{ minWidth: 0 }} onClick={onOpen ?? onPick}>
        <span className="grow" style={{ minWidth: 0 }}>
          <div className="title truncate">{node.name}</div>
          <div className="meta truncate">{meta}</div>
        </span>
        {selected && <Icons.check size={18} />}
      </button>
      {onStats && (
        <button className="icon-btn plain" aria-label={`Stats for ${node.name}`} onClick={onStats}>
          <Icons.chart size={18} />
        </button>
      )}
      {onOpen && (
        <button className="icon-btn plain" aria-label={`Open ${node.name}`} onClick={onOpen}>
          <Icons.chevron size={18} />
        </button>
      )}
    </div>
  );
}

/** Every node whose name, ECO or move order contains the query, starred first. */
function search(tree: OpeningTree, query: string, starred: string[]): OpeningNode[] {
  const needle = query.trim().toLowerCase();
  if (!needle) return [];
  const stars = new Set(starred);
  return descendantsOf(tree.root)
    .filter(
      (node) =>
        node.name.toLowerCase().includes(needle) ||
        (node.eco ?? '').toLowerCase().startsWith(needle) ||
        node.id.toLowerCase().includes(needle),
    )
    .sort(
      (a, b) =>
        Number(stars.has(b.id)) - Number(stars.has(a.id)) || b.games - a.games || a.depth - b.depth,
    )
    .slice(0, 40);
}
