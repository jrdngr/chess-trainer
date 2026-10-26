import { useMemo, useState, type ReactNode } from 'react';
import { lastMoveOf, walkSan, piecesFromFen, START_FEN, type Color } from '../chess/core';
import type { ColorChoice } from '../model/openingRun';
import type { Repertoire } from '../model/types';
import { nodeById, openingTree, type OpeningNode, type OpeningTree } from '../model/openingTree';
import {
  entryForNode,
  entryTrail,
  pickerCatalog,
  sideForPick,
  type PickerCatalog,
} from '../model/picker';
import { referenceIndex } from '../model/referenceIndex';
import { colorLabel } from '../model/selection';
import { ANY_FAVORITE } from '../model/anyFavorite';
import { useStore } from '../store/useStore';
import { BrowsePicker } from './BrowsePicker';
import { Piece } from './Pieces';
import { TierBar } from './ScoreBar';
import { ChoiceRow, Icons, Segmented, Sheet } from './ui';

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
  if (openingId === ANY_FAVORITE) return ['Any favorite'];
  const node = nodeById(tree, openingId);
  if (node.depth === 0) return ['Any opening'];
  const entry = entryForNode(catalog, node);
  const trail = entry ? entryTrail(entry).map((e) => shortLabel(e.label)) : [node.name];
  if (!node.custom) return trail;
  // A line played past its name: the name, then the moves it goes on with.
  const named = node.parentId ? tree.byId.get(node.parentId) : undefined;
  const from = named && named.sans.every((san, i) => node.sans[i] === san) ? named.sans.length : 0;
  return from ? [...trail, moveRange(node.sans, from)] : trail;
}

