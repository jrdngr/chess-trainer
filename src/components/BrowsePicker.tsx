import { useEffect, useMemo, useRef, useState } from 'react';
import { lastMoveOf, walkSan, START_FEN, type Color } from '../chess/core';
import {
  bookItems,
  isHead,
  lineName,
  myLines,
  nextMoves,
  nodeAt,
  recentItems,
  repMoves,
  searchItems,
  shelfRows,
  SHELVES,
  suggestions,
  type BrowseItem,
  type BrowseRow,
} from '../model/browse';
import { ANY_FAVORITE } from '../model/anyFavorite';
import { nodeById, openingTree } from '../model/openingTree';
import { pickerCatalog, sideForPick } from '../model/picker';
import { referenceIndex } from '../model/referenceIndex';
import { rankOf } from '../model/scoring';
import { useStore } from '../store/useStore';
import { Board } from './Board';
import { ColorSquare, SideDot } from './Selection';
import { IconButton, Icons } from './ui';

type Chip = 'mine' | 'suggest' | 'shelves' | 'recent' | 'book';

const CHIPS: { id: Chip; label: string }[] = [
  { id: 'mine', label: 'My lines' },
  { id: 'suggest', label: 'Suggestions' },
  { id: 'shelves', label: 'Shelves' },
  { id: 'recent', label: 'Recent' },
  { id: 'book', label: 'Book' },
];

type SideFilter = 'both' | Color;

const WHY_COLOR = { hole: '#f97316', like: '#2dd4bf', style: '#a855f7' } as const;

/** "1.e4 c5 2.Nf3": the book always starts from the start. */
function moveText(sans: string[]): string {
  return sans.map((san, i) => (i % 2 === 0 ? `${i / 2 + 1}.${san}` : san)).join(' ');
}

/**
 * The full opening picker: a board you can always play on, the name of what
 * is on it, and lists underneath that each move the board somewhere.
 *
 * Choose selects exactly the board's line and closes; the close button leaves
 * the selection as it was. Nothing is selected by tapping a row, which only
 * plays its line out and opens what is under it.
 */
