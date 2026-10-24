import { useMemo, useState } from 'react';
import { ExtensionGraph } from '../components/ExtensionGraph';
import { SideSquare } from '../components/OpeningPlate';
import { MiniBoard } from '../components/Selection';
import { AppBar, Empty, haptic, Icons, Segmented, Sheet, toast } from '../components/ui';
import { fenTurn, sansToMoveText } from '../chess/core';
import { extensionRoot, extensionRoots, keptCurrent, layoutGraph } from '../model/extensionGraph';
import { treeKinds, type MoveKind } from '../model/extensions';
import { openingsIn, type DerivedOpening } from '../model/openings';
import { referenceIndex } from '../model/referenceIndex';
import { pathTo, subtreeIds } from '../model/repertoire';
import { bookMoves } from '../model/survival';
import { moveLabel } from '../model/tidy';
import type { Repertoire } from '../model/types';
import { repertoireList, useStore } from '../store/useStore';

/** One opening that has extensions in it, as the review lists it. */
export interface ExtensionOpening {
  rep: Repertoire;
  opening: DerivedOpening;
  kinds: Map<string, MoveKind>;
  /** Its extensions, each by its first move. */
  roots: string[];
  /** Of those, the ones not reviewed yet. */
  open: number;
  /** Saved mistakes, wherever they sit in an extension. */
  mistakes: number;
}

/** Every opening with an extension in it, over both sides. */
export function useExtensionOpenings(): ExtensionOpening[] {
  const repertoires = useStore((s) => s.repertoires);
  const repertoireOrder = useStore((s) => s.repertoireOrder);
  return useMemo(() => {
    const index = referenceIndex();
    const out: ExtensionOpening[] = [];
    for (const rep of repertoireList({ repertoires, repertoireOrder })) {
      const kinds = treeKinds(rep, index);
      const roots = extensionRoots(rep, kinds);
      if (!roots.length) continue;
      for (const opening of openingsIn(rep, index)) {
        const inside = new Set(subtreeIds(rep, opening.rootId));
        const above = new Set(pathTo(rep, opening.rootId).map((node) => node.id));
        // An extension that starts above the opening's root holds the whole opening, so it belongs to it too.
        const mine = roots.filter((root) => inside.has(root.id) || above.has(root.id));
        if (!mine.length) continue;
        const ids = new Set(mine.flatMap((root) => subtreeIds(rep, root.id)));
        out.push({
          rep,
          opening,
          kinds,
          roots: mine.map((root) => root.id),
          open: mine.filter((root) => !keptCurrent(rep, root)).length,
          mistakes: [...ids].filter((id) => kinds.get(id) === 'mistake').length,
        });
      }
    }
    return out;
  }, [repertoires, repertoireOrder]);
}

/**
 * The Extensions review: one opening at a time, drawn as a graph of your
 * lines with the extensions outlined. Tap a move to see its position; Keep or
 * Remove act on the whole extension the move belongs to, from its first move
 * off the book. A mistake of yours can be switched to the book's move, the way
 * a Tidy switch works.
 */