/** "6.e3 e6" — the moves of a line from one ply on, numbered as played. */
function moveRange(sans: string[], from: number): string {
  return sans
    .slice(from)
    .map((san, i) => {
      const ply = from + i;
      const n = Math.floor(ply / 2) + 1;
      return ply % 2 === 0 ? `${n}.${san}` : i === 0 ? `${n}...${san}` : san;
    })
    .join(' ');
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
/** `trailing` sits at the bar's right end, like Home's settings gear. */
export function SelectionBar({ trailing }: { trailing?: ReactNode } = {}) {
  const selection = useStore((s) => s.settings.selection);
  const [picking, setPicking] = useState<'color' | 'quick' | 'opening' | null>(null);
  const trail = selectionTrail(selection.opening);

  return (
    <>
      <div className="selection-bar">
        <button className="pick color" onClick={() => setPicking('color')} aria-label="Color">
          <ColorSquare choice={selection.color} size={22} />
        </button>
        <button className="pick opening" onClick={() => setPicking('quick')}>
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
        {trailing}
      </div>
      <ColorPicker open={picking === 'color'} onClose={() => setPicking(null)} />
      <QuickPicker
        open={picking === 'quick'}
        onClose={() => setPicking(null)}
        onBrowse={() => setPicking('opening')}
      />
      <OpeningPicker
        open={picking === 'opening'}
        onClose={() => setPicking(null)}
        onBack={() => setPicking('quick')}
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

/** The first moves the quick picker offers, as tree ids. */
const QUICK_FIRST_MOVES = ['e4', 'd4', 'c4', 'Nf3'];
/** Favorites shown before "Show all". */
const QUICK_FAVORITES = 6;

/**
 * The quick picker: the few picks most sessions want, one tap each.
 *
 * Any opening, your favorites (the ones played last first), and the common
 * first moves. A favorite sets the side the way the full picker does; a first
 * move keeps the side you have, so 1.e4 as Black means facing it. Everything
 * else is one tap further, in the full picker.
 */
export function QuickPicker({
  open,
  onClose,
  onBrowse,
}: {
  open: boolean;
  onClose: () => void;
  onBrowse: () => void;
}) {
  const selection = useStore((s) => s.settings.selection);
  const favorites = useStore((s) => s.settings.favoriteOpenings);
  const score = useStore((s) => s.score);
  const setSelection = useStore((s) => s.setSelection);
  const [showAll, setShowAll] = useState(false);
  if (!open) return null;

  const { tree, catalog } = catalogNow();
  const lastAt = (id: string) => score.nodes[id]?.lastAt ?? 0;
  const mine = favorites
    .map((id, i) => ({ node: tree.byId.get(id), i }))
    .filter((f): f is { node: OpeningNode; i: number } => Boolean(f.node) && f.node!.depth > 0)
    .sort((a, b) => lastAt(b.node.id) - lastAt(a.node.id) || a.i - b.i)
    .map(({ node }) => ({ node, side: sideForPick(catalog, node) ?? 'w', label: favoriteLabel(catalog, node) }));
  const shown = showAll ? mine : mine.slice(0, QUICK_FAVORITES);
  const firstMoves = QUICK_FIRST_MOVES.map((id) => tree.byId.get(id)).filter((node): node is OpeningNode =>
    Boolean(node),
  );

  const choose = (patch: Parameters<typeof setSelection>[0]) => {
    setSelection(patch);
    onClose();
  };
  const isChosen = (id: string) => (selection.opening === id ? ' selected' : '');

  return (
    <Sheet open={open} onClose={onClose} title="Opening" from="top">
      <div className="qp">
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

        <button className={`qp-tile qp-any${isChosen('')}`} onClick={() => choose({ opening: '' })}>
          <span className="qp-any-name">Any opening</span>
        </button>

        {mine.length > 0 && (
          <button className={`qp-tile qp-any${isChosen(ANY_FAVORITE)}`} onClick={() => choose({ opening: ANY_FAVORITE })}>
            <span className="qp-any-name">Any favorite</span>
          </button>
        )}

        {mine.length > 0 && (
          <div>
            <SectionHead title="Favorites" />
            <div className="qp-grid">
              {shown.map(({ node, side, label }) => {
                const stats = score.nodes[node.id];
                return (
                  <button
                    key={node.id}
                    className={`qp-tile${isChosen(node.id)}`}
                    onClick={() => choose({ opening: node.id, color: side })}
                  >
                    <span className="qp-name">
                      <SideDot side={side} />
                      <span className="truncate">{label}</span>
                    </span>
                    <TierBar rating={stats?.rating ?? 0} rated={stats?.rated ?? 0} />
                  </button>
                );
              })}
            </div>
            {mine.length > QUICK_FAVORITES && (
              <button className="op-more" onClick={() => setShowAll(!showAll)}>
                {showAll ? 'Show fewer' : `Show all ${mine.length}`}
              </button>
            )}
          </div>
        )}

        <div>
          <SectionHead title="First move" />
          <div className="qp-moves">
            {firstMoves.map((node) => (
              <button key={node.id} className={`qp-tile qp-move${isChosen(node.id)}`} onClick={() => choose({ opening: node.id })}>
                {moveText(node.sans)}
              </button>
            ))}
          </div>
        </div>

        <button className="qp-browse" onClick={onBrowse}>
          <span className="grow">Browse all openings</span>
          <Icons.chevron size={16} />
        </button>
      </div>
    </Sheet>
  );
}

/** A favorite's name as the picker shows it, short where the book's is long. */
function favoriteLabel(catalog: PickerCatalog, node: OpeningNode): string {
  const entry = entryForNode(catalog, node);
  return shortLabel(entry?.label ?? node.name);
}

/** Your favorites as the quick picker lists them: the node, the side it is played from, and its short name. */
export function favoriteEntries(ids: string[]): { node: OpeningNode; side: Color; label: string }[] {
  const { tree, catalog } = catalogNow();
  return ids
    .map((id) => tree.byId.get(id))
    .filter((node): node is OpeningNode => Boolean(node) && node!.depth > 0)
    .map((node) => ({ node, side: sideForPick(catalog, node) ?? 'w', label: favoriteLabel(catalog, node) }));
}

/**
 * The opening picker, over the whole screen: a board to play the line on, and
 * lists under it that set the board up (see `BrowsePicker`).
 */
export function OpeningPicker({
  open,
  onClose,
  onBack,
  onChoose,
  playbook,
  picked,
}: {
  open: boolean;
  onClose: () => void;
  /** Back to where the picker was opened from. */
  onBack?: () => void;
  /** Take the chosen line instead of selecting it (see `BrowsePicker`). */
  onChoose?: (sans: string[], side: Color | null) => void;
  /** The Playbook the lists read, when it is not the saved one (see `BrowsePicker`). */
  playbook?: Repertoire[];
  picked?: { sans: string[]; color: Color }[];
}) {
  if (!open) return null;
  return (
    <div className="op-screen bp-screen" role="dialog" aria-label="Opening">
      <BrowsePicker onClose={onClose} onBack={onBack} onChoose={onChoose} playbook={playbook} picked={picked} />
    </div>
  );
}

/** "1.e4 c5 2.Nf3" without playing the moves: the book always starts from the start. */
function moveText(sans: string[]): string {
  return sans.map((san, i) => (i % 2 === 0 ? `${i / 2 + 1}.${san}` : san)).join(' ');
}

function SectionHead({ title, aside }: { title: ReactNode; aside?: ReactNode }) {
  return (
    <div className="section">
      <span>{title}</span>
      {aside !== undefined && <span className="faint tiny">{aside}</span>}
    </div>
  );
}

export function SideDot({ side }: { side: Color }) {
  return <i className={`op-dot ${side}`} aria-label={side === 'w' ? 'White' : 'Black'} />;
}

/**
 * A still board of the position a move order reaches, for the picker's
 * header. `lastMove` lights the move that reached it.
 */
export function MiniBoard({
  sans,
  orientation,
  size = 96,
  lastMove = false,
}: {
  sans: string[];
  orientation: Color;
  size?: number;
  lastMove?: boolean;
}) {
  const key = sans.join(' ');
  const pieces = useMemo(() => {
    const { fens } = walkSan(key ? key.split(' ') : []);
    return piecesFromFen(fens[fens.length - 1] ?? START_FEN);
  }, [key]);
  const lit = useMemo(() => {
    const move = lastMove && key ? lastMoveOf(key.split(' ')) : null;
    return move ? [move.from, move.to] : [];
  }, [key, lastMove]);
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
        <div key={square} className={`${(file + rank) % 2 === 0 ? 'd' : 'l'}${lit.includes(square as never) ? ' hl' : ''}`}>
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