export function BrowsePicker({
  onClose,
  onBack,
  onChoose,
}: {
  onClose: () => void;
  onBack?: () => void;
  /** Hand the board's line over instead of selecting it: onboarding collects openings this way. */
  onChoose?: (sans: string[], side: Color | null) => void;
}) {
  const selection = useStore((s) => s.settings.selection);
  const favorites = useStore((s) => s.settings.favoriteOpenings);
  const repertoires = useStore((s) => s.repertoires);
  const score = useStore((s) => s.score);
  const settings = useStore((s) => s.settings);
  const setSelection = useStore((s) => s.setSelection);
  const toggleStar = useStore((s) => s.toggleStar);

  const index = referenceIndex();
  const tree = openingTree(index);
  const catalog = pickerCatalog(tree);
  const reps = useMemo(() => Object.values(repertoires), [repertoires]);

  const [moves, setMoves] = useState<string[]>(() =>
    selection.opening === ANY_FAVORITE ? [] : nodeById(tree, selection.opening).sans,
  );
  /** The side the line is played from, once a row or the square has said so. */
  const [sideSet, setSide] = useState<Color | null>(() =>
    selection.opening && selection.color !== 'random' ? selection.color : null,
  );
  const [flipped, setFlipped] = useState(false);
  const [chip, setChip] = useState<Chip | null>(null);
  const [trail, setTrail] = useState<{ label: string; items: () => BrowseItem[] }[]>([]);
  const [filter, setFilter] = useState<SideFilter>('both');
  const [searching, setSearching] = useState(false);
  const [query, setQuery] = useState('');
  const [previewed, setPreviewed] = useState<string | null>(null);
  const pane = useRef<HTMLDivElement>(null);

  const { fens } = useMemo(() => walkSan(moves), [moves]);
  const fen = fens[fens.length - 1] ?? START_FEN;
  const node = moves.length ? nodeAt(tree, moves) : null;
  const exact = node && node.depth > 0 && !node.custom ? node : null;
  const side: Color | null = moves.length
    ? sideSet ?? (node ? sideForPick(catalog, node) : null) ?? sideForPick(catalog, nodeById(tree, moves.join(' ')))
    : null;
  const viewSide: Color = side ?? (selection.color === 'b' ? 'b' : 'w');
  const orientation: Color = flipped ? (viewSide === 'w' ? 'b' : 'w') : viewSide;

  const stars = new Set(favorites);
  const stats = exact ? score.nodes[exact.id] : undefined;
  const rank = stats && stats.rated > 0 ? rankOf(stats.rating, stats.rated) : null;

  const goTo = (sans: string[], rowSide?: Color) => {
    setMoves(sans);
    if (rowSide) setSide(rowSide);
    else if (!sans.length) setSide(null);
  };

  const play = (san: string) => {
    setMoves([...moves, san]);
    setPreviewed(null);
  };

  const undo = () => {
    const next = moves.slice(0, -1);
    goTo(next);
    setPreviewed(null);
  };

  const choose = () => {
    // The book's own move order where it has one for this position, so ratings and favorites line up.
    const id = moves.length ? node?.id ?? moves.join(' ') : '';
    if (onChoose) {
      if (id) onChoose(id.split(' '), side);
      onClose();
      return;
    }
    setSelection(id ? { opening: id, ...(side ? { color: side } : {}) } : { opening: '' });
    onClose();
  };

  const pickChip = (next: Chip) => {
    setChip(chip === next ? null : next);
    setTrail([]);
    setSearching(false);
    setQuery('');
  };

  const tapRow = (row: BrowseRow) => {
    goTo(row.sans, row.side);
    setPreviewed(row.key);
    if (row.open) {
      const open = row.open;
      setTrail([...trail, { label: row.label, items: open }]);
      pane.current?.scrollTo({ top: 0 });
    }
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  const rootItems = useMemo((): BrowseItem[] => {
    switch (chip) {
      case 'mine':
        return myLines(reps, index, tree, favorites);
      case 'suggest':
        return suggestions(reps, index, tree, catalog);
      case 'recent':
        return recentItems(tree, catalog, score);
      case 'book':
        return bookItems(catalog);
      default:
        return [];
    }
  }, [chip, reps, index, tree, catalog, favorites, score]);

  const searchResults = useMemo(
    () => (searching ? searchItems(query, reps, index, tree, catalog) : []),
    [searching, query, reps, index, tree, catalog],
  );

  const mine = useMemo(() => repMoves(reps), [reps]);
  const next = useMemo(() => nextMoves(index, tree, catalog, moves, mine), [index, tree, catalog, moves, mine]);

  /* the list */
  const rowView = (row: BrowseRow, first: boolean) => {
    const at = nodeAt(tree, row.sans);
    const rowStats = at ? score.nodes[at.id] : undefined;
    const rowRank = rowStats && rowStats.rated > 0 ? rankOf(rowStats.rating, rowStats.rated) : null;
    return (
      <button
        key={row.key}
        className={`bp-row${first ? ' first' : ''}${previewed === row.key ? ' previewed' : ''}`}
        onClick={() => tapRow(row)}
      >
        <SideDot side={row.side} />
        <span className="bp-row-text">
          <span className="bp-row-name">{row.label}</span>
          {row.why && (
            <span
              className="bp-why"
              style={{ color: WHY_COLOR[row.why.kind], background: `${WHY_COLOR[row.why.kind]}24` }}
            >
              {row.why.text}
            </span>
          )}
        </span>
        {at && stars.has(at.id) && (
          <span className="bp-star">
            <Icons.star size={14} filled />
          </span>
        )}
        {rowRank?.held && (
          <span className="bp-tier" style={{ color: rowRank.held.color }}>
            {rowRank.held.name}
          </span>
        )}
      </button>
    );
  };

  const listView = (items: BrowseItem[], filtered: boolean) => {
    const shown = filtered && filter !== 'both' ? dropEmptyHeads(items.filter((i) => isHead(i) || i.side === filter)) : items;
    if (!shown.length) return <div className="bp-empty">Nothing here yet</div>;
    const blocks: { head?: string; rows: BrowseRow[] }[] = [];
    for (const item of shown) {
      if (isHead(item)) blocks.push({ head: item.head, rows: [] });
      else {
        if (!blocks.length) blocks.push({ rows: [] });
        blocks[blocks.length - 1].rows.push(item);
      }
    }
    return blocks.map((block, i) => (
      <div className="bp-list" key={`${block.head ?? ''}${i}`}>
        {block.head && <div className="bp-head">{block.head}</div>}
        {block.rows.map((row, j) => rowView(row, j === 0 && !block.head))}
      </div>
    ));
  };

  const crumbs = chip ? [{ label: CHIPS.find((c) => c.id === chip)!.label }, ...trail] : [];
  const sideToggle = (
    <div className="bp-seg" role="group" aria-label="Side">
      {(['both', 'w', 'b'] as SideFilter[]).map((value) => (
        <button key={value} className={filter === value ? 'on' : ''} onClick={() => setFilter(value)}>
          {value === 'both' ? 'Both' : value === 'w' ? 'W' : 'B'}
        </button>
      ))}
    </div>
  );

  const body = (() => {
    if (searching) {
      if (!query.trim()) return null;
      return listView(searchResults, false);
    }
    if (!chip) {
      return (
        <div className="bp-list">
          <div className="bp-head">Next</div>
          {next.length === 0 && <div className="bp-empty inset">The book has nothing after this</div>}
          {next.map((move) => (
            <button key={move.san} className="bp-move" onClick={() => play(move.san)}>
              <span className="bp-san">{move.label}</span>
              <span className="bp-move-name">{move.name}</span>
              {move.mine && <i className="bp-mine" aria-label="In your Playbook" />}
              <span className="bp-share">{Math.round(move.share)}%</span>
            </button>
          ))}
        </div>
      );
    }
    const items = trail.length ? trail[trail.length - 1].items() : chip === 'shelves' ? null : rootItems;
    return (
      <>
        <div className="bp-ctl">
          <div className="bp-crumbs">
            {crumbs.map((crumb, i) => (
              <span key={i} className="bp-crumb">
                {i > 0 && <span className="sep">{'›'}</span>}
                <button className={i === crumbs.length - 1 ? 'here' : ''} onClick={() => setTrail(trail.slice(0, i))}>
                  {crumb.label}
                </button>
              </span>
            ))}
          </div>
          {items && sideToggle}
        </div>
        {items ? (
          listView(items, true)
        ) : (
          <div className="bp-shelves">
            {SHELVES.map((shelf) => {
              const rows = shelfRows(catalog, shelf);
              return (
                <button
                  key={shelf.id}
                  className="bp-shelf"
                  onClick={() => setTrail([{ label: shelf.label, items: () => rows }])}
                >
                  <i style={{ background: shelf.color }} />
                  <b>{shelf.label}</b>
                  <span>{rows.length}</span>
                </button>
              );
            })}
          </div>
        )}
      </>
    );
  })();

  return (
    <div className="bp">
      <div className="bp-top">
        {onBack ? (
          <IconButton label="Back" onClick={onBack}>
            <Icons.back size={20} />
          </IconButton>
        ) : (
          <IconButton label="Close" onClick={onClose}>
            <Icons.close size={20} />
          </IconButton>
        )}
        <span className="bp-title">Openings</span>
        <IconButton label="Undo" onClick={undo} disabled={!moves.length}>
          <Icons.undo size={20} />
        </IconButton>
        <IconButton label="Flip board" onClick={() => setFlipped(!flipped)}>
          <Icons.flip size={20} />
        </IconButton>
        <IconButton
          label="Search"
          onClick={() => {
            setSearching(!searching);
            setQuery('');
          }}
        >
          <Icons.search size={20} />
        </IconButton>
        {onBack && (
          <IconButton label="Close" onClick={onClose}>
            <Icons.close size={20} />
          </IconButton>
        )}
      </div>

      <div className="bp-board">
        <Board
          fen={fen}
          orientation={orientation}
          onMove={(move) => play(move.san)}
          movableFor="both"
          lastMove={lastMoveOf(moves)}
          showCoordinates={settings.showCoordinates}
          theme={settings.boardTheme}
        />
      </div>

      <div className="bp-bar">
        <button
          className="bp-side"
          aria-label="Side"
          disabled={!moves.length}
          onClick={() => setSide(viewSide === 'w' ? 'b' : 'w')}
        >
          <ColorSquare choice={side ?? selection.color} size={16} />
        </button>
        <span className="bp-name">
          <b className="truncate">{lineName(tree, catalog, moves)}</b>
          <span className="truncate">{moves.length ? moveText(moves) : 'Every line'}</span>
        </span>
        {rank?.held && (
          <span className="bp-rank" style={{ color: rank.held.color }}>
            {rank.held.name} {Math.round(stats!.rating)}
          </span>
        )}
        {exact && (
          <button
            className="icon-btn plain"
            aria-label={`${stars.has(exact.id) ? 'Remove from' : 'Add to'} favorites`}
            onClick={() => toggleStar(exact.id)}
          >
            <Icons.star size={20} filled={stars.has(exact.id)} />
          </button>
        )}
        <button className="bp-choose" onClick={choose}>
          Choose
        </button>
      </div>

      {searching ? (
        <input
          className="field bp-search"
          autoFocus
          placeholder="Name, ECO or moves"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
      ) : (
        <div className="bp-chips">
          {CHIPS.map((c) => (
            <button key={c.id} className={`bp-chip${chip === c.id ? ' on' : ''}`} onClick={() => pickChip(c.id)}>
              {c.label}
            </button>
          ))}
        </div>
      )}

      <div className="bp-pane" ref={pane}>
        {body}
      </div>
    </div>
  );
}

/** A heading left with nothing under it, once the side filter has had its say. */
function dropEmptyHeads(items: BrowseItem[]): BrowseItem[] {
  return items.filter((item, i) => !isHead(item) || (items[i + 1] !== undefined && !isHead(items[i + 1])));
}