export function ExtensionsScreen({ onBack }: { onBack: () => void }) {
  const openings = useExtensionOpenings();
  const removeNode = useStore((s) => s.removeNode);
  const tidyKeep = useStore((s) => s.tidyKeep);
  const tidySwitch = useStore((s) => s.tidySwitch);
  const [pickedId, setPickedId] = useState<string | null>(null);
  const [choosing, setChoosing] = useState(false);
  const [extOnly, setExtOnly] = useState(false);
  const [selected, setSelected] = useState<string | null>(null);

  const current = openings.find((o) => o.opening.id === pickedId) ?? openings[0] ?? null;
  const index = referenceIndex();
  const rows = useMemo(
    () => (current ? layoutGraph(current.rep, index, current.kinds, current.opening.rootId, { extOnly }) : []),
    [current, index, extOnly],
  );

  if (!current) {
    return (
      <>
        <AppBar title="Extensions" onBack={onBack} />
        <div className="screen">
          <Empty title="No extensions" hint="Every move in your Playbook is a book move." />
        </div>
      </>
    );
  }

  const { rep, opening, kinds } = current;
  const cells = rows.flatMap((row) => row.cells.filter((cell) => cell.nodeId));
  const firstExt = cells.find((cell) => cell.kind !== 'book')?.nodeId ?? cells[0]?.nodeId ?? null;
  const selId = selected && rep.nodes[selected] && cells.some((c) => c.nodeId === selected) ? selected : firstExt;
  const sel = selId ? rep.nodes[selId] : null;
  const selPath = sel ? pathTo(rep, sel.id) : [];
  const selKind = sel ? (kinds.get(sel.id) ?? 'book') : 'book';
  const root = sel ? extensionRoot(rep, kinds, sel.id) : null;
  const rootPly = root ? pathTo(rep, root.id).length - 1 : 0;
  const size = root ? subtreeIds(rep, root.id).length : 0;
  const kept = root ? keptCurrent(rep, root) : false;
  const yours = sel ? fenTurn(sel.fenBefore) === rep.color : false;
  const bookMove = sel && selKind === 'mistake' && yours ? bookMoves(index, sel.fenBefore).find((san) => san !== sel.san) : undefined;

  const select = (nodeId: string | null) => setSelected(nodeId);

  const onRemove = () => {
    if (!root) return;
    const label = moveLabel(rootPly, root.san);
    const undo = removeNode(rep.id, root.id);
    if (!undo) return;
    haptic(12);
    select(null);
    toast(`Removed ${label}`, { label: 'Undo', run: undo });
  };

  const onKeep = () => {
    if (!root) return;
    tidyKeep(rep.id, root.id);
    haptic(8);
    toast(`Kept ${moveLabel(rootPly, root.san)}`);
  };

  const onSwitch = () => {
    if (!sel || !bookMove) return;
    const ply = selPath.length - 1;
    const undo = tidySwitch(rep.id, sel.id, bookMove);
    if (!undo) return;
    haptic(12);
    select(null);
    toast(`Switched to ${moveLabel(ply, bookMove)}`, { label: 'Undo', run: undo });
  };

  return (
    <>
      <AppBar title="Extensions" onBack={onBack} />
      <div className="screen">
        <button className="ext-head" onClick={() => setChoosing(true)} disabled={openings.length < 2}>
          <SideSquare color={rep.color} />
          <span className="truncate">{opening.name}</span>
          {openings.length > 1 && <Icons.down size={16} />}
        </button>

        {sel && (
          <div className="ext-peek">
            <MiniBoard sans={selPath.map((n) => n.san)} orientation={rep.color} size={100} lastMove />
            <div className="info">
              <span className={`move-tag${selKind === 'book' ? '' : ' ext'}`}>
                {moveLabel(selPath.length - 1, sel.san)}
                {selKind === 'mistake' && <Icons.warn size={15} />}
              </span>
              {root && (
                <span className="count">
                  {size} {size === 1 ? 'move' : 'moves'}
                </span>
              )}
            </div>
          </div>
        )}

        <div className="ext-prefix">
          <span className="movetext">{sansToMoveText(opening.path)}</span>
          <Segmented
            value={extOnly ? 'ext' : 'all'}
            options={[
              { value: 'all', label: 'All' },
              { value: 'ext', label: 'Extensions' },
            ]}
            onChange={(v) => setExtOnly(v === 'ext')}
          />
        </div>

        <div className="ext-scroll">
          <ExtensionGraph rows={rows} rootPly={opening.path.length} selected={selId} onSelect={select} />
        </div>

        {root && (
          <div className="ext-actions">
            {bookMove && (
              <button className="btn accent block" onClick={onSwitch}>
                Switch to {moveLabel(selPath.length - 1, bookMove)}
              </button>
            )}
            <div className="row gap-8">
              <button className="btn grow" onClick={onKeep} disabled={kept}>
                {kept ? 'Kept' : 'Keep'}
              </button>
              <button className="btn danger grow" onClick={onRemove}>
                Remove
              </button>
            </div>
          </div>
        )}
      </div>

      <Sheet open={choosing} onClose={() => setChoosing(false)} title="Extensions">
        <div className="list">
          {openings.map((o) => (
            <button
              key={o.opening.id}
              className="list-row"
              onClick={() => {
                setPickedId(o.opening.id);
                select(null);
                setChoosing(false);
              }}
            >
              <SideSquare color={o.rep.color} />
              <span className="grow title truncate">{o.opening.name}</span>
              {o.mistakes > 0 && (
                <span className="ext-pill mistake">
                  <Icons.warn size={12} />
                  {o.mistakes}
                </span>
              )}
              <span className="ext-pill">{o.roots.length}</span>
            </button>
          ))}
        </div>
      </Sheet>
    </>
  );
}
